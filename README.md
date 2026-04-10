# gpu-cr-benchmark

**Independent benchmark of GPU checkpoint/restore (C/R) on NVIDIA RTX 5090**  
using CRIU 4.2 + cuda-checkpoint (driver 580.126), tested March 2026.

Motivated by Cedana's published benchmarks on A100. This repo provides
independent, reproducible results on newer consumer hardware using only
open-source tooling.

---

## Hardware & Software

| Component | Details |
|-----------|---------|
| GPU | NVIDIA RTX 5090 32GB GDDR7 |
| Driver | 580.126.09 |
| CUDA Toolkit | 12.8 |
| CRIU | 4.2 (built from source) |
| cuda-checkpoint | 580.126.09 (bundled with driver) |
| Host | Vast.ai KVM VM, AMD Ryzen 9 9950X |
| OS | Ubuntu 22.04 |
| Date | March 2026 |

---

## Results 1: Single-VM Checkpoint/Restore

All times in milliseconds. 3 runs per model. `correct=true` means
inference resumed correctly after restore (verified by output continuity).

### Summary Table

| Model | VRAM Used | Avg Checkpoint (ms) | Avg Restore (ms) | Checkpoint Size (MB) |
|-------|-----------|--------------------|-----------------|--------------------|
| counter (minimal CUDA) | ~500MB | 539 | 1325 | 543 |
| gpt2-124M | 1126MB | 1241 | 3762 | 2336 |
| gpt2-medium-345M | 1976MB | 1380 | 4175 | 3183 |
| gpt2-large-774M | 3704MB | 2977* | 4578 | 4978 |
| gpt2-xl-1558M | 5590MB | 3761* | 5108 | 7915 |

*Excludes cold first-run outlier (see below)

### Key Finding: Cold vs Warm Checkpoint Gap

First checkpoint after model load is significantly slower than subsequent ones:

| Model | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Cold/Warm Ratio |
|-------|-----------|-----------|-----------|----------------|
| gpt2-large | 5338 | 2377 | 2217 | 2.4x |
| gpt2-xl | 19923 | 3920 | 3601 | 5.5x |

**Implication:** For spot interruption handlers, trigger one warm-up
checkpoint early in the job. Subsequent checkpoints triggered by actual
interruptions will be 2-5x faster.

### Comparison with Cedana Published Benchmarks (GPT-2, A100 40GB)

| Metric | Cedana (A100) | This Repo (RTX 5090) | Notes |
|--------|--------------|---------------------|-------|
| Checkpoint | 7.01s | 1.24s | Different method — Cedana uses CRIU CUDA plugin |
| Restore (cold start) | 6.22s | 3.76s | |
| Hardware | A100 40GB HBM2e | RTX 5090 32GB GDDR7 | 5090 has PCIe 5.0 vs PCIe 4.0 |
| Software | Cedana proprietary GPU plugin | Standard CRIU + cuda-checkpoint | |

Direct comparison is imperfect — Cedana uses their proprietary GPU
interception layer which has different tradeoffs vs NVIDIA's native
cuda-checkpoint. These numbers reflect what's achievable with
standard open-source tooling on RTX 5090.

---

## Results 2: Cross-Provider Migration via Cloudflare R2

Simulated cross-provider migration: checkpoint on VM, upload to R2,
download on same VM (single-VM simulation), restore.

### Network Baseline (Vast.ai → Cloudflare R2)

| Direction | File Size | Time | Throughput |
|-----------|----------|------|-----------|
| Upload | 2GB | 77s | ~26 MB/s |
| Download | 2GB | 32s | ~64 MB/s |

### Migration Latency (gpt2-124M, 2.3GB checkpoint)

| Run | Checkpoint (ms) | Upload (ms) | Download (ms) | Restore (ms) | Total (ms) |
|-----|----------------|------------|--------------|-------------|-----------|
| 1 | 3207 | 92189 | 40374 | 1811 | 137,581 |
| 2 | 2972 | 95409 | 39575 | 1784 | 139,740 |
| 3 | 2972 | 95808 | 42443 | 1801 | 143,024 |
| **Avg** | **3050** | **94469** | **40797** | **1799** | **~140,000** |

**Total average migration time: ~140 seconds (2.3 minutes) for gpt2-124M**

Network transfer dominates (95% of total time). Checkpoint and restore
combined are only ~5 seconds. This means cross-provider migration is
practical for long-running jobs (>30 minutes) but not for short jobs.

---

## Results 3: Checkpoint Mode Optimization

Compared three cuda-checkpoint modes on gpt2-124M:

| Mode | Avg Lock/Suspend (ms) | Avg CRIU Dump (ms) | Avg Total (ms) | Size (MB) |
|------|----------------------|--------------------|---------------|----------|
| toggle | 895 | 1642 | 2537 | 2338 |
| lock_check | 295 | 1661 | 2576 | 2337 |
| predump | 900 | 3450 | 4350 | 2338 |

**Finding:** `toggle` and `lock_check` modes show similar total times.
`predump` adds significant overhead for gpt2-124M with no size benefit
at this model scale — predump may benefit larger models where dirty
page tracking reduces checkpoint size.

---

## Reproducing These Results

### Setup

```bash
git clone https://github.com/mdrazak2001/gpu-cr-benchmark.git
cd gpu-cr-benchmark
bash scripts/setup_remote.sh
aws configure  # set R2 credentials
```

### Single-VM Benchmark

```bash
bash scripts/start_inference.sh
PID=$(pgrep -f "inference.py" | head -1)
# Run 3 checkpoint/restore cycles
for i in 1 2 3; do
    bash scripts/run_single_migration.sh
done
```

### Cross-Provider Migration

```bash
# Phase 1 (VM1): checkpoint and upload
bash scripts/checkpoint_and_upload.sh $PID | tee /tmp/output.txt
STAMP=$(grep "^stamp=" /tmp/output.txt | cut -d'=' -f2)

# Phase 2 (VM2): download and restore
bash scripts/download_and_restore.sh $STAMP
```

---

## Limitations

- Migration tested on single VM (upload + download on same machine).
  True cross-instance geographic latency not yet measured.
- Cedana comparison is indirect — different GPU plugin architecture.
- RTX 5090 is a consumer card without ECC memory or NVLink.
- LLaMA models not yet tested (pending HuggingFace access).
- Cedana GPU plugin not tested (requires account access).

---

## Raw Data

All raw CSV results are in `results/`:

- `results_single_vm.csv` — single-VM checkpoint/restore, all models
- `results_migration_checkpoint_upload.csv` — upload timing to R2
- `results_migration_download_restore.csv` — download + restore timing
- `results_optimization_tmpfs_v1.csv` — predump experiments
- `results_optimization_tmpfs_v2.csv` — mode comparison experiments

---

## Next Steps

- [ ] True two-VM migration benchmark (separate instances, different regions)
- [ ] LLaMA 3.2 1B, 3B, 8B benchmarks
- [ ] Cedana GPU plugin comparison (pending account access)
- [ ] Cross-provider benchmark: Vast.ai → RunPod via R2

---

Built in Bengaluru by Mohammed Razak  
Feedback welcome via GitHub Issues.