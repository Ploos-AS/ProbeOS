# ProbeOS Boot Menu Design

This document describes the boot menu structure and available boot modes for
ProbeOS.

> GRUB provides the modern BIOS/UEFI menu. SYSLINUX provides a focused legacy
> BIOS menu from `boot/syslinux/isolinux.cfg`. See
> [build-audit.md](build-audit.md) and [memtest.md](memtest.md) for verified
> status.

The boot menu is the primary user entry point and must remain simple, explicit,
and predictable.

---

## 1. Bootloader

ProbeOS uses GRUB2 as its primary modern bootloader and ISOLINUX/SYSLINUX for
legacy BIOS compatibility. GRUB owns UEFI support; the SYSLINUX artifact is
intentionally BIOS-only.

Goals:
- BIOS and UEFI compatibility
- Clear, minimal menu structure
- Support for standalone tools (e.g. memory test)
- Easy branding and customization

---

## 2. Current generated menus

GRUB contains ProbeOS GUI, ProbeOS Text / Curses, and the explicit Memtest86+
entry. SYSLINUX contains Hardware Identification, Serial Console, Verbose /
Debug, and the explicit Memtest86+ entry.

The normal generated ISO defaults to **Start ProbeOS (Text / Curses)** so that
serial and headless qualification has a stable console. Memtest is never the
default.

The SYSLINUX menu exposes Hardware Identification, Serial Console, Verbose /
Debug, and Memory Test entries. Hardware Identification is its normal default.
Reboot and power-off entries are omitted because this milestone does not
qualify the associated COM32 behavior on legacy machines.

---

## 3. Boot Modes

### 3.1 Start ProbeOS (GUI)

- Boots into a minimal graphical environment
- Launches the ProbeOS GUI automatically
- Intended for interactive hardware inspection and benchmarking

Characteristics:
- Quiet boot
- Automatic login
- X11 started via startx
- Lightweight window manager

---

### 3.2 Start ProbeOS (Text / Curses)

- Boots into a text-only environment
- Automatically launches a menu-driven TUI
- Suitable for serial consoles, headless systems, or minimal environments

---

### 3.3 Local diagnostics and benchmarks

The local GUI/TUI exposes the currently packaged information and benchmark
tools. They are not separate boot-menu entries and cannot be started by the
Web/API service.

---

### 3.4 Memory Test (Memtest86+)

- Boots Memtest86+ as a standalone environment
- No operating system is loaded

---

### 3.5 Verbose / Debug

The SYSLINUX image has one clearly labelled verbose/debug entry. GRUB does not
currently provide a separate debug submenu.

---

## 4. Safety Defaults

- Disk writes avoided by default
- Destructive tools require explicit user action
- Potentially dangerous options are clearly labeled

---

## 5. Branding

Branding is minimal and informational only.

Footer example:

ProbeOS — https://probeos.eu
© 2026 Ploos AS

---

## 6. Future Extensions

- Network / PXE boot
- Automated verification profiles
- Architecture-specific entries

These are out of scope for initial releases.
