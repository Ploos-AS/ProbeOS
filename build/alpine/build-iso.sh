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
BOOTLOADER="${BOOTLOADER:-grub}"
case "$BOOTLOADER" in
    grub|syslinux) ;;
    *) echo "[!] Unsupported bootloader: $BOOTLOADER" >&2; exit 1 ;;
esac
ISO_NAME="probeos-${ARCH}-${BOOTLOADER}.iso"
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"
APKDIR="$ISODIR/apks/$ARCH"
MODLOOPDIR="$REPO_ROOT/build/alpine/modloop"
KEYDIR="$REPO_ROOT/build/alpine/keys"
ALPINE_MAIN="https://dl-cdn.alpinelinux.org/alpine/v3.19/main"
ALPINE_COMMUNITY="https://dl-cdn.alpinelinux.org/alpine/v3.19/community"
MEMTEST_VERSION="8.10"
MEMTEST_ARCHIVE_URL="https://memtest.org/download/v${MEMTEST_VERSION}/mt86plus_${MEMTEST_VERSION}.binaries.zip"
MEMTEST_ARCHIVE_SHA256="7e6c5162cb84ab959aeb9d13c9cfd6976b0dec3b34936b73820b20c55eb26c29"
GRUB_DEFAULT="${GRUB_DEFAULT:-1}"
WEB_BIND="${PROBEOS_WEB_BIND:-127.0.0.1}"
case "$ARCH" in
    x86_64) MEMTEST_MEMBER="mt86p_810_x86_64" ;;
    x86) MEMTEST_MEMBER="mt86p_810_i586" ;;
    *) echo "[!] Unsupported Memtest86+ architecture: $ARCH" >&2; exit 1 ;;
esac

required_commands=(abuild-sign apk chroot curl mksquashfs openssl sha256sum tar unzip)
if [ "$BOOTLOADER" = grub ]; then
    required_commands+=(grub-mkrescue)
else
    required_commands+=(xorriso)
fi
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "[!] Missing build command: $command_name" >&2
        echo "[!] Use build/alpine/build-container.sh for a reproducible build." >&2
        exit 1
    }
done

echo "[*] Cleaning previous builds"
rm -rf "$WORKDIR" "$ISODIR" "$MODLOOPDIR" "$KEYDIR"
mkdir -p "$WORKDIR" "$ISODIR" "$OUTDIR"
rm -f "$OUTDIR/$ISO_NAME"

echo "[*] Installing Alpine base system and packages"
sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PACKAGES_FILE" | xargs apk --root "$WORKDIR" \
    --initdb \
    --no-scripts \
    --quiet \
    --arch "$ARCH" \
    --keys-dir /etc/apk/keys \
    --repository "$ALPINE_MAIN" \
    --repository "$ALPINE_COMMUNITY" \
    add
chroot "$WORKDIR" /bin/busybox --install -s

echo "[*] Configuring system"
echo "probeos" > "$WORKDIR/etc/hostname"

cat > "$WORKDIR/etc/motd" <<EOF
ProbeOS
https://probeos.eu
© 2026 Ploos AS
EOF

echo "root:probeos" | chroot "$WORKDIR" /bin/busybox chpasswd

echo "[*] Enabling essential services"
chroot "$WORKDIR" rc-update add devfs sysinit
chroot "$WORKDIR" rc-update add mdev sysinit
chroot "$WORKDIR" rc-update add hwdrivers sysinit
chroot "$WORKDIR" rc-update add hostname boot
chroot "$WORKDIR" rc-update add local default

mkdir -p "$WORKDIR/etc/local.d"
cat > "$WORKDIR/etc/local.d/probe-identify.start" <<'EOF'
#!/bin/sh
if [ ! -x /usr/local/bin/probe-identify ]; then
    echo 'PROBEOS_BOOT_FAIL probe-identify=missing' >/dev/console
    exit 1
fi
mkdir -p /run/probeos
if ! /usr/local/bin/probe-identify >/run/probeos/probe-identify.log 2>&1; then
    echo 'PROBEOS_BOOT_FAIL probe-identify=failed' >/dev/console
    exit 1
fi
if ! jq empty /run/probeos/report.json >/dev/null 2>&1; then
    echo 'PROBEOS_BOOT_FAIL report_json=invalid' >/dev/console
    exit 1
fi
if [ ! -s /run/probeos/report.txt ]; then
    echo 'PROBEOS_BOOT_FAIL report_txt=missing' >/dev/console
    exit 1
