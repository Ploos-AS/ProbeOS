#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIR=${PROBEOS_LOG_DIR:-$ROOT/ci-logs/qemu}
mkdir -p "$LOG_DIR"

run_linux() {
    local arch=$1 bootloader=$2 mode=$3 qemu="qemu-system-x86_64"
    [[ $arch == x86 ]] && qemu="qemu-system-i386"
    QEMU="$qemu" "$ROOT/tests/qemu-smoke.sh" \
        "$ROOT/out/probeos-$arch-$bootloader.iso" "$mode" \
        "$LOG_DIR/probeos-$arch-$bootloader-$mode.log"
}

run_linux x86_64 grub bios
run_linux x86_64 grub uefi
run_linux x86 grub bios
run_linux x86_64 syslinux bios
run_linux x86 syslinux bios

# LAN mode is an explicit runtime choice; build a temporary equivalent so the
# host-forwarded test can reach the guest service. Final artifacts are restored
# by build-all.sh after this qualification script.
ARCH=x86_64 BOOTLOADER=grub PROBEOS_WEB_BIND=0.0.0.0 PROBEOS_SKIP_DOCKER_BUILD=1 \
    "$ROOT/build/alpine/build-container.sh"
"$ROOT/tests/qemu-lan-smoke.sh" "$ROOT/out/probeos-x86_64-grub.iso" \
    "$LOG_DIR/probeos-x86_64-grub-lan.log"

# Memtest needs a deterministic default-menu build. These are temporary images;
# build-all.sh must run again afterward before metadata/publication is generated.
for arch in x86_64 x86; do
    qemu="qemu-system-x86_64"
    [[ $arch == x86 ]] && qemu="qemu-system-i386"
    for bootloader in grub syslinux; do
        if [[ $bootloader == grub ]]; then
            ARCH="$arch" BOOTLOADER=grub GRUB_DEFAULT=2 PROBEOS_SKIP_DOCKER_BUILD=1 \
                "$ROOT/build/alpine/build-container.sh"
        else
            ARCH="$arch" BOOTLOADER=syslinux SYSLINUX_DEFAULT=memtest PROBEOS_SKIP_DOCKER_BUILD=1 \
                "$ROOT/build/alpine/build-container.sh"
        fi
        QEMU="$qemu" "$ROOT/tests/memtest-smoke.sh" \
            "$ROOT/out/probeos-$arch-$bootloader.iso" bios \
            "$LOG_DIR/probeos-$arch-$bootloader-memtest-bios.log"
        if [[ $arch == x86_64 && $bootloader == grub ]]; then
            "$ROOT/tests/memtest-smoke.sh" "$ROOT/out/probeos-x86_64-grub.iso" uefi \
                "$LOG_DIR/probeos-x86_64-grub-memtest-uefi.log"
        fi
    done
done
