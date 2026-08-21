#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${PROBEOS_BUILD_IMAGE:-probeos-builder:alpine-3.19}
LOG_DIR=${PROBEOS_LOG_DIR:-$ROOT/ci-logs/build}
mkdir -p "$LOG_DIR"
rm -f "$ROOT/out"/probeos-*.iso "$ROOT/out/SHA256SUMS" \
    "$ROOT/out/release-manifest.json"

docker build -t "$IMAGE" -f "$ROOT/build/alpine/Dockerfile" "$ROOT" 2>&1 | tee "$LOG_DIR/docker-builder.log"
docker run --rm -v "$ROOT:/workspace" "$IMAGE" rm -rf \
    /workspace/build/alpine/work /workspace/build/alpine/iso \
    /workspace/build/alpine/keys /workspace/build/alpine/modloop
for arch in x86_64 x86; do
    for bootloader in grub syslinux; do
        log="$LOG_DIR/probeos-$arch-$bootloader.log"
        ARCH="$arch" BOOTLOADER="$bootloader" PROBEOS_SKIP_DOCKER_BUILD=1 \
            "$ROOT/build/alpine/build-container.sh" 2>&1 | tee "$log"
        "$ROOT/tests/iso-layout.sh" "$ROOT/out/probeos-$arch-$bootloader.iso"
        "$ROOT/tests/iso-content-audit.sh" "$ROOT/out/probeos-$arch-$bootloader.iso"
    done
done