fi
boot_mode=$(jq -er '.firmware.boot_mode | select(. == "BIOS" or . == "UEFI")' \
    /run/probeos/report.json) || {
    echo 'PROBEOS_BOOT_FAIL firmware=invalid' >/dev/console
    exit 1
}
echo "PROBEOS_BOOT_OK init=/sbin/init probe-identify=present report_txt=present report_json=valid firmware=$boot_mode" >/dev/console
EOF
chmod +x "$WORKDIR/etc/local.d/probe-identify.start"

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
cp "$REPO_ROOT/src/scripts/probeos-network" "$WORKDIR/usr/local/bin/probeos-network"
cp "$REPO_ROOT/src/scripts/probeos-udhcpc" "$WORKDIR/usr/local/bin/probeos-udhcpc"
cp "$REPO_ROOT/src/scripts/probeos-web" "$WORKDIR/usr/local/bin/probeos-web"
cp "$REPO_ROOT/src/scripts/probe-identify" "$WORKDIR/usr/local/bin/probe-identify"
mkdir -p "$WORKDIR/usr/local/lib/probeos"
cp "$REPO_ROOT/src/lib/probe-identify-lib.sh" "$WORKDIR/usr/local/lib/probeos/probe-identify-lib.sh"
cp "$REPO_ROOT/src/web/probeos_web.py" "$WORKDIR/usr/local/lib/probeos/probeos_web.py"
mkdir -p "$WORKDIR/etc/init.d" "$WORKDIR/etc/conf.d"
cp "$SCRIPT_DIR/init.d/probeos-network" "$WORKDIR/etc/init.d/probeos-network"
cp "$SCRIPT_DIR/init.d/probeos-web" "$WORKDIR/etc/init.d/probeos-web"
cp "$SCRIPT_DIR/conf.d/probeos-web" "$WORKDIR/etc/conf.d/probeos-web"
sed -i "s|^PROBEOS_WEB_BIND=.*|PROBEOS_WEB_BIND=\"$WEB_BIND\"|" "$WORKDIR/etc/conf.d/probeos-web"
chroot "$WORKDIR" rc-update add probeos-network default
chroot "$WORKDIR" rc-update add probeos-web default
# Replace the literal runtime fallback.
# shellcheck disable=SC2016
sed -i 's|$SELF_DIR/../lib/probe-identify-lib.sh|/usr/local/lib/probeos/probe-identify-lib.sh|' "$WORKDIR/usr/local/bin/probe-identify"
chmod +x "$WORKDIR/usr/local/bin/"*.sh
chmod +x "$WORKDIR/usr/local/bin/probeos-network" "$WORKDIR/usr/local/bin/probeos-udhcpc" "$WORKDIR/usr/local/bin/probeos-web" "$WORKDIR/etc/init.d/probeos-network" "$WORKDIR/etc/init.d/probeos-web"
chmod +x "$WORKDIR/usr/local/bin/probe-identify"

# =========================================
# Open-source Memtest86+ payload
# =========================================
echo "[*] Installing Memtest86+ v$MEMTEST_VERSION"
MEMTEST_DIR="$WORKDIR/memtest"
MEMTEST_ARCHIVE="$WORKDIR/memtest86plus.zip"
mkdir -p "$MEMTEST_DIR"
curl -fsSL "$MEMTEST_ARCHIVE_URL" -o "$MEMTEST_ARCHIVE"
printf '%s  %s\n' "$MEMTEST_ARCHIVE_SHA256" "$MEMTEST_ARCHIVE" | sha256sum -c -
unzip -q -j "$MEMTEST_ARCHIVE" "$MEMTEST_MEMBER" -d "$MEMTEST_DIR"
mv "$MEMTEST_DIR/$MEMTEST_MEMBER" "$MEMTEST_DIR/mt86plus"

# =========================================
# Initramfs
# =========================================
echo "[*] Creating initramfs"
set -- "$WORKDIR"/lib/modules/*
KERNEL_VERSION=${1##*/}
chroot "$WORKDIR" depmod "$KERNEL_VERSION"
chroot "$WORKDIR" mkinitfs -o /boot/initramfs-probeos "$KERNEL_VERSION"

# =========================================
# Alpine-native diskless live system
# =========================================
echo "[*] Creating offline APK repository"
mkdir -p "$ISODIR/boot"
mkdir -p "$APKDIR"
mapfile -t INSTALLED_PACKAGES < <(
    awk '/^P:/{print substr($0, 3)}' "$WORKDIR/lib/apk/db/installed"
)
apk fetch --quiet --no-cache --arch "$ARCH" --keys-dir /etc/apk/keys \
    --repository "$ALPINE_MAIN" --repository "$ALPINE_COMMUNITY" \
    --output "$APKDIR" "${INSTALLED_PACKAGES[@]}"
