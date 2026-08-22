#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ProbeOS TUI - presentation layer for probe-identify
DIALOG=${DIALOG:-dialog}
REPORT_DIR=${PROBE_OUTPUT_DIR:-/run/probeos}
REPORT_JSON="$REPORT_DIR/report.json"
REPORT_TEXT="$REPORT_DIR/report.txt"
DIAGNOSTICS_TEXT="$REPORT_DIR/diagnostics.txt"
FOOTER="ProbeOS — https://probeos.eu — © 2026 Ploos AS"
export NCURSES_NO_UTF8_ACS=1

refresh_probe() {
    mkdir -p "$REPORT_DIR" 2>/dev/null || true
    probe-identify --output-dir "$REPORT_DIR" >/tmp/probeos-probe.log 2>&1 || {
        $DIALOG --title "Hardware probe" --textbox /tmp/probeos-probe.log 12 80
        return 1
    }
}
ensure_report() { [ -s "$REPORT_JSON" ] || refresh_probe; }
show_text() { $DIALOG --backtitle "$FOOTER" --title "$1" --textbox "$2" 32 105; }
show_json() {
    ensure_report || return
    tmp=$(mktemp /tmp/probeos-view.XXXXXX) || return
    jq -r "$2" "$REPORT_JSON" >"$tmp" 2>&1 || echo 'Information unavailable.' >"$tmp"
    show_text "$1" "$tmp"
    rm -f "$tmp"
}
run_diagnostic() {
    tmp=$(mktemp /tmp/probeos-diagnostic.XXXXXX) || return
    if probe-diagnostics "$@" --output-dir "$REPORT_DIR" >"$tmp" 2>&1; then :; fi
    show_text "Diagnostic Results" "$tmp"
    rm -f "$tmp"
}
export_diagnostics() {
    [ -s "$REPORT_DIR/diagnostics.json" ] || { $DIALOG --msgbox "Diagnostics have not been run." 6 55; return; }
    destination=$($DIALOG --stdout --inputbox "Directory for diagnostic result copies:" 9 70 "/tmp") || return
    [ -d "$destination" ] || { $DIALOG --msgbox "Directory does not exist." 6 50; return; }
    stamp=$(date +%Y%m%d-%H%M%S)
    for extension in txt json html; do cp "$REPORT_DIR/diagnostics.$extension" "$destination/probeos-diagnostics-$stamp.$extension" || return; done
    $DIALOG --msgbox "Diagnostic results exported to:\n$destination" 7 70
}
diagnostics_menu() {
    choice=$($DIALOG --stdout --backtitle "$FOOTER" --title "Diagnostics" --menu "Quick Check is passive, offline, and non-destructive" 23 82 9 \
        1 "Quick Check" 2 "CPU Diagnostic" 3 "Userspace Memory Test" 4 "Storage Health" 5 "Storage Read Test" 6 "Network Diagnostic" 7 "View Results" 8 "Export Results" 9 "Memtest86+ information") || return
    case "$choice" in
        1) run_diagnostic quick ;;
        2) $DIALOG --yesno "Runs a CPU workload for 60 seconds and stops it on cancellation." 7 72 && run_diagnostic cpu --duration 60 ;;
        3) $DIALOG --yesno "Tests a conservative amount of currently available RAM. ProbeOS keeps a memory reserve. This is not boot-time Memtest86+." 9 76 && run_diagnostic memory ;;
        4) run_diagnostic storage-health ;;
        5) device=$($DIALOG --stdout --inputbox "Device to read (example /dev/nvme0n1):" 8 70) || return; $DIALOG --yesno "Reads 4 GiB from $device. No data will be written." 7 72 && run_diagnostic storage-read --device "$device" --read-mib 4096 ;;
        6) run_diagnostic network ;;
        7) if [ -s "$DIAGNOSTICS_TEXT" ]; then show_text "Diagnostic Results" "$DIAGNOSTICS_TEXT"; else $DIALOG --msgbox "Diagnostics have not been run." 6 55; fi ;;
        8) export_diagnostics ;;
        9) $DIALOG --msgbox "For deeper full-memory testing, reboot and choose ProbeOS - Memory Test (Memtest86+) from the boot menu. The userspace memory test is not equivalent to Memtest86+." 9 76 ;;
    esac
}
benchmark_menu() {
    choice=$($DIALOG --stdout --backtitle "$FOOTER" --title "Benchmarks" --menu "Explicit opt-in; measurements are not health ratings" 22 78 8 1 "Quick Benchmark" 2 "CPU Benchmark" 3 "Memory Benchmark" 4 "Storage Read Benchmark" 5 "Network Benchmark" 6 "Full Benchmark" 7 "View Results" 8 "Export Results") || return
    case "$choice" in
        1) run_benchmark quick ;;
        2) run_benchmark cpu ;;
        3) run_benchmark memory ;;
        4) device=$($DIALOG --stdout --inputbox "Device to READ (example /dev/nvme0n1):" 8 72) || return; run_benchmark storage --device "$device" ;;
        5) peer=$($DIALOG --stdout --inputbox "Explicit LAN iperf3 server address:" 8 72) || return; run_benchmark network --peer "$peer" ;;
        6) run_benchmark full ;;
        7) if [ -s "$REPORT_DIR/benchmarks.txt" ]; then show_text "Benchmark Results" "$REPORT_DIR/benchmarks.txt"; else $DIALOG --msgbox "Benchmarks have not been run." 6 55; fi ;;
        8) export_result benchmarks ;;
    esac
}
run_benchmark() {
    profile=$1; shift
    $DIALOG --yesno "Run $profile benchmark now? Workloads are bounded and cancellable; storage is read-only." 8 72 || return
    tmp=$(mktemp /tmp/probeos-benchmark.XXXXXX) || return
    probe-benchmark run "$profile" "$@" --output-dir "$REPORT_DIR" >"$tmp" 2>&1 || true
    show_text "Benchmark Results" "$tmp"; rm -f "$tmp"
}
export_result() {
    kind=$1; [ -s "$REPORT_DIR/$kind.json" ] || { $DIALOG --msgbox "Results have not been run." 6 55; return; }
    destination=$($DIALOG --stdout --inputbox "Directory for result copies:" 9 70 "/tmp") || return
    stamp=$(date +%Y%m%d-%H%M%S); for extension in txt json html; do cp "$REPORT_DIR/$kind.$extension" "$destination/probeos-$kind-$stamp.$extension" || return; done
}
stability_menu() {
    choice=$($DIALOG --stdout --title "Stability / Burn-in" --menu "CPU + bounded memory; no storage writes" 18 78 5 1 "15-minute Stability Test" 2 "60-minute Burn-in Test" 3 "Custom Duration" 4 "View Results" 5 "Export Results") || return
    case "$choice" in 1) seconds=900;; 2) seconds=3600;; 3) minutes=$($DIALOG --stdout --inputbox "Duration in minutes (1-1440):" 8 60 "15") || return; seconds=$((minutes * 60));; 4) [ -s "$REPORT_DIR/stability.txt" ] && show_text "Stability Results" "$REPORT_DIR/stability.txt"; return;; 5) export_result stability; return;; esac
    $DIALOG --yesno "ProbeOS Stability Test\n\nDuration: $((seconds / 60)) minutes\nCPU load: high\nMemory load: bounded\nStorage writes: none\n\nTemperatures will be monitored where supported. Start?" 14 72 || return
    tmp=$(mktemp /tmp/probeos-stability.XXXXXX) || return; probe-benchmark stability --duration "$seconds" --output-dir "$REPORT_DIR" >"$tmp" 2>&1 || true; show_text "Stability Results" "$tmp"; rm -f "$tmp"
}
export_report() {
    ensure_report || return
    destination=$($DIALOG --stdout --inputbox "Directory for report copies:" 9 70 "/tmp") || return
    [ -d "$destination" ] || { $DIALOG --msgbox "Directory does not exist." 6 50; return; }
    stamp=$(date +%Y%m%d-%H%M%S)
    profile=${1:-sale}
    cp "$REPORT_DIR/$profile.txt" "$destination/probeos-$profile-$stamp.txt" && cp "$REPORT_DIR/$profile.json" "$destination/probeos-$profile-$stamp.json" || return
    [ "$profile" = sale ] && cp "$REPORT_DIR/sale.html" "$destination/probeos-sale-$stamp.html"
    $DIALOG --msgbox "$profile report exported to:\n$destination" 7 70
}
reports_menu() {
    choice=$($DIALOG --stdout --backtitle "$FOOTER" --title "Reports" --menu "Sale is concise and privacy-safe" 20 76 7 1 "View Sale Report" 2 "View Detailed Report" 3 "View Full Report" 4 "Export Sale Report (TXT/JSON/HTML)" 5 "Export Detailed Report" 6 "Export Full Report" 7 "Back") || return
    case "$choice" in 1) show_text "Sale Report" "$REPORT_DIR/sale.txt" ;; 2) show_text "Detailed Report" "$REPORT_DIR/detailed.txt" ;; 3) show_text "Full Report" "$REPORT_DIR/full.txt" ;; 4) export_report sale ;; 5) export_report detailed ;; 6) export_report full ;; esac
}
network_status() {
    tmp=$(mktemp /tmp/probeos-network.XXXXXX) || return
    probeos-network status >"$tmp" 2>&1 || true
    show_text "Network Status" "$tmp"
    rm -f "$tmp"
}
network_interfaces() { probeos-network interfaces 2>/dev/null | paste -sd' ' -; }
configure_dhcp() {
    interfaces=$(network_interfaces)
    [ -n "$interfaces" ] || { $DIALOG --msgbox "No wired Ethernet interface found." 6 60; return; }
    iface=$($DIALOG --stdout --inputbox "Wired interface (available: $interfaces):" 9 70 "${interfaces%% *}") || return
    tmp=$(mktemp /tmp/probeos-dhcp.XXXXXX) || return
    if probeos-network dhcp "$iface" >"$tmp" 2>&1; then
        $DIALOG --msgbox "DHCP configured on $iface." 7 60
    else
        show_text "DHCP result" "$tmp"
    fi
    rm -f "$tmp"
}
configure_static() {
    interfaces=$(network_interfaces)
    [ -n "$interfaces" ] || { $DIALOG --msgbox "No wired Ethernet interface found." 6 60; return; }
    iface=$($DIALOG --stdout --inputbox "Wired interface (available: $interfaces):" 9 70 "${interfaces%% *}") || return
    address=$($DIALOG --stdout --inputbox "IPv4 address/prefix (example 192.168.1.20/24):" 9 70) || return
    gateway=$($DIALOG --stdout --inputbox "Gateway (optional):" 9 70) || return
    probeos-network static "$iface" "$address" "$gateway" && $DIALOG --msgbox "Static IPv4 configured on $iface." 7 60
}
web_config_file=/etc/conf.d/probeos-web
web_set_bind() {
    bind=$1
    [ -f "$web_config_file" ] || return 1
    sed -i "s|^PROBEOS_WEB_BIND=.*|PROBEOS_WEB_BIND=\"$bind\"|" "$web_config_file"
    rc-service probeos-web restart >/dev/null 2>&1 || rc-service probeos-web start >/dev/null 2>&1
}
web_menu() {
    choice=$($DIALOG --stdout --backtitle "$FOOTER" --title "ProbeOS Web UI" --menu "Read-only report interface on port 8080" 18 76 5 \
        1 "Start Local Web UI (127.0.0.1)" 2 "Enable LAN Web UI (all IPv4)" 3 "Stop Web UI" 4 "Show Web UI Address" 5 "Back") || return
    case "$choice" in
        1) web_set_bind 127.0.0.1; $DIALOG --msgbox "Local Web UI: http://127.0.0.1:8080/" 7 65 ;;
        2) web_set_bind 0.0.0.0; $DIALOG --msgbox "LAN Web UI enabled for trusted local networks.\nUse Network Status to find the IPv4 address." 8 70 ;;
        3) rc-service probeos-web stop; $DIALOG --msgbox "Web UI stopped." 6 50 ;;
        4) tmp=$(mktemp /tmp/probeos-web-address.XXXXXX) || return; probeos-network status >"$tmp" 2>&1 || true; printf '\nWeb UI port: 8080\n' >>"$tmp"; show_text "Web UI Address" "$tmp"; rm -f "$tmp" ;;
    esac
}
network_menu() {
    choice=$($DIALOG --stdout --backtitle "$FOOTER" --title "Network / Web UI" --menu "DHCP is runtime-only and failure is non-fatal" 20 78 6 \
        1 "Show Network Status" 2 "Configure DHCP" 3 "Configure Static IPv4" 4 "Web UI Controls" 5 "Back") || return
    case "$choice" in 1) network_status ;; 2) configure_dhcp ;; 3) configure_static ;; 4) web_menu ;; esac
}
windows_info() {
    show_json "Windows / OEM License" '.windows | "Firmware OEM key: \(if .firmware_license.oem_key_found then "Found" else "Not found" end)\nMSDM present: \(.firmware_license.msdm_present)\nSource: \(.firmware_license.source // "None")\nMasked key: \(.firmware_license.key_masked // "Not available")\n\nInstallations:\n" + ((.installations // []) | if length==0 then "None discovered" else map("\(.product_name // "Unknown Windows") — \(.device)\n  Version/build: \(.version // "Unknown") / \(.build // "Unknown")\n  Product ID: \(.product_id // "Unknown")\n  Channel: \(.license_channel // "Unknown")\n  Activation: \(.activation_status)") | join("\n")) end)'
}
reveal_windows_key() {
    $DIALOG --yesno "Show Windows Product Key? Anyone nearby may see sensitive information. Reuse and activation are not guaranteed." 9 74 || return
    tmp=$(mktemp /tmp/probeos-key.XXXXXX) || return
    probe-identify --output-dir "$REPORT_DIR" --reveal-key >"$tmp" 2>&1
    show_text "Sensitive Windows Product Key" "$tmp"
    rm -f "$tmp"
}
export_windows_license() {
    destination=$($DIALOG --stdout --fselect "/tmp/probeos-windows-license.txt" 12 76) || return
    probe-identify --output-dir "$REPORT_DIR" --export-key "$destination" >/dev/null 2>&1 && $DIALOG --msgbox "Sensitive license information exported with mode 0600." 7 70
}
windows_menu() {
    choice=$($DIALOG --stdout --backtitle "$FOOTER" --title "Windows Licensing" --menu "Keys are excluded from normal reports, Web UI, and API" 17 76 4 1 "View License Summary" 2 "Show Windows Product Key" 3 "Export Windows License Information" 4 "Back") || return
    case "$choice" in 1) windows_info ;; 2) reveal_windows_key ;; 3) export_windows_license ;; esac
}

