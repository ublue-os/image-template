#!/bin/bash

set -ex

TIMESTAMP=`date +%Y%m%d%H%M`
IMAGE_TAG_PREFIX=$USER/bazzite-kdeland-local

# BUILD ARGUMENTS:
BUILD_FROM_IMAGE=ghcr.io/ublue-os/bazzite-nvidia-open:stable
BUILD_SHELL=1
BUILD_HYPRLAND=1

docker build \
    -f Containerfile \
    --tag=${IMAGE_TAG_PREFIX}:${TIMESTAMP} \
    --tag=${IMAGE_TAG_PREFIX}:stable \
    --tag=${IMAGE_TAG_PREFIX}:latest \
    --build-arg BUILD_FROM_IMAGE="${BUILD_FROM_IMAGE}" \
    --build-arg BUILD_SHELL="${BUILD_SHELL}" \
    --build-arg BUILD_HYPRLAND="${BUILD_HYPRLAND}" \
    .
