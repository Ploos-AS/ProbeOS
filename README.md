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
human-readable report and stable-schema JSON under `/run/probeos`. The optional
retro-friendly local Web UI/API presents that same report without probing again.
See
[`docs/hardware-identification.md`](docs/hardware-identification.md) for data
sources, Windows OEM-license handling, privacy guidance, and limitations.
See [docs/web-api.md](docs/web-api.md) and [docs/networking.md](docs/networking.md)
for Web/API and LAN operation.

## Build and boot

The supported live-ISO build runs in Docker and pins Alpine 3.19. GRUB is the
modern BIOS/UEFI path; SYSLINUX is retained as a BIOS-only compatibility path
for legacy systems:

```sh
build/alpine/build-container.sh
BOOTLOADER=syslinux build/alpine/build-container.sh
ARCH=x86 build/alpine/build-container.sh
ARCH=x86 BOOTLOADER=syslinux build/alpine/build-container.sh
tests/iso-layout.sh out/probeos-x86_64-grub.iso
tests/iso-layout.sh out/probeos-x86_64-syslinux.iso
tests/qemu-smoke.sh out/probeos-x86_64-grub.iso bios
tests/qemu-smoke.sh out/probeos-x86_64-grub.iso uefi
# Optional legacy x86 qualification:
ARCH=x86 build/alpine/build-container.sh
QEMU=qemu-system-i386 tests/qemu-smoke.sh out/probeos-x86-grub.iso bios
```

These commands produce `probeos-x86_64-grub.iso`,
`probeos-x86_64-syslinux.iso`, `probeos-x86-grub.iso`, and
`probeos-x86-syslinux.iso` under `out/`. SYSLINUX configuration is maintained
at [`boot/syslinux/isolinux.cfg`](boot/syslinux/isolinux.cfg).

The BIOS smoke test needs `qemu-system-x86_64`. The UEFI test additionally
needs OVMF at `/usr/share/OVMF`, or `OVMF_CODE` and `OVMF_VARS` set to suitable
firmware files. Both tests disable guest networking and write their serial logs
under `${TMPDIR:-/tmp}` unless a log path is passed as the third argument.

The resulting root login password is `probeos`. See
[`docs/build-audit.md`](docs/build-audit.md) for the live-media architecture,
qualification evidence, and current limitations.

ProbeOS also includes the offline, open-source Memtest86+ v8.10 boot option;
see [`docs/memtest.md`](docs/memtest.md) for provenance, licensing, and
qualification details. It is distinct from the proprietary PassMark MemTest86.

## Continuous integration and releases

GitHub Actions validates source and fixtures, builds all four ISO variants with
the same containerized builder used locally, checks their layouts, and runs the
qualified Linux, offline, LAN/Web/API, and Memtest86+ QEMU smoke tests. Successful
CI runs provide a 14-day `probeos-isos-<commit SHA>` development artifact with
the ISOs, `SHA256SUMS`, and `release-manifest.json`.

Strict SemVer tags such as `v0.1.0` run the same pipeline and create a GitHub
Release only after qualification succeeds. See [docs/releasing.md](docs/releasing.md)
for the artifact matrix, hosted-runner limitations, checksum verification,
local reproduction, and release procedure.

---

## License

ProbeOS is open-source software licensed under the MIT License.

Copyright © 2026 Ploos AS

---

## Links

- Project site: https://probeos.eu
- Source code: https://github.com/ploos-as/probeos
