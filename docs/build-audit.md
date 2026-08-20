# Build audit (Hardware Identification v1)

Audit baseline: branch `main`, commit
`b81db74dc9b1031a0d2a9c8d7aa50b2c6dc3f895`.

The baseline tree had no Dockerfile and no checked-in SYSLINUX configuration.
Both ISO scripts generated a GRUB menu directly. Historical SYSLINUX artifacts
therefore cannot be validated or reconstructed from this checkout and were not
replaced.

Baseline defects included an undefined `ROOTDIR` in the Alpine builder, a
second invalid `PACKAGES_FILE` assignment, missing generated image assets,
duplicate OpenRC registration, absent kernel dependency, comment lines passed
to `apk` by the Ubuntu builder, and a `main`-only repository configuration for
packages that require `community`. GUI dependencies and POSIX shell syntax were
also inconsistent.

The package list was validated against the official Alpine 3.19 `main` and
`community` indexes for both x86 and x86_64. The common package list resolves
on both. `acpica`, `util-linux`, and `mesa-utils` provide `acpidump`, `lsblk`,
and `glxinfo`; those are not package names. Packages unavailable on both v3.19
targets, or unavailable on x86, are not in the common list.

The builders now resolve repository paths consistently, parse package files
safely, include the probe and its library, tolerate optional generated artwork,
initialize the target apk database, select the installed kernel for `mkinitfs`,
and retain the existing GRUB-oriented layout. They do not fabricate SYSLINUX
support.

Important remaining build limitation: the baseline scripts copy a kernel and a
normal `mkinitfs` image but do not place the installed root filesystem in the
ISO in a form the initramfs mounts. They also do not demonstrate hybrid
BIOS/UEFI boot or provide the referenced memtest payload. Thus the baseline ISO
generation is not sufficient evidence of a bootable ProbeOS live system. This
milestone does not silently replace that historical boot architecture; a
separate build-restoration change needs either the last known-good profile or a
documented boot test matrix (BIOS/UEFI and x86/x86_64).

## Validation performed

The x86_64 Alpine builder was run in a privileged Alpine 3.19 container. It
installed the resolved package set and produced a 45 MiB ISO. `xorriso`
confirmed a protective MBR and BIOS El Torito GRUB image. A bounded QEMU/SeaBIOS
test reached the GRUB menu and selected the ProbeOS kernel. It did not reach a
usable ProbeOS userspace console, consistent with the missing live-root
mechanism above. UEFI and x86 boot were not tested. Therefore this milestone
records an ISO artifact-generation success, not a boot-success claim.
