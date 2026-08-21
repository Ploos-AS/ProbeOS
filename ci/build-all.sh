#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${PROBEOS_BUILD_IMAGE:-probeos-builder:alpine-3.19}
LOG_DIR=${PROBEOS_LOG_DIR:-$ROOT/ci-logs/build}
mkdir -p "$LOG_DIR"

docker build -t "$IMAGE" -f "$ROOT/build/alpine/Dockerfile" "$ROOT" 2>&1 | tee "$LOG_DIR/docker-builder.log"
for arch in x86_64 x86; do
    for bootloader in grub syslinux; do
        log="$LOG_DIR/probeos-$arch-$bootloader.log"
        ARCH="$arch" BOOTLOADER="$bootloader" PROBEOS_SKIP_DOCKER_BUILD=1 \
            "$ROOT/build/alpine/build-container.sh" 2>&1 | tee "$log"
        "$ROOT/tests/iso-layout.sh" "$ROOT/out/probeos-$arch-$bootloader.iso"
    done
done
