#!/usr/bin/env bash
set -e

# ProbeOS ISO build on Ubuntu/Debian host
# Uses Alpine minirootfs
# https://probeos.eu
# © 2026 Ploos AS

ROOTDIR="$(pwd)"
WORKDIR="$ROOTDIR/work"
ROOTFS="$WORKDIR/rootfs"
ISODIR="$ROOTDIR/iso"
OUTDIR="$ROOTDIR/out"
MINIROOTFS="$WORKDIR/alpine-minirootfs.tar.gz"
ARCH="x86_64"
ISO_NAME="probeos-${ARCH}.iso"
PACKAGES_FILE="$ROOTDIR/build/alpine/packages.txt"

# =========================
# 1. Prepare directories
# =========================
echo "[*] Cleaning previous builds"
rm -rf "$WORKDIR" "$ISODIR" "$OUTDIR"
mkdir -p "$WORKDIR" "$ISODIR" "$OUTDIR"

# =========================
# 2. Download Alpine minirootfs
# =========================
if [ ! -f "$MINIROOTFS" ]; then
    echo "[*] Downloading Alpine minirootfs"
    wget -O "$MINIROOTFS" "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.0-x86_64.tar.gz"
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
echo "https://dl-cdn.alpinelinux.org/alpine/v3.19/main" > "$ROOTFS/etc/apk/repositories"

# =========================
# 5. Install packages
# =========================
echo "[*] Installing packages into rootfs"
if [ ! -f "$PACKAGES_FILE" ]; then
    echo "[!] ERROR: $PACKAGES_FILE not found"
    exit 1
fi
xargs -a "$PACKAGES_FILE" apk --root "$ROOTFS" --arch "$ARCH" --no-cache add

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
chroot "$ROOTFS" rc-update add sysinit
chroot "$ROOTFS" rc-update add mdev sysinit
chroot "$ROOTFS" rc-update add hwdrivers sysinit

# =========================
# 7. Install assets
# =========================
mkdir -p "$ROOTFS/usr/share/probeos"
cp -r "$ROOTDIR/assets/logo/logo.png" "$ROOTFS/usr/share/probeos/"
cp "$ROOTDIR/assets/generated/wallpaper.png" "$ROOTFS/usr/share/probeos/wallpaper.png"
cp "$ROOTDIR/assets/generated/splash.png" "$ROOTFS/usr/share/probeos/splash.png"

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
chmod +x "$ROOTFS/usr/local/bin/"*.sh

# =========================
# 8. Initramfs
# =========================
echo "[*] Creating initramfs"
chroot "$ROOTFS" mkinitfs -o /boot/initramfs-probeos

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
