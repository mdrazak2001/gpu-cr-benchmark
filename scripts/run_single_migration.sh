#!/bin/bash
# run_single_migration.sh - One complete checkpoint/upload/download/restore cycle

set -e

bash ~/start_inference.sh
PID=$(pgrep -f "inference.py" | head -1)
echo "PID: $PID"

bash ~/checkpoint_and_upload.sh $PID | tee /tmp/ckpt_output.txt
STAMP=$(grep "^stamp=" /tmp/ckpt_output.txt | cut -d'=' -f2)
echo "Stamp: $STAMP"

pkill -f "inference.py" 2>/dev/null
sleep 3

bash ~/download_and_restore.sh $STAMP

echo "=== Results ==="
cat ~/results_r2.csv
echo ""
cat ~/results_r2_restore.csv
