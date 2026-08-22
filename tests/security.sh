#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
credential='root:'"probeos"

if rg -n -F "$credential" "$ROOT" --glob '!tests/security.sh' --glob '!out/**' --glob '!build/alpine/work/**' --glob '!build/alpine/iso/**'; then
    echo 'historical shared credential remains in source' >&2; exit 1
fi
grep -Fq 'passwd -l root' "$ROOT/build/alpine/build-iso.sh"
grep -Fq 'tty1::respawn:/usr/local/bin/probeos-console' "$ROOT/build/alpine/build-iso.sh"
grep -Fq 'Open Privileged Shell' "$ROOT/src/scripts/tui-menu.sh"
grep -Fq 'Open Privileged Terminal' "$ROOT/src/scripts/gui-menu.sh"
for daemon in openssh-server dropbear; do
    if grep -Eq "^[[:space:]]*$daemon([[:space:]]|$)" "$ROOT/build/alpine/packages.txt"; then
        echo "remote shell package selected: $daemon" >&2; exit 1
    fi
done
for daemon in sshd dropbear telnetd rlogind rexecd; do
    if rg -n "rc-update add $daemon" "$ROOT/build" >/dev/null; then
        echo "remote shell service enabled: $daemon" >&2; exit 1
    fi
done
if rg -n 'subprocess|os\.system|os\.popen|exec\(|spawn|do_POST|do_PUT|do_PATCH|do_DELETE' "$ROOT/src/web/probeos_web.py"; then
    echo 'Web/API contains a command/write execution primitive' >&2; exit 1
fi
for tree in src tests docs; do
    if rg -n -i '(password|credential).{0,30}[A-Z0-9]{5}(-[A-Z0-9]{5}){4}' "$ROOT/$tree"; then
        echo "credential material found under $tree" >&2; exit 1
    fi
done
echo 'ok - local privilege and remote-administration source policy passed'
