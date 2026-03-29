#!/bin/bash
set -e

MODELS=(
    "gpt2:gpt2-124M"
    "gpt2-medium:gpt2-medium-345M"
    "gpt2-large:gpt2-large-774M"
    "gpt2-xl:gpt2-xl-1558M"
)

RESULTS_FILE="$HOME/results.csv"

# Ensure header exists
if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,gpu,driver,method,workload,checkpoint_ms,restore_ms,checkpoint_size_mb,correct" > "$RESULTS_FILE"
fi

for MODEL_ENTRY in "${MODELS[@]}"; do
    MODEL_NAME="${MODEL_ENTRY%%:*}"
    MODEL_LABEL="${MODEL_ENTRY##*:}"
    
    echo ""
    echo "========================================"
    echo "Benchmarking: $MODEL_NAME ($MODEL_LABEL)"
    echo "========================================"
    
    # Create inference script for this model
    cat > ~/inference_current.py << PYEOF
from transformers import pipeline
import time

print("Loading $MODEL_NAME...")
pipe = pipeline("text-generation", model="$MODEL_NAME", device=0)
print("Model loaded on GPU")

count = 0
while True:
    result = pipe("The weather today is", max_new_tokens=20)
    count += 1
    print(f"Inference {count}: {result[0]['generated_text'][:50]}")
    time.sleep(2)
PYEOF

    # Kill any existing inference process
    pkill -f "inference_current" 2>/dev/null || true
    sleep 3

    # Start as session leader
    setsid python3 ~/inference_current.py </dev/null >~/current.log 2>&1 &
    
    # Wait for model to load - bigger models need more time
    echo "Waiting for model to load..."
    WAIT=30
    if [[ "$MODEL_NAME" == "gpt2-xl" ]]; then WAIT=60; fi
    if [[ "$MODEL_NAME" == "gpt2-large" ]]; then WAIT=45; fi
    sleep $WAIT

    PID=$(pgrep -f "inference_current" | head -1)
    if [ -z "$PID" ]; then
        echo "ERROR: Process failed to start for $MODEL_NAME"
        cat ~/current.log | tail -10
        continue
    fi
    echo "PID: $PID"

    # Verify on GPU
    nvidia-smi | grep python3 || echo "Warning: not visible in nvidia-smi yet"
    tail -3 ~/current.log

    # Run 3 benchmark cycles
    for i in 1 2 3; do
        rm -rf ~/demo; mkdir -p ~/demo

        T1=$(date +%s%N)
        ./cuda-checkpoint-bin --toggle --pid $PID
        sudo criu dump -t $PID \
            --images-dir ~/demo \
            --tcp-established \
            --skip-in-flight
        DUMP_EXIT=$?
        T2=$(date +%s%N)
        CP_MS=$(( (T2-T1)/1000000 ))
        CP_SIZE_MB=$(du -sm ~/demo | cut -f1)

        T3=$(date +%s%N)
        sudo criu restore --images-dir ~/demo \
            --restore-detached \
            --tcp-established
        sleep 3
        PID=$(pgrep -f "inference_current" | head -1)
        ./cuda-checkpoint-bin --toggle --pid $PID
        RESTORE_EXIT=$?
        T4=$(date +%s%N)
        RS_MS=$(( (T4-T3)/1000000 ))

        CORRECT=$([ $DUMP_EXIT -eq 0 ] && [ $RESTORE_EXIT -eq 0 ] && echo "true" || echo "false")

        echo "Run $i: checkpoint=${CP_MS}ms size=${CP_SIZE_MB}MB restore=${RS_MS}ms correct=${CORRECT}"

        cat >> "$RESULTS_FILE" << CSVEOF
2026-03-29,RTX5090,580.126,criu+cuda-checkpoint,${MODEL_LABEL},${CP_MS},${RS_MS},${CP_SIZE_MB},${CORRECT}
CSVEOF

        sleep 2
    done

    echo "Done with $MODEL_NAME"
    pkill -f "inference_current" 2>/dev/null || true
    sleep 3
done

echo ""
echo "=== ALL BENCHMARKS COMPLETE ==="
cat "$RESULTS_FILE"
