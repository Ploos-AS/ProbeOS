#!/usr/bin/env bash
set -euo pipefail

ISO=${1:?usage: iso-layout.sh ISO}
[[ -s "$ISO" ]] || { echo "ISO missing or empty: $ISO" >&2; exit 1; }
case $(basename "$ISO") in
    *-x86_64-*) arch=x86_64 ;;
    *-x86-*) arch=x86 ;;
    *) echo "cannot determine ISO architecture from filename: $ISO" >&2; exit 2 ;;
esac

listing=$(xorriso -indev "$ISO" -find / -type f -exec lsdl 2>/dev/null)
for path in \
    '/.alpine-release' \
    '/apks/.boot_repository' \
    '/boot/grub/grub.cfg' \
    '/boot/initramfs' \
    '/boot/modloop-lts' \
    '/boot/vmlinuz' \
    '/probeos.apkovl.tar.gz'; do
    grep -Fq "'$path'" <<<"$listing" || { echo "ISO file missing: $path" >&2; exit 1; }
done
grep -Fq "/apks/$arch/APKINDEX.tar.gz" <<<"$listing" || { echo 'offline APK index missing' >&2; exit 1; }
echo "ok - ISO layout contains Alpine live media and ProbeOS overlay"
