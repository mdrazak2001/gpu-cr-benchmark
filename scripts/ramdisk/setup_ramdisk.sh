#!/bin/bash
# setup_ramdisk.sh - Create 4GB RAM disk for checkpointing

set -e

echo "=== Creating 4GB RAM disk ==="
sudo mkdir -p /mnt/ramdisk
sudo mount -t tmpfs -o size=4G tmpfs /mnt/ramdisk

# Verify
df -h | grep ramdisk
echo "RAM disk ready at /mnt/ramdisk"