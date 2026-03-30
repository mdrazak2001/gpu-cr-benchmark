#!/bin/bash
# setup_remote.sh - Prepare a fresh GPU instance for C/R Benchmarking

set -e

echo "=== Waiting for apt lock to clear ==="
# Kill unattended upgrades that block apt on fresh instances
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

echo "=== Adding CUDA toolkit to PATH ==="
export PATH=/usr/local/cuda-12.8/bin:$PATH
echo 'export PATH=/usr/local/cuda-12.8/bin:$PATH' >> ~/.bashrc

echo "=== Installing CUDA toolkit ==="
# Only install if nvcc not already present
if ! command -v nvcc &> /dev/null; then
    sudo apt-get install -y cuda-toolkit-12-8
fi
nvcc --version

echo "=== Cloning CRIU ==="
git clone https://github.com/checkpoint-restore/criu.git
cd criu

echo "=== Building CRIU ==="
make -j$(nproc)

echo "=== Installing CRIU ==="
sudo make install-criu
criu --version
cd ..

echo "=== Downloading CUDA checkpoint tool ==="
git clone https://github.com/NVIDIA/cuda-checkpoint.git
cp cuda-checkpoint/bin/x86_64_Linux/cuda-checkpoint ./cuda-checkpoint-bin
chmod +x ./cuda-checkpoint-bin

echo "=== Verifying cuda-checkpoint ==="
./cuda-checkpoint-bin --help

echo "=== Installing Python packages ==="
pip install torch transformers huggingface_hub --quiet

echo "=== Setup complete ==="
echo "Next: reboot if nvidia-smi shows version mismatch"
nvidia-smi | head -3