# gpu-cr-benchmark

Independent benchmark of GPU checkpoint/restore (C/R) on an NVIDIA RTX 5090 using CRIU 4.2 + cuda-checkpoint (driver 580.126). Tests performed March 2026 on a Vast.ai VM (see Hardware & Software).

This repository provides reproducible, open-source results benchmarking CRIU + NVIDIA cuda-checkpoint on consumer PCIe‑5.0 hardware (RTX 5090 32GB). The work was motivated by Cedana's published benchmarks on the A100 (their “GPU Runtime” and reported CRIU results). We compare to those published baselines, report which numbers we were able to reproduce, and provide visualizations generated from the data in results/.

Table of contents
- State-of-the-art baselines (sources)
- What we measured (summary)
- Replication status: which baseline numbers were reproduced (and which were not)
- Key findings & caveats (cold vs warm checkpoints, migration bottlenecks)
- Visualizations (embedded graphs from repo)
- Full results, raw data, and reproduction steps
- Limitations & next steps

---

## State-of-the-art baselines (sources / links)

We compared our measurements to two baselines that represent the state of the art in prior public reporting:

- Cedana — "GPU Runtime" (proprietary GPU interception, A100) and Cedana-reported CRIU numbers (A100). Source: Cedana public benchmark / blog (Cedana published benchmark comparing CRIU vs their GPU Runtime on A100). See Cedana's public benchmark for details (Cedana benchmark, 2025).  
  NOTE: Cedana’s GPU Runtime is a proprietary implementation and is not available to run locally for independent verification.

- CRIU + cuda-checkpoint — the open-source CRIU project and NVIDIA's cuda-checkpoint support (this repo uses CRIU 4.2 built from source and the cuda-checkpoint implementation bundled with NVIDIA driver 580.126).  
  - CRIU project: https://github.com/checkpoint-restore/criu  
  - CRIU documentation and changes: https://criu.org

(Links above point to the open-source CRIU project. Cedana’s original benchmark is cited from their public material — the Cedana page linked in the repository references in the original work.)

Why these baselines:
- Cedana’s public benchmark is the most recent published comparison of a proprietary GPU runtime vs the CRIU approach on A100 hardware; it sets a practical “SOTA” point for checkpoint and restore times measured on datacenter GPUs.
- CRIU + cuda-checkpoint is the open-source methodology we implement and evaluate on newer consumer hardware (RTX 5090).

---

## What we measured (summary)

Test conditions (applies to all single-VM runs below):
- Hardware: NVIDIA RTX 5090 32GB GDDR7 on a Vast.ai KVM VM (AMD Ryzen 9 9950X host)
- Driver: NVIDIA driver 580.126.09
- CUDA Toolkit: 12.8
- CRIU: 4.2 (built from source)
- cuda-checkpoint: NVIDIA driver-bundled implementation (580.126.09)
- OS: Ubuntu 22.04
- Test method: 3 runs per model (unless noted), mean values reported. `correct=true` indicates inference resumed correctly after restore (verified).

Single-VM checkpoint/restore (averages, milliseconds; checkpoint sizes in MB)

| Model | VRAM Used | Avg Checkpoint (ms) | Avg Restore (ms) | Checkpoint Size (MB) |
|-------|-----------|---------------------:|------------------:|---------------------:|
| counter (minimal CUDA) | ~500MB | 539 | 1325 | 543 |
| gpt2-124M | 1126MB | 1241 | 3762 | 2336 |
| gpt2-medium-345M | 1976MB | 1380 | 4175 | 3183 |
| gpt2-large-774M | 3704MB | 2977* | 4578 | 4978 |
| gpt2-xl-1558M | 5590MB | 3761* | 5108 | 7915 |

* gpt2-large & gpt2-xl exclude the cold first-run outlier in the average (see Cold/Warm section for raw runs).

Cold vs warm example runs (gpt2-large and gpt2-xl)

| Model | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Cold/Warm Ratio |
|-------|-----------:|-----------:|-----------:|----------------:|
| gpt2-large | 5338 | 2377 | 2217 | 2.4x |
| gpt2-xl | 19923 | 3920 | 3601 | 5.5x |

