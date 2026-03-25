#!/bin/bash
# setup_remote.sh - Prepare a fresh GPU instance for C/R Benchmarking

set -e

echo "=== Installing dependencies ==="
sudo apt-get update
sudo apt-get install -y \
    build-essential git wget \
    libprotobuf-dev protobuf-compiler \
    libprotobuf-c-dev protobuf-c-compiler \
    libnl-3-dev libcap-dev libaio-dev \
    libnet1-dev \
    pkg-config libgnutls28-dev

echo "=== Cloning CRIU ==="
git clone https://github.com/checkpoint-restore/criu.git
cd criu

echo "=== Building CRIU ==="
make -j$(nproc)

echo "=== Installing CRIU ==="
sudo make install

echo "=== CRIU version ==="
criu --version

cd ..

echo "=== Downloading CUDA checkpoint tool ==="
wget https://github.com/NVIDIA/cuda-checkpoint/raw/main/bin/cuda-checkpoint
chmod +x cuda-checkpoint

echo "=== Verifying cuda-checkpoint ==="
./cuda-checkpoint --help || true

echo "=== Setup complete ==="