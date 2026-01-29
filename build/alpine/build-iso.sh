#!/usr/bin/env bash
set -e

# ProbeOS Alpine ISO build script
# https://probeos.eu
# © 2026 Ploos AS

ROOTDIR="$(pwd)"
WORKDIR="$ROOTDIR/work"
ISODIR="$ROOTDIR/iso"
OUTDIR="$ROOTDIR/out"

ALPINE_VERSION="3.19"
ARCH="x86_64"

ISO_NAME="probeos-${ARCH}.iso"

PACKAGES_FILE="$ROOTDIR/build/alpine/packages.txt"

echo "[*] Building ProbeOS ISO"

rm -rf "$WORKDIR" "$ISODIR" "$OUTDIR"
mkdir -p "$WORKDIR" "$ISODIR" "$OUTDIR"

echo "[*] Installing Alpine base system"
apk --root "$WORKDIR" \
    --arch "$ARCH" \
    --keys-dir /etc/apk/keys \
    --repositories-file /etc/apk/repositories \
    add alpine-base $(grep -v '^#' "$PACKAGES_FILE")

echo "[*] Basic system configuration"

echo "probeos" > "$WORKDIR/etc/hostname"

cat > "$WORKDIR/etc/motd" <<EOF
ProbeOS
https://probeos.eu
© 2026 Ploos AS
EOF

echo "root:probeos" | chroot "$WORKDIR" chpasswd

echo "[*] Enabling essential services"
chroot "$WORKDIR" rc-update add devfs sysinit
chroot "$WORKDIR" rc-update add dmesg sysinit
chroot "$WORKDIR" rc-update add mdev sysinit
chroot "$WORKDIR" rc-update add hwdrivers sysinit

echo "[*] Creating initramfs"
chroot "$WORKDIR" mkinitfs -o /boot/initramfs-probeos

echo "[*] Preparing ISO structure"

mkdir -p "$ISODIR/boot/grub"
cp "$WORKDIR/boot/vmlinuz-lts" "$ISODIR/boot/vmlinuz"
cp "$WORKDIR/boot/initramfs-probeos" "$ISODIR/boot/initramfs"

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

echo "[*] Creating ISO image"

grub-mkrescue -o "$OUTDIR/$ISO_NAME" "$ISODIR"

echo "[✓] ISO created at $OUTDIR/$ISO_NAME"
