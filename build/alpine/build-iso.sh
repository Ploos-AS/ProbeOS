#!/usr/bin/env bash
set -eu

# ProbeOS Alpine-native ISO build
# https://probeos.eu
# © 2026 Ploos AS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="$REPO_ROOT/build/alpine/work"
ISODIR="$REPO_ROOT/build/alpine/iso"
OUTDIR="$REPO_ROOT/out"

ARCH="${ARCH:-x86_64}"
ISO_NAME="probeos-${ARCH}.iso"
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"

echo "[*] Cleaning previous builds"
rm -rf "$WORKDIR" "$ISODIR" "$OUTDIR"
mkdir -p "$WORKDIR" "$ISODIR" "$OUTDIR"

echo "[*] Installing Alpine base system and packages"
sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PACKAGES_FILE" | xargs apk --root "$WORKDIR" \
    --initdb \
    --quiet \
    --arch "$ARCH" \
    --keys-dir /etc/apk/keys \
    --repository https://dl-cdn.alpinelinux.org/alpine/v3.19/main \
    --repository https://dl-cdn.alpinelinux.org/alpine/v3.19/community \
    add

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
chroot "$WORKDIR" rc-update add mdev sysinit
chroot "$WORKDIR" rc-update add hwdrivers sysinit

# =========================================
# Install assets (logo, wallpaper, splash)
# =========================================
echo "[*] Installing visual assets"

mkdir -p "$WORKDIR/usr/share/probeos"
cp "$REPO_ROOT/assets/logo/logo.png" "$WORKDIR/usr/share/probeos/"
if [ -f "$REPO_ROOT/assets/generated/wallpaper.png" ]; then
    cp "$REPO_ROOT/assets/generated/wallpaper.png" "$WORKDIR/usr/share/probeos/wallpaper.png"
fi

# =========================================
# Openbox configuration
# =========================================
echo "[*] Installing Openbox configuration"

mkdir -p "$WORKDIR/etc/xdg/openbox"
cp "$REPO_ROOT/assets/openbox/rc.xml" "$WORKDIR/etc/xdg/openbox/rc.xml"
cp "$REPO_ROOT/assets/openbox/autostart" "$WORKDIR/etc/xdg/openbox/autostart"
mkdir -p "$WORKDIR/etc/xdg/tint2"
cp "$REPO_ROOT/assets/openbox/tint2rc" "$WORKDIR/etc/xdg/tint2/tint2rc"

# =========================================
# Install ProbeOS scripts
# =========================================
echo "[*] Installing GUI and TUI scripts"

mkdir -p "$WORKDIR/usr/local/bin"
cp "$REPO_ROOT/src/scripts/tui-menu.sh" "$WORKDIR/usr/local/bin/tui-menu.sh"
cp "$REPO_ROOT/src/scripts/gui-menu.sh" "$WORKDIR/usr/local/bin/gui-menu.sh"
cp "$REPO_ROOT/src/scripts/probe-identify" "$WORKDIR/usr/local/bin/probe-identify"
mkdir -p "$WORKDIR/usr/local/lib/probeos"
cp "$REPO_ROOT/src/lib/probe-identify-lib.sh" "$WORKDIR/usr/local/lib/probeos/probe-identify-lib.sh"
# Replace the literal runtime fallback.
# shellcheck disable=SC2016
sed -i 's|$SELF_DIR/../lib/probe-identify-lib.sh|/usr/local/lib/probeos/probe-identify-lib.sh|' "$WORKDIR/usr/local/bin/probe-identify"
chmod +x "$WORKDIR/usr/local/bin/"*.sh
chmod +x "$WORKDIR/usr/local/bin/probe-identify"

# =========================================
# Initramfs
# =========================================
echo "[*] Creating initramfs"
set -- "$WORKDIR"/lib/modules/*
KERNEL_VERSION=${1##*/}
chroot "$WORKDIR" mkinitfs -o /boot/initramfs-probeos "$KERNEL_VERSION"

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
