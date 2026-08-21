# Third-party software and source provenance

The repository MIT license covers ProbeOS-authored material only. The ISO
redistributes the components below under their upstream licenses; ProbeOS does
not relicense them and is not an official Alpine Linux or Memtest86+ project.

## Alpine system and packages

The authoritative builder uses Alpine Linux v3.19 `main` and `community` for
`x86` and `x86_64` from <https://dl-cdn.alpinelinux.org/alpine/v3.19/>. `apk`
uses Alpine's installed trusted keys when resolving and downloading packages.
The ISO contains the resolved APKs and a locally generated, signed offline APK
index; the generated public index key is included in the live overlay. ProbeOS
adds its configuration, scripts, Web service, menus, assets, and reports.

The redistributed package set is defined in `build/alpine/packages.txt` and
includes the Linux kernel, BusyBox, OpenRC, Python, X.Org, Openbox, GRUB-related
build inputs, SYSLINUX, and diagnostic utilities. Exact resolved package
versions and license metadata can be inspected in each APK (`.PKGINFO`) and in
the staged `/lib/apk/db/installed`. Alpine package/source and license records
are available through <https://pkgs.alpinelinux.org/packages?branch=v3.19> and
<https://git.alpinelinux.org/aports/>. Alpine's licensing overview is at
<https://www.alpinelinux.org/about/>.

Significant upstream projects include:

| Component | Source / license reference |
| --- | --- |
| Linux kernel | <https://kernel.org/>; GPL-2.0-only |
| BusyBox | <https://busybox.net/>; GPL-2.0-only |
| OpenRC | <https://github.com/OpenRC/openrc>; BSD-2-Clause |
| Python | <https://www.python.org/>; Python Software Foundation License |
| GNU GRUB | <https://www.gnu.org/software/grub/>; GPLv3+ |
| SYSLINUX | <https://www.syslinux.org/>; GPLv2 |

This inventory is a provenance aid, not a substitute for the license metadata
shipped by each package. Before publication, retain the release manifest and
the exact APK inventory, and make corresponding upstream source available or
provide a valid source offer where a redistributed license requires it. Legal
interpretation of a particular distribution method should be reviewed by the
publisher; this document does not make a legal-compliance warranty.

## Memtest86+

ProbeOS uses the official Memtest86+ v8.10 binary archive, verifies SHA-256
`7e6c5162cb84ab959aeb9d13c9cfd6976b0dec3b34936b73820b20c55eb26c29`, and
selects its x86_64 or i586 payload. Memtest86+ is GPLv2. Complete provenance is
in [`docs/memtest.md`](../docs/memtest.md). No PassMark MemTest86 component is
included.
