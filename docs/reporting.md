<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Report profiles

ProbeOS probes hardware once and stores the result in the authoritative
`report.json`. The `sale`, `detailed`, and `full` presentations are derived from
that document; they never run their own hardware probes.

## Sale (default)

The sale profile answers the questions normally needed for a computer listing:
system make/model, CPU and topology, installed memory, graphics, storage type,
capacity and defensible PASS/WARN/FAIL/UNKNOWN health, network adapters,
firmware mode/version, detected Windows installations and useful battery data.
Missing values are omitted. Multiple devices and installations are retained.

Sale output is written as `sale.txt`, `sale.json`, and standalone `sale.html`.
`report.txt` is the same privacy-safe sale text for compatibility. The HTML has
no JavaScript, external resources, or network dependency and is suitable for
printing.

Sale reports exclude serial numbers, UUIDs, MAC addresses, Windows product
keys, and other key-shaped fields. They are intended to be shareable, although
users should still review any report before publishing it.

## Detailed and full

The detailed profile presents substantially more topology, DIMM, firmware,
graphics, storage, network, power, and Windows metadata in readable sections.
The full profile additionally retains advanced PCI, USB, and sensor inventory.
Both apply normal redaction: `full` means complete technical inventory, not
automatic disclosure of secrets.

Outputs are `detailed.txt`/`detailed.json` and `full.txt`/`full.json`. The local
TUI and GUI expose profile viewing and export. Ordinary Web/API access remains
redacted and read-only. `/api/v1/profiles` describes profiles and
`/api/v1/report/{sale,detailed,full}` returns their JSON presentations.

## Schema compatibility

The authoritative schema is 1.1. It adds `report_profiles`,
`default_human_profile`, structured recovered-key metadata, and an explicit
digital-license uncertainty value. Existing schema-1.0 inventory fields keep
their meanings. Presentation JSON is identified by `profile` or
`report_profile` and is not a replacement for authoritative `report.json`.