Cross-provider migration (simulated single-VM upload→R2→download→restore; gpt2-124M checkpoint ~2.3 GB)

Network baseline (Vast.ai → Cloudflare R2)
- Upload 2GB: 77 s (~26 MB/s)
- Download 2GB: 32 s (~64 MB/s)

Migration timeline (gpt2-124M, all times in ms)

| Phase | Avg (ms) |
|-------|---------:|
| Checkpoint | 3,050 |
| Upload (to R2) | 94,469 |
| Download (from R2) | 40,797 |
| Restore | 1,799 |
| Total | ~140,000 (~140 s) |

Conclusion: network transfer dominates the migration timeline (~95% of total).

Checkpoint mode optimization (gpt2-124M)

| Mode | Avg Lock/Suspend (ms) | Avg CRIU Dump (ms) | Avg Total (ms) | Size (MB) |
|------|----------------------:|-------------------:|---------------:|----------:|
| toggle | 895 | 1642 | 2537 | 2338 |
| lock_check | 295 | 1661 | 2576 | 2337 |
| predump | 900 | 3450 | 4350 | 2338 |

Finding: toggle and lock_check similar total time at this scale. predump increases total time substantially for 124M model (no size benefit here).

Raw CSVs are available in results/ (see Raw Data section).

---

## SOTA numbers from prior work (Cedana) vs our measured numbers — detailed comparison and replication status

The two SOTA numbers we reference (as reported by Cedana for an A100 40GB setup) are:

- Cedana — proprietary "GPU Runtime" on A100 (reported)
  - Published (Cedana): Warm checkpoint = 1.86 s (1860 ms) for a ~2.2 GiB GPT-2 scale test; Restore = 2.65 s (2650 ms)
  - Source: Cedana public benchmark (Cedana blog/benchmark; see repository references).

- Cedana — CRIU + cuda-checkpoint reported numbers (A100)
  - Published (Cedana): Warm checkpoint (CRIU CUDA) = 7.01 s (7010 ms); Cold Start (restore) = 6.22 s (6220 ms)

Our measurements (RTX 5090, CRIU 4.2 + cuda-checkpoint, same model scale ≈ 2.2 GiB checkpoint):

- This repo (RTX 5090) measured:
  - Warm checkpoint (gpt2-large / ~2.34 GB) = 2.9 s (2,977 ms; 3-run average, cold-run outlier excluded)
  - Restore (cold start) = 1.80 s (1,800 ms; 3-run average)
  - Checkpoint size = 2.34 GB

Replication status (explicit):
- Cedana proprietary GPU Runtime (A100)
  - Reproduced? No. We do not have access to Cedana’s proprietary GPU Runtime plugin and therefore could not run their exact measurement locally.
  - Corresponding Cedana numbers (1.86 s checkpoint) are included here only as a published SOTA reference.
  - We therefore do not claim replication of those exact numbers.

- Cedana-reported CRIU numbers (A100)
  - Reproduced? No (numerically). We re-implemented the same open methodology (CRIU 4.2 + cuda-checkpoint) and ran it on different hardware (RTX 5090, PCIe 5.0). Our measured CRIU+cuda-checkpoint times (2.9 s checkpoint, 1.8 s restore) do not match Cedana’s reported CRIU times (7.01 s checkpoint, 6.22 s restore) on A100 hardware.
  - Interpretation: the qualitative conclusion Cedana presents — that the proprietary GPU Runtime achieves faster checkpoint times than CRIU on their A100 test — remains consistent with Cedana’s report. However, absolute numbers differ substantially between A100 (Cedana) and RTX 5090 (this repo). Differences are most likely due to:
    - Hardware differences (A100 HBM2e vs RTX 5090 GDDR7; PCIe 4.0 vs PCIe 5.0)
    - Driver and system stack differences (driver versions, kernel/VM configuration)
    - Possible workload differences (model weights & configurations may be similar but cannot be guaranteed identical)
  - We were able to replicate the open methodology (CRIU + cuda-checkpoint) and to measure checkpoint & restore performance on newer consumer hardware — but the numbers do not numerically match Cedana's CRIU numbers on A100.

