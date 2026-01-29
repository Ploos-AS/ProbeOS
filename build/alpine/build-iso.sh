#!/usr/bin/env bash
set -e

# ProbeOS Alpine-native ISO build
# https://probeos.eu
# © 2026 Ploos AS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="$REPO_ROOT/build/alpine/work"
ISODIR="$REPO_ROOT/build/alpine/iso"
OUTDIR="$REPO_ROOT/out"

ARCH="x86_64"
ISO_NAME="probeos-${ARCH}.iso"
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"

ALPINE_VERSION="3.19"
ARCH="x86_64"

ISO_NAME="probeos-${ARCH}.iso"

PACKAGES_FILE="$ROOTDIR/build/alpine/packages.txt"

echo "[*] Cleaning previous builds"
rm -rf "$WORKDIR" "$ISODIR" "$OUTDIR"
mkdir -p "$WORKDIR" "$ISODIR" "$OUTDIR"

echo "[*] Installing Alpine base system and packages"
apk --root "$WORKDIR" \
    --arch "$ARCH" \
    --keys-dir /etc/apk/keys \
    --repositories-file /etc/apk/repositories \
    add alpine-base $(grep -v '^#' "$PACKAGES_FILE")

echo "[*] Configuring system"
echo "probeos" > "$WORKDIR/etc/hostname"

cat > "$WORKDIR/etc/motd" <<EOF
ProbeOS
https://probeos.eu
© 2026 Ploos AS
EOF

echo "root:probeos" | chroot "$WORKDIR" chpasswd

echo "[*] Enabling essential services"
chroot "$WORKDIR" rc-update add devfs sysinit
chroot "$WORKDIR" rc-update add sysinit
chroot "$WORKDIR" rc-update add mdev sysinit
chroot "$WORKDIR" rc-update add hwdrivers sysinit

# =========================================
# Install assets (logo, wallpaper, splash)
# =========================================
echo "[*] Installing visual assets"

mkdir -p "$WORKDIR/usr/share/probeos"
cp -r "$ROOTDIR/assets/logo/logo.png" "$WORKDIR/usr/share/probeos/"
cp "$ROOTDIR/assets/generated/wallpaper.png" "$WORKDIR/usr/share/probeos/wallpaper.png"
cp "$ROOTDIR/assets/generated/splash.png" "$WORKDIR/usr/share/probeos/splash.png"

# =========================================
# Openbox configuration
# =========================================
echo "[*] Installing Openbox configuration"

mkdir -p "$WORKDIR/etc/xdg/openbox"
cp "$ROOTDIR/assets/openbox/rc.xml" "$WORKDIR/etc/xdg/openbox/rc.xml"
cp "$ROOTDIR/assets/openbox/autostart" "$WORKDIR/etc/xdg/openbox/autostart"
mkdir -p "$WORKDIR/etc/xdg/tint2"
cp "$ROOTDIR/assets/openbox/tint2rc" "$WORKDIR/etc/xdg/tint2/tint2rc"

# =========================================
# Install ProbeOS scripts
# =========================================
echo "[*] Installing GUI and TUI scripts"

mkdir -p "$WORKDIR/usr/local/bin"
cp "$ROOTDIR/src/scripts/tui-menu.sh" "$WORKDIR/usr/local/bin/tui-menu.sh"
cp "$ROOTDIR/src/scripts/gui-menu.sh" "$WORKDIR/usr/local/bin/gui-menu.sh"
chmod +x "$WORKDIR/usr/local/bin/"*.sh

# =========================================
# Initramfs
# =========================================
echo "[*] Creating initramfs"
chroot "$WORKDIR" mkinitfs -o /boot/initramfs-probeos

# =========================================
# ISO preparation
# =========================================
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

# =========================================
# Build ISO
# =========================================
echo "[*] Creating ISO image"

grub-mkrescue -o "$OUTDIR/$ISO_NAME" "$ISODIR"

echo "[✓] ISO created at $OUTDIR/$ISO_NAME"
