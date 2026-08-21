#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-network-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
status=$(PROBEOS_NETWORK_RUNTIME_DIR="$WORK" "$ROOT/src/scripts/probeos-network" status json)
jq -e 'type=="array"' <<<"$status" >/dev/null
interfaces=$(PROBEOS_NETWORK_RUNTIME_DIR="$WORK" "$ROOT/src/scripts/probeos-network" interfaces)
if [ -n "$interfaces" ]; then
    while read -r iface; do
        [ -n "$iface" ] || continue
        [ "$iface" != lo ]
    done <<<"$interfaces"
fi
if PROBEOS_NETWORK_RUNTIME_DIR="$WORK" "$ROOT/src/scripts/probeos-network" static lo not-an-ip >/dev/null 2>&1; then
    echo 'invalid static IPv4 unexpectedly accepted' >&2
    exit 1
fi
echo 'ok - network status, interface discovery, and static IPv4 validation passed'