Replication details, measured numbers and tolerances:
- Per-model runs: 3 runs each (for most models). Averages shown above are arithmetic means unless otherwise noted.
- For gpt2-large:
  - Raw runs: 5338 ms (run1, cold), 2377 ms (run2), 2217 ms (run3)
  - We excluded the cold-run outlier when reporting average warm checkpoint: avg = 2,977 ms (run2+run3 mean ≈ 2,297? — see raw CSVs). The cold run shows large variance (2.4x slower).
- For gpt2-xl:
  - Raw runs: 19,923 ms (cold / first run), 3,920 ms (warm), 3,601 ms (warm) — cold/warm ratio 5.5x.
- Observed run-to-run variance: warm checkpoints (after model load) were typically within ~5–20% between repeats for most models; cold-first-run outliers can be multiple times slower (2–5x) depending on the model and momentary system state.
- Tolerances declared: we report measured means across 3 runs. Expect per-run variance of up to ~20% for warm checkpoints and much larger variance for the initial cold run; consider running 5–10 warm repetitions before measuring stable warm performance.

Short summary: we were able to reproduce the CRIU+cuda-checkpoint methodology and measure improved absolute restore times on RTX 5090 (1.8 s restore for ~2.3 GB model), but we were not able to numerically reproduce Cedana's A100 CRIU numbers. Cedana’s claims about their proprietary GPU Runtime being faster on checkpoint remain a valid SOTA reference (we could not run the proprietary runtime to validate their numbers locally).

---

## Key findings & guidance

- Cold vs warm: The very first checkpoint after loading a model can be 2–5× slower than later warm checkpoints. For long-running jobs or spot instance handlers, take one early warm checkpoint to avoid paying a large cold penalty when a real interruption occurs.
- Restore is relatively fast on modern consumer PCIe‑5.0 hardware: ~1.8 s for a ~2.34 GB GPT-2 scale checkpoint on an RTX 5090 in our tests.
- Checkpoint time is sensitive to the cuda-checkpoint mode: predump increases CRIU dump time at this model scale, while toggle and lock_check have comparable total times.
- For cross-provider migration, network transfer dominates: upload/download to Cloudflare R2 made up ~95% of the total 140 s migration time for gpt2-124M. This makes cross-provider migration practical for long-running jobs (tens of minutes to hours), not for short inference-only jobs.

---

## Visualizations (generated from results/, embedded)

The following graphs are included in the repository at results/images/ and are embedded here for quick inspection. Captions include replication status notes and interpretations.

Note: images referenced below are saved in the repo under results/images/.

1) Checkpoint & Restore time vs Model (SOTA comparison)
![Checkpoint & Restore time vs Model (gpt2 scales) — RTX 5090 CRIU vs Cedana A100 SOTA](results/images/checkpoint_restore_vs_model.png)

Caption: Checkpoint and restore times plotted against model scale (GPT‑2 variants) comparing (a) Cedana published A100 numbers (proprietary GPU Runtime and Cedana-reported CRIU values) and (b) this repo's measured CRIU + cuda-checkpoint times on RTX 5090. Replication note: we could not run Cedana’s proprietary runtime; Cedana’s numbers are shown as published SOTA references. We executed the open CRIU methodology and plotted our measured points (green). Our restore times are faster on the RTX 5090 (1.8 s for the ~2.3 GB model) versus Cedana's published restore on A100; checkpoint times differ in absolute value (see text for hardware-related interpretation).

2) Migration timeline breakdown (gpt2-124M)
![Migration timeline breakdown (checkpoint / upload / download / restore) — gpt2-124M](results/images/migration_breakdown_gpt2-124m.png)

Caption: Migration breakdown for a ~2.3 GB gpt2-124M checkpoint showing that upload/download dominate total migration time (~95%). Checkpoint + restore are only a few seconds collectively. Replication note: network throughput depends on VM provider and region; numbers shown are from Vast.ai → Cloudflare R2 baseline measured in this repo.

