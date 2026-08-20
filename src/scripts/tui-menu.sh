#!/bin/sh
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
    cp "$REPORT_TEXT" "$destination/probeos-report-$stamp.txt" && cp "$REPORT_JSON" "$destination/probeos-report-$stamp.json" && $DIALOG --msgbox "Reports exported to:\n$destination" 7 70
}
windows_info() {
    show_json "Windows / OEM License" '.windows | "Firmware OEM key: \(if .firmware_license.oem_key_found then "Found" else "Not found" end)\nMSDM present: \(.firmware_license.msdm_present)\nSource: \(.firmware_license.source // "None")\nMasked key: \(.firmware_license.key_masked // "Not available")\n\nInstallations:\n" + ((.installations // []) | if length==0 then "None discovered" else map("\(.product_name // "Unknown Windows") — \(.device)\n  Version/build: \(.version // "Unknown") / \(.build // "Unknown")\n  Product ID: \(.product_id // "Unknown")\n  Channel: \(.license_channel // "Unknown")\n  Activation: \(.activation_status)") | join("\n")) end)'
    $DIALOG --yesno "Reveal the complete firmware OEM key on screen? This is sensitive information." 8 70 || return
    tmp=$(mktemp /tmp/probeos-key.XXXXXX) || return
    probe-identify --output-dir "$REPORT_DIR" --no-windows-mount --reveal-key >"$tmp" 2>&1
    show_text "Sensitive OEM key" "$tmp"
    rm -f "$tmp"
}

refresh_probe
while :; do
    choice=$($DIALOG --stdout --clear --backtitle "$FOOTER" --title "ProbeOS" --menu "Hardware Inspection & Diagnostics" 24 76 16 \
        1 "System Summary" 2 "CPU" 3 "Memory" 4 "Motherboard / Firmware" 5 "PCI Devices" 6 "USB Devices" 7 "Graphics" 8 "Storage" 9 "Network" 10 "Sensors / Power" 11 "Windows / OEM License" 12 "Benchmarks" 13 "Export Report" 14 "Shell" 15 "Reboot" 16 "Power Off") || exit 0
    case "$choice" in
        1) ensure_report && show_text "System Summary" "$REPORT_TEXT" ;;
        2) show_json "CPU" '.cpu' ;; 3) show_json "Memory" '.memory' ;;
        4) show_json "Motherboard / Firmware" '{motherboard,firmware,system:{chassis:.system.chassis}}' ;;
        5) show_json "PCI Devices" '.pci' ;; 6) show_json "USB Devices" '.usb' ;; 7) show_json "Graphics" '.graphics' ;;
        8) show_json "Storage" '.storage' ;; 9) show_json "Network" '.network' ;; 10) show_json "Sensors / Power" '{sensors,power}' ;;
        11) windows_info ;; 12) benchmark_menu ;; 13) export_report ;;
        14) clear; echo "Type 'exit' to return to ProbeOS."; /bin/sh ;; 15) reboot ;; 16) poweroff ;;
    esac
done
