#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ProbeOS TUI - presentation layer for probe-identify
DIALOG=${DIALOG:-dialog}
REPORT_DIR=${PROBE_OUTPUT_DIR:-/run/probeos}
REPORT_JSON="$REPORT_DIR/report.json"
REPORT_TEXT="$REPORT_DIR/report.txt"
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
benchmark_menu() {
    choice=$($DIALOG --stdout --backtitle "$FOOTER" --title "Benchmarks (explicit opt-in)" --menu "No benchmark starts automatically" 16 70 5 1 "CPU benchmark (30 seconds)" 2 "Memory benchmark" 3 "Temporary-file read benchmark" 4 "Back") || return
    case "$choice" in
        1) $DIALOG --yesno "Run a 30-second CPU stress benchmark?" 7 60 && stress-ng --cpu 0 --timeout 30s ;;
        2) $DIALOG --yesno "Run the sysbench memory benchmark?" 7 60 && sysbench memory run ;;
        3) run_disk_bench ;;
    esac
}
run_disk_bench() {
    $DIALOG --yesno "This creates a 256 MiB regular file in /tmp, reads it with fio, then removes it. No physical device is selected. Continue?" 9 72 || return
    file=$(mktemp /tmp/probeos-fio.XXXXXX) || return
    trap 'rm -f "$file"' HUP INT TERM EXIT
    dd if=/dev/zero of="$file" bs=1M count=256 status=none || { rm -f "$file"; trap - HUP INT TERM EXIT; return; }
    fio --name=probeos-read --rw=read --readonly --filename="$file" --direct=1 --size=256M
    rm -f "$file"
    trap - HUP INT TERM EXIT
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
        1 "Sale Report" 2 "CPU" 3 "Memory" 4 "Motherboard / Firmware" 5 "PCI Devices" 6 "USB Devices" 7 "Graphics" 8 "Storage" 9 "Network" 10 "Network / Web UI" 11 "Sensors / Power" 12 "Windows Licensing" 13 "Benchmarks" 14 "Reports / Export" 15 "Shell" 16 "Reboot" 17 "Power Off") || exit 0
    case "$choice" in
        1) ensure_report && show_text "System Summary" "$REPORT_TEXT" ;;
        2) show_json "CPU" '.cpu' ;; 3) show_json "Memory" '.memory' ;;
        4) show_json "Motherboard / Firmware" '{motherboard,firmware,system:{chassis:.system.chassis}}' ;;
        5) show_json "PCI Devices" '.pci' ;; 6) show_json "USB Devices" '.usb' ;; 7) show_json "Graphics" '.graphics' ;;
        8) show_json "Storage" '.storage' ;; 9) show_json "Network" '.network' ;; 10) network_menu ;; 11) show_json "Sensors / Power" '{sensors,power}' ;;
        12) windows_menu ;; 13) benchmark_menu ;; 14) reports_menu ;;
        15) clear; echo "Type 'exit' to return to ProbeOS."; /bin/sh ;; 16) reboot ;; 17) poweroff ;;
    esac
done
