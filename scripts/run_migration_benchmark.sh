#!/bin/bash
# run_migration_benchmark.sh - Full checkpoint/upload/download/restore cycle

set -e

RUNS=${1:-3}
echo "Running $RUNS migration cycles"

# Ensure inference is running
PID=$(pgrep -f "inference.py" | head -1)
if [ -z "$PID" ]; then
    echo "Starting inference..."
    bash ~/start_inference.sh
    PID=$(pgrep -f "inference.py" | head -1)
fi
echo "Starting PID: $PID"

for i in $(seq 1 $RUNS); do
    echo ""
    echo "========================================"
    echo "=== Migration Run $i / $RUNS ==="
    echo "========================================"

    PID=$(pgrep -f "inference.py" | head -1)
    if [ -z "$PID" ]; then
        echo "Restarting inference..."
        bash ~/start_inference.sh
        PID=$(pgrep -f "inference.py" | head -1)
    fi
    echo "PID: $PID"

    # Phase 1: Checkpoint + Upload (visible output)
    echo "--- Phase 1: Checkpoint + Upload ---"
    bash ~/checkpoint_and_upload.sh $PID | tee /tmp/ckpt_output.txt
    STAMP=$(grep "^stamp=" /tmp/ckpt_output.txt | cut -d'=' -f2)
    echo "Stamp: $STAMP"

    # Simulate VM1 shutdown
    pkill -f "inference.py" 2>/dev/null
    sleep 3

    # Phase 2: Download + Restore
    echo "--- Phase 2: Download + Restore ---"
    bash ~/download_and_restore.sh $STAMP
    sleep 5

    echo "Run $i complete"
done

echo ""
echo "========================================"
echo "=== FINAL RESULTS ==="
echo "========================================"
echo "--- Checkpoint + Upload ---"
cat ~/results_r2.csv
echo ""
echo "--- Download + Restore ---"
cat ~/results_r2_restore.csv
