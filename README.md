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

## Build and boot

The supported live-ISO build runs in Docker and pins Alpine 3.19:

```sh
build/alpine/build-container.sh
tests/iso-layout.sh out/probeos-x86_64-grub.iso
tests/qemu-smoke.sh out/probeos-x86_64-grub.iso bios
tests/qemu-smoke.sh out/probeos-x86_64-grub.iso uefi
# Optional legacy x86 qualification:
ARCH=x86 build/alpine/build-container.sh
QEMU=qemu-system-i386 tests/qemu-smoke.sh out/probeos-x86-grub.iso bios
```

The BIOS smoke test needs `qemu-system-x86_64`. The UEFI test additionally
needs OVMF at `/usr/share/OVMF`, or `OVMF_CODE` and `OVMF_VARS` set to suitable
firmware files. Both tests disable guest networking and write their serial logs
under `${TMPDIR:-/tmp}` unless a log path is passed as the third argument.

The resulting root login password is `probeos`. See
[`docs/build-audit.md`](docs/build-audit.md) for the live-media architecture,
qualification evidence, and current limitations.

---

## License

ProbeOS is open-source software licensed under the MIT License.

Copyright © 2026 Ploos AS

---

## Links

- Project site: https://probeos.eu
- Source code: https://github.com/ploos-as/probeos
