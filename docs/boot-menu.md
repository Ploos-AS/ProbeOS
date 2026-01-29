# ProbeOS Boot Menu Design

This document describes the boot menu structure and available boot modes for
ProbeOS.

The boot menu is the primary user entry point and must remain simple, explicit,
and predictable.

---

## 1. Bootloader

ProbeOS uses GRUB2 as the primary bootloader.

Goals:
- BIOS and UEFI compatibility
- Clear, minimal menu structure
- Support for standalone tools (e.g. memory test)
- Easy branding and customization

---

## 2. Top-Level Boot Menu

ProbeOS
- Start ProbeOS (GUI)
- Start ProbeOS (Text / Curses)
- Hardware Stress & Benchmarks
- Disk & Storage Tools
- Memory Test (Memtest86+)
- Firmware / Low-Level Tools
- Advanced / Debug

The default selection is **Start ProbeOS (GUI)**.

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

### 3.3 Hardware Stress & Benchmarks

Submenu:

- CPU Stress Test
- Memory Stress Test
- GPU Test
- Run All Benchmarks

These entries boot into ProbeOS with predefined modes or flags that automatically
launch the corresponding tools.

---

### 3.4 Disk & Storage Tools

Submenu (read-only by default):

- SMART Status
- NVMe Information
- Disk Performance Test

---

### 3.5 Memory Test (Memtest86+)

- Boots Memtest86+ as a standalone environment
- No operating system is loaded

---

### 3.6 Firmware / Low-Level Tools

Submenu:

- ACPI / BIOS Tests
- EFI Information
- DMI / SMBIOS Viewer

---

### 3.7 Advanced / Debug

- Drop to Shell
- Disable KMS
- Disable ACPI
- Verbose Boot
- Recovery Shell

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
