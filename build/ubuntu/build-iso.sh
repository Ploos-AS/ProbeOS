#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

echo 'This historical prototype builder is unsupported; use build/alpine/build-container.sh.' >&2
exit 2

# ProbeOS ISO build on Ubuntu/Debian host
# Uses Alpine minirootfs
# https://probeos.eu
# © 2026 Ploos AS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOTDIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKDIR="$ROOTDIR/build/ubuntu/work"
ROOTFS="$WORKDIR/rootfs"
ISODIR="$ROOTDIR/iso"
OUTDIR="$ROOTDIR/out"
ARCH="${ARCH:-x86_64}"
MINIROOTFS="$WORKDIR/alpine-minirootfs-${ARCH}.tar.gz"
ISO_NAME="probeos-${ARCH}.iso"
PACKAGES_FILE="$ROOTDIR/build/alpine/packages.txt"

# =========================
# 1. Prepare directories
# =========================
echo "[*] Cleaning previous builds"
rm -rf "$WORKDIR" "$ISODIR"
mkdir -p "$WORKDIR" "$ISODIR" "$OUTDIR"

# =========================
# 2. Download Alpine minirootfs
# =========================
if [ ! -f "$MINIROOTFS" ]; then
    echo "[*] Downloading Alpine minirootfs"
    wget -O "$MINIROOTFS" "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/${ARCH}/alpine-minirootfs-3.19.0-${ARCH}.tar.gz"
fi

# =========================
# 3. Extract rootfs
# =========================
echo "[*] Extracting minirootfs"
mkdir -p "$ROOTFS"
tar -xzf "$MINIROOTFS" -C "$ROOTFS"

# =========================
# 4. Setup apk repos
# =========================
mkdir -p "$ROOTFS/etc/apk"
cat > "$ROOTFS/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v3.19/main
https://dl-cdn.alpinelinux.org/alpine/v3.19/community
EOF

# =========================
# 5. Install packages
# =========================
echo "[*] Installing packages into rootfs"
if [ ! -f "$PACKAGES_FILE" ]; then
    echo "[!] ERROR: $PACKAGES_FILE not found"
    exit 1
fi
sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PACKAGES_FILE" | xargs apk --root "$ROOTFS" --arch "$ARCH" --no-cache add

# =========================
# 6. Configure system
# =========================
echo "probeos" > "$ROOTFS/etc/hostname"

cat > "$ROOTFS/etc/motd" <<EOF
ProbeOS
https://probeos.eu
© 2026 Ploos AS
EOF

echo "root:probeos" | chroot "$ROOTFS" chpasswd

# Enable essential services
chroot "$ROOTFS" rc-update add devfs sysinit
chroot "$ROOTFS" rc-update add mdev sysinit
chroot "$ROOTFS" rc-update add hwdrivers sysinit

# =========================
# 7. Install assets
# =========================
mkdir -p "$ROOTFS/usr/share/probeos"
cp -r "$ROOTDIR/assets/logo/logo.png" "$ROOTFS/usr/share/probeos/"
if [ -f "$ROOTDIR/assets/generated/wallpaper.png" ]; then
    cp "$ROOTDIR/assets/generated/wallpaper.png" "$ROOTFS/usr/share/probeos/wallpaper.png"
fi

# Openbox configuration
mkdir -p "$ROOTFS/etc/xdg/openbox"
cp "$ROOTDIR/assets/openbox/rc.xml" "$ROOTFS/etc/xdg/openbox/rc.xml"
cp "$ROOTDIR/assets/openbox/autostart" "$ROOTFS/etc/xdg/openbox/autostart"
mkdir -p "$ROOTFS/etc/xdg/tint2"
cp "$ROOTDIR/assets/openbox/tint2rc" "$ROOTFS/etc/xdg/tint2/tint2rc"

# ProbeOS scripts
mkdir -p "$ROOTFS/usr/local/bin"
cp "$ROOTDIR/src/scripts/tui-menu.sh" "$ROOTFS/usr/local/bin/"
cp "$ROOTDIR/src/scripts/gui-menu.sh" "$ROOTFS/usr/local/bin/"
cp "$ROOTDIR/src/scripts/probe-identify" "$ROOTFS/usr/local/bin/"
mkdir -p "$ROOTFS/usr/local/lib/probeos"
cp "$ROOTDIR/src/lib/probe-identify-lib.sh" "$ROOTFS/usr/local/lib/probeos/"
# Replace the literal runtime fallback.
# shellcheck disable=SC2016
sed -i 's|$SELF_DIR/../lib/probe-identify-lib.sh|/usr/local/lib/probeos/probe-identify-lib.sh|' "$ROOTFS/usr/local/bin/probe-identify"
chmod +x "$ROOTFS/usr/local/bin/"*.sh
chmod +x "$ROOTFS/usr/local/bin/probe-identify"

# =========================
# 8. Initramfs
# =========================
echo "[*] Creating initramfs"
set -- "$ROOTFS"/lib/modules/*
KERNEL_VERSION=${1##*/}
chroot "$ROOTFS" mkinitfs -o /boot/initramfs-probeos "$KERNEL_VERSION"

# =========================
# 9. Prepare ISO
# =========================
mkdir -p "$ISODIR/boot/grub"
cp "$ROOTFS/boot/vmlinuz-lts" "$ISODIR/boot/vmlinuz"
cp "$ROOTFS/boot/initramfs-probeos" "$ISODIR/boot/initramfs"

cat > "$ISODIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5

menuentry "ProbeOS (GUI)" {
    linux /boot/vmlinuz quiet
    initrd /boot/initramfs
}

menuentry "ProbeOS (Text / Curses)" {
    linux /boot/vmlinuz quiet text
    initrd /boot/initramfs
}

menuentry "Memory Test (Memtest86+)" {
    linux16 /boot/memtest86+.bin
}
EOF

# =========================
# 10. Build ISO
# =========================
echo "[*] Creating ISO image"
grub-mkrescue -o "$OUTDIR/$ISO_NAME" "$ISODIR"

echo "[✓] Ubuntu/Debian ISO created at $OUTDIR/$ISO_NAME"
