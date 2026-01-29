# ProbeOS — Design Overview

## 1. Purpose

ProbeOS is a lightweight, bootable Linux-based operating system designed for
hardware inspection, diagnostics, compatibility testing, and performance
benchmarking.

It is intended to be run directly from removable media (USB or CD/DVD) without
installation and without modifying local storage unless explicitly requested
by the user.

---

## 2. Design Principles

ProbeOS is guided by the following principles:

- **Hardware-first**  
  The primary focus is discovering, verifying, and testing system hardware.

- **Minimal and fast**  
  The system should boot quickly and remain small in size.

- **Trustworthy by default**  
  Read-only operations are preferred. Potentially destructive tools must be
  clearly labeled and opt-in.

- **Fully redistributable**  
  All included components must be open-source and legally redistributable.

- **Multiple interfaces**  
  ProbeOS must function in both graphical (GUI) and text-based (TUI) modes.

- **Predictable behavior**  
  Tools should behave consistently across hardware and platforms.

---

## 3. Target Use Cases

- Hardware diagnostics and troubleshooting
- System verification for resale or refurbishment
- Compatibility and firmware inspection
- Performance benchmarking
- Technical audits and reporting
- Education and demonstration

---

## 4. Base System

ProbeOS is based on a minimal Linux distribution (initially Alpine Linux) to
ensure a small footprint and fast boot times.

Key characteristics:
- BusyBox-based userland
- Minimal init system
- No persistent state by default
- BIOS and UEFI boot support

---

## 5. Boot Modes

ProbeOS provides multiple boot modes via the bootloader menu:

- **ProbeOS (GUI)**  
  Boots into a minimal graphical environment for hardware inspection and
  benchmarking.

- **ProbeOS (Text / Curses)**  
  Boots into a text-only environment with a menu-driven interface.

- **Memory Test**  
  Standalone memory testing (e.g. Memtest86+).

- **Hardware Stress and Test Tools**  
  Optional entries for focused diagnostics.

- **Advanced / Debug**  
  Low-level boot options and debugging tools.

---

## 6. User Interfaces

### 6.1 Graphical Interface (GUI)

- Minimal X11 environment
- Lightweight window manager (e.g. Openbox)
- Hardware information tools and benchmarks
- Optional visual demos (e.g. GPU tests, fractals)

### 6.2 Text Interface (TUI)

- Curses-based menus (e.g. `dialog`)
- Keyboard-only navigation
- Suitable for serial consoles and headless systems

---

## 7. Tooling Strategy

### 7.1 Computation and Benchmarks

- Core diagnostics and benchmarks are implemented as compiled C binaries
- Emphasis on small, fast, and predictable tools
- No reliance on large runtime environments

### 7.2 Orchestration

- Shell scripts are used to orchestrate tools, present menus, and aggregate
  reports
- Scripts are kept simple and auditable

---

## 8. Hardware Coverage

ProbeOS aims to provide insight into:

- CPU topology, features, and performance
- Memory configuration and bandwidth
- Storage devices and health (SMART, NVMe)
- GPU capabilities and rendering
- Firmware (BIOS/UEFI, ACPI)
- Sensors and thermals
- Network interfaces

---

## 9. Reporting

ProbeOS supports exporting inspection and benchmark results:

- Plain text summaries
- Optional HTML reports
- Timestamped output directories
- Non-persistent by default unless saved by the user

All reports include basic provenance information (ProbeOS version, timestamp).

---

## 10. Safety and Scope

ProbeOS is not intended to be:
- A general-purpose desktop environment
- An installer or partition editor
- A recovery OS for data repair

Destructive operations are excluded by default and may only be included as
explicit, clearly labeled options.

---

## 11. Branding and Attribution

ProbeOS is developed and maintained by **Ploos AS**.

Branding is intentionally minimal and non-intrusive. Attribution may appear in:
- Boot splash screens
- About dialogs
- Generated reports
- Documentation

---

## 12. Future Considerations

Potential future enhancements include:
- Additional benchmark suites
- Extended firmware testing
- PXE/network boot support
- Automated verification profiles
- Support for additional architectures

These are considered out of scope for initial releases.