apk index --rewrite-arch "$ARCH" --output "$APKDIR/APKINDEX.tar.gz" "$APKDIR"/*.apk
mkdir -p "$KEYDIR" "$WORKDIR/etc/apk/keys"
openssl genrsa -out "$KEYDIR/probeos-build.rsa" 2048 >/dev/null 2>&1
openssl rsa -in "$KEYDIR/probeos-build.rsa" -pubout \
    -out "$KEYDIR/probeos-build.rsa.pub" >/dev/null 2>&1
abuild-sign -k "$KEYDIR/probeos-build.rsa" "$APKDIR/APKINDEX.tar.gz"
cp "$KEYDIR/probeos-build.rsa.pub" "$WORKDIR/etc/apk/keys/"
touch "$ISODIR/apks/.boot_repository"
cp "$WORKDIR/etc/alpine-release" "$ISODIR/.alpine-release"

echo "[*] Creating kernel modloop"
mkdir -p "$MODLOOPDIR/modules"
cp -a "$WORKDIR/lib/modules/." "$MODLOOPDIR/modules/"
mksquashfs "$MODLOOPDIR" "$ISODIR/boot/modloop-lts" -comp xz -noappend -quiet

echo "[*] Creating ProbeOS APK overlay"
rm -f "$WORKDIR/etc/apk/repositories"
tar -C "$WORKDIR" -czf "$ISODIR/probeos.apkovl.tar.gz" \
    etc usr/local usr/share/probeos

mkdir -p "$ISODIR/boot/memtest"
cp "$MEMTEST_DIR/mt86plus" "$ISODIR/boot/memtest/mt86plus"

# =========================================
# ISO preparation
# =========================================
cp "$WORKDIR/boot/vmlinuz-lts" "$ISODIR/boot/vmlinuz"
cp "$WORKDIR/boot/initramfs-probeos" "$ISODIR/boot/initramfs"

if [ "$BOOTLOADER" = grub ]; then
    mkdir -p "$ISODIR/boot/grub"
    cat > "$ISODIR/boot/grub/grub.cfg" <<EOF
set default=$GRUB_DEFAULT
set timeout=5

menuentry "ProbeOS (GUI)" {
    linux /boot/vmlinuz modules=loop,squashfs,sd-mod,usb-storage modloop=/boot/modloop-lts quiet
    initrd /boot/initramfs
}

menuentry "ProbeOS (Text / Curses)" {
    linux /boot/vmlinuz modules=loop,squashfs,sd-mod,usb-storage modloop=/boot/modloop-lts console=tty0 console=ttyS0,115200 text
    initrd /boot/initramfs
}

menuentry "ProbeOS - Memory Test (Memtest86+)" {
    linux /boot/memtest/mt86plus console=ttyS0,115200
}
EOF
else
    SYSLINUX_DIR="$ISODIR/boot/syslinux"
    SYSLINUX_SHARE=/usr/share/syslinux
    mkdir -p "$SYSLINUX_DIR"
    cp "$REPO_ROOT/boot/syslinux/isolinux.cfg" "$SYSLINUX_DIR/isolinux.cfg"
    if [ -n "${SYSLINUX_DEFAULT:-}" ]; then
        sed -i "s/^DEFAULT .*/DEFAULT $SYSLINUX_DEFAULT/" "$SYSLINUX_DIR/isolinux.cfg"
    fi
    for syslinux_file in isolinux.bin ldlinux.c32 menu.c32 libcom32.c32 libutil.c32; do
        [ -r "$SYSLINUX_SHARE/$syslinux_file" ] || {
            echo "[!] Missing SYSLINUX build artifact: $SYSLINUX_SHARE/$syslinux_file" >&2
            exit 1
        }
        cp "$SYSLINUX_SHARE/$syslinux_file" "$SYSLINUX_DIR/"
    done
    [ -r "$SYSLINUX_SHARE/isohdpfx.bin" ] || {
        echo "[!] Missing SYSLINUX hybrid MBR: $SYSLINUX_SHARE/isohdpfx.bin" >&2
        exit 1
    }
fi

# =========================================
# Build ISO
# =========================================
echo "[*] Creating ISO image"

if [ "$BOOTLOADER" = grub ]; then
    grub-mkrescue -o "$OUTDIR/$ISO_NAME" "$ISODIR" -- -volid PROBEOS
else
    xorriso -as mkisofs \
        -o "$OUTDIR/$ISO_NAME" \
        -volid PROBEOS \
        -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
        -partition_offset 16 \
        -c boot/syslinux/boot.cat \
        -b boot/syslinux/isolinux.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        "$ISODIR"
fi

rm -rf "$KEYDIR"

echo "[✓] ISO created at $OUTDIR/$ISO_NAME"
