#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Conservative offline Windows DigitalProductId decoder/classifier."""
import argparse
import json
import re
import sys

ALPHABET = "BCDFGHJKMPQRTVWXY2346789"
# Microsoft-published/default installation keys are not unique licenses.
GENERIC_KEYS = {
    "TX9XD-98N7V-6WMQ6-BX7FG-H8Q99", "3KHY7-WNT83-DGQKR-F7HPR-844BM",
    "7HNRX-D7KGG-3K4RQ-4WPJ4-YTDFH", "PVMJN-6DFY6-9CCP6-7BKTT-D3WVR",
    "W269N-WFGWX-YVC9B-4J6C9-T83GX", "MH37W-N47XK-V7XM9-C7227-GCQG9",
    "NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J", "9FNHH-K3HBT-3W4TD-6383H-6XYWF",
    "6TP4R-GNPTD-KYYHQ-7B7DP-J447Y", "YVWGF-BXNMC-HTQYQ-CPQ99-66QFC",
    "NPPR9-FWDCX-D2C8J-H872K-2YT43", "DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4",
    "NW6C2-QMPVW-D7KKK-3GKT6-VCFB2", "2WH4N-8QGBV-H22JP-CT43Q-MDWWJ",
    "YYVX9-NTFWV-6MDM3-9PT4T-4M68B", "44RPN-FTY23-9VTTB-MP9BX-T84FV",
    "2B87N-8KFHP-DKV6R-Y2C8J-PKCKT",
}


def decode(data):
    if len(data) < 67:
        return None
    digits = bytearray(data[52:67])
    win8 = (digits[14] // 6) & 1
    digits[14] = (digits[14] & 0xF7) | ((win8 & 2) * 4)
    decoded = ""
    last = 0
    for _ in range(25):
        current = 0
        for index in range(14, -1, -1):
            current = current * 256 + digits[index]
            digits[index] = current // 24
            current %= 24
        decoded = ALPHABET[current] + decoded
        last = current
    if win8:
        decoded = decoded[1:last + 1] + "N" + decoded[last + 1:]
    return "-".join(decoded[i:i + 5] for i in range(0, 25, 5))


def registry_bytes(text):
    match = re.search(r'^"DigitalProductId"=hex(?:\([0-9a-f]+\))?:(.*?)(?=\n(?:"|\[)|\Z)', text,
                      re.I | re.M | re.S)
    if not match:
        return None
    values = re.findall(r'(?<![0-9a-f])([0-9a-f]{2})(?![0-9a-f])', match.group(1), re.I)
    return bytes(int(value, 16) for value in values)


def classify(key, channel=None):
    generic = key.upper() in GENERIC_KEYS
    kind = "generic" if generic else "unknown"
    confidence = "high" if generic else "low"
    reusable = "not_established" if generic else "possible_not_guaranteed"
    if channel and "OEM_DM" in channel.upper() and not generic:
        kind, confidence = "OEM_DM", "medium"
    return {"key": key, "key_type": kind, "confidence": confidence,
            "reusable_hint": reusable}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry-export", action="store_true")
    parser.add_argument("--key")
    parser.add_argument("--channel")
    args = parser.parse_args()
    key = args.key
    if args.registry_export:
        raw = registry_bytes(sys.stdin.read())
        key = decode(raw) if raw else None
    if not key or not re.fullmatch(r"[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}", key, re.I):
        print("null")
        return
    print(json.dumps(classify(key.upper(), args.channel)))


if __name__ == "__main__":
    main()