refresh_probe
while :; do
    choice=$($DIALOG --stdout --clear --backtitle "$FOOTER" --title "ProbeOS" --menu "Hardware Inspection & Diagnostics" 26 84 19 \
        1 "Sale Report" 2 "CPU" 3 "Memory" 4 "Motherboard / Firmware" 5 "PCI Devices" 6 "USB Devices" 7 "Graphics" 8 "Storage" 9 "Network" 10 "Network / Web UI" 11 "Sensors / Power" 12 "Windows Licensing" 13 "Diagnostics" 14 "Benchmarks" 15 "Stability / Burn-in" 16 "Reports / Export" 17 "Shell" 18 "Reboot" 19 "Power Off") || exit 0
    case "$choice" in
        1) ensure_report && show_text "System Summary" "$REPORT_TEXT" ;;
        2) show_json "CPU" '.cpu' ;; 3) show_json "Memory" '.memory' ;;
        4) show_json "Motherboard / Firmware" '{motherboard,firmware,system:{chassis:.system.chassis}}' ;;
        5) show_json "PCI Devices" '.pci' ;; 6) show_json "USB Devices" '.usb' ;; 7) show_json "Graphics" '.graphics' ;;
        8) show_json "Storage" '.storage' ;; 9) show_json "Network" '.network' ;; 10) network_menu ;; 11) show_json "Sensors / Power" '{sensors,power}' ;;
        12) windows_menu ;; 13) diagnostics_menu ;; 14) benchmark_menu ;; 15) stability_menu ;; 16) reports_menu ;;
        17) clear; echo "Type 'exit' to return to ProbeOS."; /bin/sh ;; 18) reboot ;; 19) poweroff ;;
    esac
done
