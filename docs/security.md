<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Local privilege and network security model

ProbeOS is a diskless hardware appliance, not a multi-user server. Its primary
trust boundary is physical presence at the booted machine. PID 1 starts the
local ProbeOS interface as root on tty1. The TUI's **Open Privileged Shell**
and the local GUI's **Open Privileged Terminal** explicitly identify UID 0
access and warn that changes affect the live session and attached devices.
Exiting the TUI shell returns to the interface. There is no Web/API equivalent.

The root shadow password field is locked. Password login therefore cannot be
used and no fixed, generated, displayed, logged, or persisted administrative
password exists. ProbeOS creates no human non-root account and configures no
sudo or doas policy. Traditional gettys are unnecessary and are not started.

No OpenSSH server, Dropbear, telnetd, rlogind, or rexecd is installed or
enabled. A BusyBox applet or dormant package init script would not by itself be
an enabled service; CI checks packages, OpenRC runlevels, runtime listeners,
and ISO contents. Offline mode permits the loopback-only read-only Web/API
listener on TCP 8080 and DHCP-client traffic (normally UDP 68). It expects no
externally reachable listener. Explicit trusted-LAN mode permits the same
read-only Web/API on TCP 8080 and no administrative listener. LAN opt-in does
not add API mutations, workload execution, shell execution, or authentication.

If SSH is designed later, it must be disabled by default and explicitly
enabled per session. Keys or credentials must be supplied or generated for
that boot, never shared or baked in. Remote root login requires a separate
explicit design decision, and CI must verify the resulting exposure. This
milestone does not add SSH.

This model prevents reuse or future accidental network exposure of a universal
password, detects unexpected remote-shell listeners, and makes local privilege
semantics explicit. It does not protect against a malicious person with
physical control, malicious firmware or peripherals, kernel vulnerabilities,
unknown Web flaws on a hostile LAN, compromised build infrastructure, or
malicious attached storage.
