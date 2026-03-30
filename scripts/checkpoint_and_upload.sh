#!/bin/bash
set -euo pipefail

PID="${1:?Usage: $0 <pid>}"
BUCKET="gpu-checkpoints"
ENDPOINT="https://16006ce64942d49c17a11293b70cd027.r2.cloudflarestorage.com"
CHECKPOINT_BIN="$HOME/cuda-checkpoint-bin"
RESULTS_CSV="$HOME/results_r2.csv"
STAMP=$(date +%s)
DATE=$(date +%Y-%m-%d)

# Ensure CSV header exists
if [ ! -f "$RESULTS_CSV" ]; then
    echo "timestamp,gpu,driver,method,workload,checkpoint_ms,upload_ms,checkpoint_size_mb,stamp" \
        > "$RESULTS_CSV"
fi

rm -rf /tmp/demo_ckpt
mkdir -p /tmp/demo_ckpt

echo "--- Suspending CUDA for PID $PID ---"
$CHECKPOINT_BIN --toggle --pid "$PID"
echo "CUDA suspended"

echo "--- Starting CRIU Dump ---"
T1=$(date +%s%N)
sudo criu dump -t "$PID" \
    --images-dir /tmp/demo_ckpt \
    --tcp-established \
    --skip-in-flight \
    --shell-job
T2=$(date +%s%N)
CP_MS=$(( (T2 - T1) / 1000000 ))
CP_SIZE_MB=$(du -sm /tmp/demo_ckpt | cut -f1)
echo "Checkpoint done: ${CP_MS}ms, ${CP_SIZE_MB}MB"

echo "--- Uploading to R2 ---"
T3=$(date +%s%N)
aws s3 cp /tmp/demo_ckpt "s3://$BUCKET/checkpoints/$STAMP/" \
    --recursive \
    --endpoint-url "$ENDPOINT"
T4=$(date +%s%N)
UP_MS=$(( (T4 - T3) / 1000000 ))
echo "Upload done: ${UP_MS}ms"

# Log to CSV
echo "${DATE},RTX5090,580.126,criu+cuda-checkpoint+r2,gpt2-124M,${CP_MS},${UP_MS},${CP_SIZE_MB},${STAMP}" \
    >> "$RESULTS_CSV"

echo "--------------------------------"
echo "checkpoint_ms=$CP_MS"
echo "upload_ms=$UP_MS"
echo "checkpoint_size_mb=$CP_SIZE_MB"
echo "stamp=$STAMP"
echo "R2 path: s3://$BUCKET/checkpoints/$STAMP/"
echo "--------------------------------"
