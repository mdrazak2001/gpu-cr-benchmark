#!/bin/bash
# setup_remote.sh - Prepare a fresh GPU instance for C/R Benchmarking
# Tested on: Vast.ai KVM image docker.io/vastai/kvm:cuda-12.9.1-auto
# Driver: 580.126.09, CUDA: 12.9

set -e

echo "=== Verifying GPU environment ==="
nvidia-smi | head -5
nvcc --version 2>/dev/null || echo "nvcc not in PATH yet"

# Detect CUDA path and add to PATH
CUDA_PATH=$(find /usr/local -maxdepth 1 -name "cuda*" -type d | sort -V | tail -1)
echo "Found CUDA at: $CUDA_PATH"
export PATH=$CUDA_PATH/bin:$PATH
echo "export PATH=$CUDA_PATH/bin:\$PATH" >> ~/.bashrc
nvcc --version

echo "=== Waiting for apt lock to clear ==="
sudo systemctl stop unattended-upgrades || true
sudo killall unattended-upgr 2>/dev/null || true
sleep 3

echo "=== Installing dependencies ==="
sudo apt-get update
sudo apt-get install -y \
    build-essential git wget \
    libprotobuf-dev protobuf-compiler \
    libprotobuf-c-dev protobuf-c-compiler \
    python3-protobuf libnl-3-dev libcap-dev \
    uuid-dev libaio-dev libbsd-dev \
    libnet1-dev netcat-openbsd \
    pkg-config libgnutls28-dev python3-yaml \
    awscli

echo "=== Cloning CRIU ==="
git clone https://github.com/checkpoint-restore/criu.git
cd criu
make -j$(nproc)
sudo make install-criu
criu --version
cd ..

echo "=== Getting cuda-checkpoint from repo ==="
git clone https://github.com/mdrazak2001/gpu-cr-benchmark.git
cp gpu-cr-benchmark/cuda-checkpoint-bin ~/cuda-checkpoint-bin
chmod +x ~/cuda-checkpoint-bin
~/cuda-checkpoint-bin --help | head -2

echo "=== Copying benchmark scripts ==="
cp gpu-cr-benchmark/checkpoint_and_upload.sh ~/
cp gpu-cr-benchmark/download_and_restore.sh ~/
cp gpu-cr-benchmark/inference.py ~/
cp gpu-cr-benchmark/run_benchmarks.sh ~/
chmod +x ~/checkpoint_and_upload.sh ~/download_and_restore.sh ~/run_benchmarks.sh

echo "=== Installing Python packages ==="
pip install torch transformers huggingface_hub

echo "=== Configuring AWS for R2 ==="
echo "Run: aws configure"
echo "  Access Key: your R2 access key"
echo "  Secret Key: your R2 secret key"
echo "  Region: auto"

echo "=== Git config ==="
git config --global user.email "mohammedrazak2001@gmail.com"
git config --global user.name "mdrazak2001"

echo "=== Final verification ==="
nvidia-smi | head -3
echo "CRIU: $(criu --version | head -1)"
echo "cuda-checkpoint: $(~/cuda-checkpoint-bin --help | head -2 | tail -1)"
python3 -c "import torch; print('PyTorch CUDA:', torch.cuda.is_available())"
echo "=== Setup complete — no reboot needed ==="

