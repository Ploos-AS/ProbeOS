#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ISO=${1:?usage: iso-layout.sh ISO}
[[ -s "$ISO" ]] || { echo "ISO missing or empty: $ISO" >&2; exit 1; }
case $(basename "$ISO") in
    *-x86_64-*) arch=x86_64 ;;
    *-x86-*) arch=x86 ;;
    *) echo "cannot determine ISO architecture from filename: $ISO" >&2; exit 2 ;;
esac

listing=$(xorriso -indev "$ISO" -find / -type f -exec lsdl 2>/dev/null)
boot_cfg=$(mktemp "${TMPDIR:-/tmp}/probeos-boot.cfg.XXXXXX")
overlay=$(mktemp "${TMPDIR:-/tmp}/probeos-overlay.XXXXXX")
overlay_listing=$(mktemp "${TMPDIR:-/tmp}/probeos-overlay-list.XXXXXX")
trap 'rm -f "$boot_cfg" "$overlay" "$overlay_listing"' EXIT
case $(basename "$ISO") in
    *-grub.iso)
        bootloader=grub
        config_path=/boot/grub/grub.cfg
        ;;
    *-syslinux.iso)
        bootloader=syslinux
        config_path=/boot/syslinux/isolinux.cfg
        ;;
    *) echo "cannot determine ISO bootloader from filename: $ISO" >&2; exit 2 ;;
esac
xorriso -osirrox on -indev "$ISO" -extract "$config_path" "$boot_cfg" >/dev/null 2>&1
for path in \
    '/.alpine-release' \
    '/apks/.boot_repository' \
    '/boot/initramfs' \
    '/boot/memtest/mt86plus' \
    '/boot/modloop-lts' \
    '/boot/vmlinuz' \
    '/probeos.apkovl.tar.gz'; do
    grep -Fq "'$path'" <<<"$listing" || { echo "ISO file missing: $path" >&2; exit 1; }
done
xorriso -osirrox on -indev "$ISO" -extract /probeos.apkovl.tar.gz "$overlay" >/dev/null 2>&1
tar -tzf "$overlay" > "$overlay_listing"
grep -Eq '^etc/probeos-release$' "$overlay_listing" || {
    echo 'runtime ProbeOS identity missing from overlay' >&2
    exit 1
}
grep -Eq '^usr/local/bin/probe-qualify$' "$overlay_listing" || { echo 'qualification workflow missing from overlay' >&2; exit 1; }
grep -Fq "'$config_path'" <<<"$listing" || { echo "boot config missing: $config_path" >&2; exit 1; }
grep -Fq "/apks/$arch/APKINDEX.tar.gz" <<<"$listing" || { echo 'offline APK index missing' >&2; exit 1; }
grep -Fq 'ProbeOS - Memory Test (Memtest86+)' "$boot_cfg" || {
    echo "Memtest86+ $bootloader entry missing" >&2
    exit 1
}
if [[ $bootloader == grub ]]; then
    grep -Eq '^set default=1$' "$boot_cfg" || {
        echo 'normal ProbeOS text entry is not the GRUB default' >&2
        exit 1
    }
fi
if [[ $bootloader == syslinux ]]; then
    for path in isolinux.bin ldlinux.c32 menu.c32 libcom32.c32 libutil.c32; do
        grep -Fq "'/boot/syslinux/$path'" <<<"$listing" || {
            echo "SYSLINUX file missing: /boot/syslinux/$path" >&2
            exit 1
        }
    done
    grep -Eq '^DEFAULT[[:space:]]+probeos$' "$boot_cfg" || {
        echo 'normal ProbeOS is not the SYSLINUX default' >&2
        exit 1
    }
    boot_report=$(xorriso -indev "$ISO" -report_el_torito plain -report_system_area plain 2>&1)
    grep -Fq 'El Torito boot img :   1  BIOS  y' <<<"$boot_report" || {
        echo 'bootable BIOS El Torito image missing' >&2
        exit 1
    }
    grep -Fq 'System area summary: MBR isohybrid' <<<"$boot_report" || {
        echo 'SYSLINUX isohybrid MBR missing' >&2
        exit 1
    }
fi
echo "ok - ISO layout contains Alpine live media and ProbeOS overlay"
