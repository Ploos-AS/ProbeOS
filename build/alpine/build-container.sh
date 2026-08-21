#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
IMAGE=${PROBEOS_BUILD_IMAGE:-probeos-builder:alpine-3.19}
ARCH=${ARCH:-x86_64}
BOOTLOADER=${BOOTLOADER:-grub}
eval "$(ARCH="$ARCH" "$REPO_ROOT/ci/version.sh" shell)"

if [[ ${PROBEOS_SKIP_DOCKER_BUILD:-0} != 1 ]]; then
    docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$REPO_ROOT"
fi
docker run --rm --privileged \
    -e ARCH="$ARCH" \
    -e BOOTLOADER="$BOOTLOADER" \
    -e GRUB_DEFAULT="${GRUB_DEFAULT:-}" \
    -e SYSLINUX_DEFAULT="${SYSLINUX_DEFAULT:-}" \
    -e PROBEOS_WEB_BIND="${PROBEOS_WEB_BIND:-}" \
    -e PROBEOS_VERSION="$PROBEOS_VERSION" \
    -e PROBEOS_BUILD_CHANNEL="$PROBEOS_BUILD_CHANNEL" \
    -e PROBEOS_GIT_COMMIT="$PROBEOS_GIT_COMMIT" \
    -e PROBEOS_GIT_SHORT_SHA="$PROBEOS_GIT_SHORT_SHA" \
    -e PROBEOS_ARCHITECTURE="$PROBEOS_ARCHITECTURE" \
    -v "$REPO_ROOT:/workspace" \
    -w /workspace \
    "$IMAGE" build/alpine/build-iso.sh
