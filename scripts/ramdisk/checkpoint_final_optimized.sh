#!/bin/bash
# Optimized for GPU mapping conflicts
set -euo pipefail
PID="${1:?Usage: $0 <pid>}"
CHECKPOINT_BIN="$HOME/cuda-checkpoint-bin"
PRE_DIR="/mnt/ramdisk/pre_dump"
RAM_DIR="/mnt/ramdisk/optimized_ckpt"

# --- PART 1: THE ONE-TIME WARM-UP (PRE-DUMP) ---
# We suspend briefly just to clear the GPU mappings for CRIU
echo "Initializing Pre-dump..."
$CHECKPOINT_BIN --toggle --pid "$PID"
sudo criu pre-dump -t "$PID" --images-dir "$PRE_DIR" --shell-job --track-mem
sudo kill -CONT "$PID"
$CHECKPOINT_BIN --toggle --pid "$PID"
echo "Static weights cached. System ready for benchmark."

sleep 2

# --- PART 2: THE ACTUAL TIMED RUN ---
echo "--- Starting Timed Benchmark ---"
T_START=$(date +%s%N)

# 1. Suspend
$CHECKPOINT_BIN --toggle --pid "$PID"
T_SUSPEND_END=$(date +%s%N)

# 2. Incremental Dump (Should be 10x faster now)
sudo criu dump -t "$PID" \
    --images-dir "$RAM_DIR" \
    --prev-images-dir "../pre_dump" \
    --tcp-established --shell-job --leave-running

T_DUMP_END=$(date +%s%N)

# Results
SUSPEND_MS=$(( (T_SUSPEND_END - T_START) / 1000000 ))
DUMP_MS=$(( (T_DUMP_END - T_SUSPEND_END) / 1000000 ))
echo "SUSPEND: ${SUSPEND_MS}ms | DUMP: ${DUMP_MS}ms | TOTAL: $((SUSPEND_MS + DUMP_MS))ms"