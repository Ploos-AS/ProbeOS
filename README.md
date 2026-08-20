# ProbeOS

ProbeOS is a lightweight, bootable Linux environment for hardware inspection,
diagnostics, and performance benchmarking.

It is designed to boot quickly from USB or CD and provide clear, trustworthy
insight into system hardware without requiring installation or modifying disks.

Project homepage: https://probeos.eu

---

## Goals

- Hardware-first user experience
- Fast boot, minimal footprint
- Fully redistributable and open
- GUI and text-based (TUI) operation
- Suitable for diagnostics, verification, and benchmarking

---

## Status

ProbeOS is in early development (v0.1).  
Interfaces, tools, and features are subject to change.

## Hardware reports

`probe-identify` is the central read-only hardware inventory. It generates a
human-readable report and stable-schema JSON under `/run/probeos`. See
[`docs/hardware-identification.md`](docs/hardware-identification.md) for data
sources, Windows OEM-license handling, privacy guidance, and limitations.

---

## License

ProbeOS is open-source software licensed under the MIT License.

Copyright © 2026 Ploos AS

---

## Links

- Project site: https://probeos.eu
- Source code: https://github.com/ploos-as/probeos
