#!/bin/bash
# start_inference.sh - Start inference workload and wait for GPU ready

pkill -f "inference.py" 2>/dev/null; sleep 2

setsid python3 ~/inference.py </dev/null >~/inference.log 2>&1 &

echo "Waiting for model to load..."
for i in $(seq 1 40); do
    sleep 3
    if grep -q "READY" ~/inference.log 2>/dev/null; then
        echo "Model ready after $((i*3))s"
        break
    fi
    echo "  ${i}/40..."
done

PID=$(pgrep -f "inference.py" | head -1)
if [ -z "$PID" ]; then
    echo "ERROR: inference.py failed to start"
    cat ~/inference.log | tail -20
    exit 1
fi

echo "PID: $PID"
tail -3 ~/inference.log
nvidia-smi | tail -5
