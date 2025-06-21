#!/bin/bash

set -eo pipefail

BTRFS_TARGET_DIR="${BTRFS_TARGET_DIR:-$(
    dir=$(podman system info --format '{{.Store.GraphRoot}}' | sed 's|/storage$||')
    mkdir -p "$dir"
    echo "$dir"
)}"
# Options used to mount
BTRFS_MOUNT_OPTS=${BTRFS_MOUNT_OPTS:-"compress-force=zstd:2"}
# Location where the loopback file will be placed.
_BTRFS_LOOPBACK_FILE=${_BTRFS_LOOPBACK_FILE:-/mnt/btrfs_loopbacks/$(systemd-escape -p "$BTRFS_TARGET_DIR")}
# Percentage of the total space to use. Max: 1.0, Min: 0.0
_BTRFS_LOOPBACK_FREE=${_BTRFS_LOOPBACK_FREE:-"0.8"}

# Result of $(dirname "$_BTRFS_LOOPBACK_FILE")
btrfs_pdir="$(dirname "$_BTRFS_LOOPBACK_FILE")"

# Install btrfs-progs
sudo apt-get install -y btrfs-progs

# Create loopback file
sudo mkdir -p "$btrfs_pdir" && sudo chown "$(id -u)":"$(id -g)" "$btrfs_pdir"
_final_size=$(
    findmnt --target "$btrfs_pdir" --bytes --df --json |
        jq -r --arg freeperc "$_BTRFS_LOOPBACK_FREE" \
            '.filesystems[0].avail * ($freeperc | tonumber) | round'
)
truncate -s "$_final_size" "$_BTRFS_LOOPBACK_FILE"
unset -v _final_size

# # Stop docker services
# sudo systemctl stop docker

# Format btrfs loopback
sudo mkfs.btrfs -r "$BTRFS_TARGET_DIR" "$_BTRFS_LOOPBACK_FILE"

# Mount
sudo systemd-mount "$_BTRFS_LOOPBACK_FILE" "$BTRFS_TARGET_DIR" \
    ${BTRFS_MOUNT_OPTS:+ --options="${BTRFS_MOUNT_OPTS}"}

# # Restart docker services
# sudo systemctl start docker