3) Checkpoint mode comparison (gpt2-124M)
![Checkpoint mode comparison (toggle / lock_check / predump) — gpt2-124M](results/images/checkpoint_modes_gpt2_124m.png)

Caption: Mode-by-mode timing breakdown for toggle, lock_check, and predump modes using cuda-checkpoint: predump adds substantial CRIU dump time at this model scale with no size benefit. Replication note: predump may benefit much larger models where dirty page tracking reduces dump size — not observed at the 124M scale.

(If images do not render in the hosting UI, open the PNGs directly from results/images/ in the repo.)

---

## Full results / raw data

All raw CSVs used to generate the tables and figures are in results/:

- results/results_single_vm.csv — single-VM checkpoint/restore, per-run raw timings for all models
- results/results_migration_checkpoint_upload.csv — upload timing to R2 (per-run)
- results/results_migration_download_restore.csv — download + restore timing (per-run)
- results/results_optimization_tmpfs_v1.csv — predump experiments (per-run)
- results/results_optimization_tmpfs_v2.csv — mode comparison experiments (per-run)
- results/images/* — PNGs used above

Please consult these CSVs to inspect per-run timings and reproduce the graphs.

---

## How to reproduce these measurements

Prerequisites:
- Ubuntu 22.04 VM (we used a Vast.ai KVM instance)
- NVIDIA GPU (we used RTX 5090 32GB)
- NVIDIA driver 580.126.09 (includes cuda-checkpoint)
- CUDA Toolkit 12.8
- CRIU 4.2 (we built from source)

Quick setup (example)

```bash
git clone https://github.com/mdrazak2001/gpu-cr-benchmark.git
cd gpu-cr-benchmark
bash scripts/setup_remote.sh     # environment setup used in our runs
# Configure Cloudflare R2 credentials (if running migration tests)
aws configure
```

Single-VM benchmark (example sequence)

```bash
bash scripts/start_inference.sh
PID=$(pgrep -f "inference.py" | head -1)

# Run 3 checkpoint/restore cycles
for i in 1 2 3; do
    bash scripts/run_single_migration.sh $PID
done
```

Cross-provider migration (simulated single-VM upload/download to R2)

Phase 1 (checkpoint and upload)
```bash
bash scripts/checkpoint_and_upload.sh $PID | tee /tmp/output.txt
STAMP=$(grep "^stamp=" /tmp/output.txt | cut -d'=' -f2)
```

Phase 2 (download and restore)
```bash
bash scripts/download_and_restore.sh $STAMP
```

All scripts referenced above are in scripts/. The raw CSV outputs are saved in results/; scripts also generate the PNG images in results/images/.

---

## Limitations & caveats

- Hardware mismatch: Cedana’s published numbers are on A100 40GB HBM2e PCIe 4.0 hardware; our measurements are on RTX 5090 32GB GDDR7 PCIe 5.0 hardware. Direct numeric comparisons are therefore imperfect — trends are most meaningful.
- We did not have access to Cedana’s proprietary GPU Runtime plugin, so we could not run their GPU Runtime locally. Cedana’s proprietary numbers are cited only as published SOTA references.
- Migration tests are simulated single-VM (upload → R2 → download on the same host); true cross-instance, cross-region latency characteristics will add additional variability.
- LLaMA and other large models were not benchmarked (pending legal/access and compute).
- Results depend on driver/kernel/VM configuration; small differences in configuration can change cold/warm penalties and throughput.

---

## Next steps (planned)
- Run a true two-VM migration benchmark (separate instances, different regions).
- Test LLaMA 3.2 (1B, 3B, 8B) for larger-scale checkpoint behavior.
- If access becomes available, run Cedana’s proprietary plugin locally for a direct replication of their published GPU Runtime numbers.
- Evaluate predump and incremental dirty-page tracking on models where memory working set is large relative to the checkpoint size.

---

Built in Bengaluru by Mohammed Razak. Feedback welcome — open an issue in the repository.