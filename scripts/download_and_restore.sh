#!/bin/bash
set -euo pipefail

STAMP="${1:?Usage: $0 <stamp>}"
BUCKET="gpu-checkpoints"
ENDPOINT="https://16006ce64942d49c17a11293b70cd027.r2.cloudflarestorage.com"
CHECKPOINT_BIN="$HOME/cuda-checkpoint-bin"
RESTORE_CSV="$HOME/results_r2_restore.csv"
DATE=$(date +%Y-%m-%d)

if [ ! -f "$RESTORE_CSV" ]; then
    echo "timestamp,gpu,driver,method,workload,download_ms,restore_ms,stamp" > "$RESTORE_CSV"
fi

rm -rf /tmp/demo_ckpt
mkdir -p /tmp/demo_ckpt

echo "--- Downloading from R2 (stamp: $STAMP) ---"
T1=$(date +%s%N)
aws s3 cp "s3://$BUCKET/checkpoints/$STAMP/" /tmp/demo_ckpt \
    --recursive \
    --endpoint-url "$ENDPOINT"
T2=$(date +%s%N)
DL_MS=$(( (T2 - T1) / 1000000 ))
echo "Download done: ${DL_MS}ms"

echo "--- Restoring with CRIU ---"
T3=$(date +%s%N)
sudo criu restore \
    --images-dir /tmp/demo_ckpt \
    --restore-detached \
    --tcp-established
T4=$(date +%s%N)
RS_MS=$(( (T4 - T3) / 1000000 ))
echo "Restore done: ${RS_MS}ms"

sleep 3
NEW_PID=$(pgrep -f "inference" | head -1)
echo "Restored PID: $NEW_PID"

echo "--- Resuming CUDA ---"
$CHECKPOINT_BIN --toggle --pid "$NEW_PID"
echo "CUDA resumed"

echo "${DATE},RTX5090,580.126,criu+cuda-checkpoint+r2,gpt2-124M,${DL_MS},${RS_MS},${STAMP}" \
    >> "$RESTORE_CSV"

echo "--------------------------------"
echo "download_ms=$DL_MS"
echo "restore_ms=$RS_MS"
echo "new_pid=$NEW_PID"
echo "--------------------------------"
