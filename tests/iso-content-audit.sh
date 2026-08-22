#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ISO=${1:?usage: iso-content-audit.sh ISO}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-content-audit.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

listing=$(xorriso -indev "$ISO" -find / -exec lsdl 2>/dev/null)
if grep -Eiq "(^|[ '/])(\.git|\.ssh|home|root)/(.*)?(id_rsa|id_ed25519|credentials|\.git)|\.(pem|key)'" <<<"$listing"; then
    echo "suspicious developer/credential path in $(basename "$ISO")" >&2
    exit 1
fi
xorriso -osirrox on -indev "$ISO" -extract /probeos.apkovl.tar.gz "$WORK/overlay.tgz" >/dev/null 2>&1
tar -xzf "$WORK/overlay.tgz" -C "$WORK"
root_field=$(awk -F: '$1=="root" {print $2}' "$WORK/etc/shadow")
case "$root_field" in \!*|\**) ;; *) echo 'ISO root password is not locked' >&2; exit 1;; esac
while IFS=: read -r account _ uid _; do
    [ "$uid" != 0 ] || [ "$account" = root ] || {
        field=$(awk -F: -v name="$account" '$1==name {print $2}' "$WORK/etc/shadow")
        case "$field" in \!*|\**) ;; *) echo 'unexpected reusable administrative password in ISO overlay' >&2; exit 1;; esac
    }
done < "$WORK/etc/passwd"
if rg -a -F 'root:'"probeos" "$WORK/overlay.tgz" "$WORK" >/dev/null; then
    echo 'historical shared credential found in ISO overlay' >&2; exit 1
fi
for service in sshd dropbear telnetd rlogind rexecd; do
    [ ! -e "$WORK/etc/runlevels/default/$service" ] || { echo "remote shell service enabled: $service" >&2; exit 1; }
done
if grep -sRIEq --binary-files=without-match \
        'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|XXXXX-XXXXX-XXXXX-XXXXX-AB234' \
        "$WORK/etc" "$WORK/usr"; then
    echo "secret-like content in $(basename "$ISO") overlay" >&2
    exit 1
fi
grep -Eq '^PROBEOS_BUILD_CHANNEL=(development|release|release-candidate)$' \
    "$WORK/etc/probeos-release"
grep -Eq '^PROBEOS_GIT_COMMIT=([0-9a-f]{40}|unknown)$' "$WORK/etc/probeos-release"
grep -Eq '^PROBEOS_BOOTLOADER=(grub|syslinux)$' "$WORK/etc/probeos-release"
grep -Eq '^PROBEOS_WEB_BIND="127\.0\.0\.1"$' "$WORK/etc/conf.d/probeos-web"
echo "ok - ISO content audit passed for $(basename "$ISO")"
