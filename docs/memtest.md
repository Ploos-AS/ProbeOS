# Memtest86+ integration

ProbeOS ships the open-source Memtest86+ project as a standalone boot option
because memory diagnostics must run outside Linux and inspect memory that the
operating system has not reserved. This is **Memtest86+**, not PassMark
MemTest86; ProbeOS includes no PassMark binaries, branding, URLs, or license
material.

## Provenance and licensing

- Project: [memtest86plus/memtest86plus](https://github.com/memtest86plus/memtest86plus)
- Release: Memtest86+ v8.10
- Source tag commit: `494689a7acbd95db8bf41cd74830b60690c9d33d`
- Official binary archive: `https://memtest.org/download/v8.10/mt86plus_8.10.binaries.zip`
- Archive SHA-256:
  `7e6c5162cb84ab959aeb9d13c9cfd6976b0dec3b34936b73820b20c55eb26c29`
- License: GNU General Public License version 2 (GPLv2), as provided by the
  upstream repository.

The containerized builder downloads that exact official archive, verifies the
SHA-256 before extraction, and copies only the architecture-specific member to
`/boot/memtest/mt86plus`. The archive contains:

| ProbeOS architecture | Upstream member | Boot support |
| --- | --- | --- |
| x86_64 | `mt86p_810_x86_64` | 64-bit legacy BIOS, 64-bit UEFI, and GRUB Linux handover |
| x86 | `mt86p_810_i586` | 32-bit legacy BIOS, 32-bit UEFI, and GRUB Linux handover |

The upstream x86_64 source build was independently checked. The upstream i586
source build currently fails with Alpine 3.19 GCC at an xHCI structure
alignment diagnostic; ProbeOS therefore uses the corresponding official
upstream release member rather than maintaining an unreviewed source patch.

## Boot mechanism

The GRUB entry is `ProbeOS - Memory Test (Memtest86+)`. It invokes the upstream
`mt86plus` image directly with GRUB's `linux` handover command; no Linux kernel,
initramfs, APK installation, or network is involved. The normal ProbeOS text
entry remains the default (`set default=1`), so Memtest only runs when selected.

The payload is present on the ISO at `/boot/memtest/mt86plus`. The same explicit
path is suitable for a future SYSLINUX entry; the expected legacy configuration
is a `LINUX /boot/memtest/mt86plus` (or equivalent `KERNEL`) entry with no
initrd.

## Qualification

Memtest smoke tests boot a temporary ISO with GRUB's default set to the
Memtest entry, run QEMU with `-nic none`, and require serial output containing
`Memtest86+ v8.10`. They stop after startup; a complete RAM pass is not needed.

| Firmware / loader | Payload | Result |
| --- | --- | --- |
| x86_64 SeaBIOS + GRUB | `mt86p_810_x86_64` | PASS: active v8.10 test screen |
| x86_64 OVMF + GRUB | `mt86p_810_x86_64` | PASS: active v8.10 test screen |
| x86 SeaBIOS + GRUB | `mt86p_810_i586` | PASS: active v8.10 x32 test screen |
| x86 IA32 UEFI | `mt86p_810_i586` | Upstream-supported; not qualified because no IA32 OVMF firmware is installed |

IA32 UEFI is not presented as a separate menu option: the architecture's
single GRUB entry selects the i586 payload, and actual firmware support remains
dependent on the target machine. Secure Boot is outside this milestone.

To reproduce the dedicated tests, build a temporary Memtest-default ISO and
then restore a normal-default build before publishing artifacts:

```sh
GRUB_DEFAULT=2 build/alpine/build-container.sh
tests/memtest-smoke.sh out/probeos-x86_64-grub.iso bios
tests/memtest-smoke.sh out/probeos-x86_64-grub.iso uefi
ARCH=x86 GRUB_DEFAULT=2 build/alpine/build-container.sh
QEMU=qemu-system-i386 tests/memtest-smoke.sh out/probeos-x86-grub.iso bios
```

The final distributed x86_64 and x86 ISOs are built again without
`GRUB_DEFAULT`, preserving normal ProbeOS as the default boot entry.
