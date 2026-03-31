#!/bin/bash
# checkpoint_ram_disk.sh - Optimized checkpointing with RAM disk + granular timing
# Focus: Measure checkpoint performance only (no upload/download/restore)
# This version removes the resume step, kills the frozen process after dump,
# and ensures CSV is written.

set -euo pipefail

PID="${1:?Usage: $0 <pid>}"
CHECKPOINT_BIN="$HOME/cuda-checkpoint-bin"
RESULTS_CSV="$HOME/results_checkpoint_optimization.csv"
STAMP=$(date +%s)
DATE=$(date +%Y-%m-%d)

# Use RAM disk
CHECKPOINT_DIR="/mnt/ramdisk/demo_ckpt"

# Ensure CSV header exists (even if file exists but is empty)
if [ ! -f "$RESULTS_CSV" ] || [ ! -s "$RESULTS_CSV" ]; then
    echo "timestamp,gpu,driver,method,workload,suspend_ms,criu_dump_ms,total_checkpoint_ms,checkpoint_size_mb,stamp" \
        > "$RESULTS_CSV"
fi

# Clean previous checkpoint
rm -rf "$CHECKPOINT_DIR"
mkdir -p "$CHECKPOINT_DIR"

echo "========================================"
echo "=== Checkpoint Optimization Test ==="
echo "========================================"
echo "PID: $PID"
echo "Checkpoint Dir: $CHECKPOINT_DIR"
echo "Timestamp: $STAMP"
echo "----------------------------------------"

# --- Phase 1: Suspend CUDA ---
echo "[1/2] Suspending CUDA..."
T_SUSPEND_START=$(date +%s%N)
$CHECKPOINT_BIN --toggle --pid "$PID"
T_SUSPEND_END=$(date +%s%N)
SUSPEND_MS=$(( (T_SUSPEND_END - T_SUSPEND_START) / 1000000 ))
echo "      CUDA suspended: ${SUSPEND_MS}ms"

# --- Phase 2: CRIU Dump to RAM disk ---
echo "[2/2] Running CRIU dump to RAM disk..."
T_CRIU_START=$(date +%s%N)
sudo criu dump -t "$PID" \
    --images-dir "$CHECKPOINT_DIR" \
    --tcp-established \
    --skip-in-flight \
    --shell-job
T_CRIU_END=$(date +%s%N)
CRIU_MS=$(( (T_CRIU_END - T_CRIU_START) / 1000000 ))
CP_SIZE_MB=$(du -sm "$CHECKPOINT_DIR" | cut -f1)
echo "      CRIU dump done: ${CRIU_MS}ms"
echo "      Checkpoint size: ${CP_SIZE_MB}MB"

# --- Calculate total checkpoint time (suspend + dump) ---
TOTAL_CHECKPOINT_MS=$((SUSPEND_MS + CRIU_MS))

# --- Log to CSV ---
echo "${DATE},RTX5090,580.95,criu+cuda-checkpoint+tmpfs,gpt2-124M,${SUSPEND_MS},${CRIU_MS},${TOTAL_CHECKPOINT_MS},${CP_SIZE_MB},${STAMP}" \
    >> "$RESULTS_CSV"

# --- Output summary ---
echo "----------------------------------------"
echo "=== Checkpoint Results ==="
echo "suspend_ms=$SUSPEND_MS"
echo "criu_dump_ms=$CRIU_MS"
echo "total_checkpoint_ms=$TOTAL_CHECKPOINT_MS"
echo "checkpoint_size_mb=$CP_SIZE_MB"
echo "stamp=$STAMP"
echo "----------------------------------------"
echo "Results saved to: $RESULTS_CSV"
echo "========================================"

# --- Cleanup: kill the frozen process ---
kill -9 "$PID" 2>/dev/null || true
echo "Process $PID killed."