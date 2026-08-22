#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ProbeOS GUI launcher. Hardware views consume probe-identify reports.
REPORT_DIR=${PROBE_OUTPUT_DIR:-/run/probeos}
REPORT_JSON="$REPORT_DIR/report.json"
refresh_probe() { probe-identify --output-dir "$REPORT_DIR" >/tmp/probeos-gui-probe.log 2>&1 || zenity --error --title="ProbeOS hardware probe" --text="The probe could not complete. See /tmp/probeos-gui-probe.log"; }
show_file() { zenity --text-info --title="$1" --width=800 --height=600 --filename="$2"; }
show_json() { tmp=$(mktemp /tmp/probeos-gui.XXXXXX) || return; jq "$2" "$REPORT_JSON" >"$tmp" 2>&1 || echo 'Information unavailable.' >"$tmp"; show_file "$1" "$tmp"; rm -f "$tmp"; }
export_report() { profile=$1; destination=$(zenity --file-selection --directory --title="Export ProbeOS $profile report") || return; stamp=$(date +%Y%m%d-%H%M%S); cp "$REPORT_DIR/$profile.txt" "$destination/probeos-$profile-$stamp.txt" && cp "$REPORT_DIR/$profile.json" "$destination/probeos-$profile-$stamp.json" || return; [ "$profile" != sale ] || cp "$REPORT_DIR/sale.html" "$destination/probeos-sale-$stamp.html"; zenity --info --text="$profile report exported to $destination"; }
reveal_key() { zenity --question --text="Show Windows Product Key? This is sensitive; reuse and activation are not guaranteed." || return; tmp=$(mktemp /tmp/probeos-gui-key.XXXXXX) || return; probe-identify --output-dir "$REPORT_DIR" --reveal-key >"$tmp" 2>&1; show_file "Sensitive Windows Product Key" "$tmp"; rm -f "$tmp"; }
export_license() { destination=$(zenity --file-selection --save --confirm-overwrite --filename="probeos-windows-license.txt" --title="Export sensitive Windows license information") || return; probe-identify --output-dir "$REPORT_DIR" --export-key "$destination" >/dev/null 2>&1 && zenity --info --text="Sensitive export written with mode 0600."; }
benchmark_menu() {
    benchmark=$(zenity --list --title="Benchmarks (explicit opt-in)" --column="Benchmark" "CPU (30 seconds)" "Memory" "Temporary-file read") || return
    case "$benchmark" in
        "CPU (30 seconds)") zenity --question --text="Run CPU benchmark for 30 seconds?" && stress-ng --cpu 0 --timeout 30s ;;
        "Memory") zenity --question --text="Run sysbench memory benchmark?" && sysbench memory run ;;
        "Temporary-file read") zenity --question --text="Create a 256 MiB file in /tmp and read it with fio? No block device is selected." || return; file=$(mktemp /tmp/probeos-gui-fio.XXXXXX) || return; dd if=/dev/zero of="$file" bs=1M count=256 status=none && fio --name=probeos-read --rw=read --readonly --filename="$file" --direct=1 --size=256M; rm -f "$file" ;;
    esac
}
refresh_probe
while :; do
    choice=$(zenity --list --title="ProbeOS" --text="Hardware Inspection & Diagnostics" --width=480 --height=600 --column="Action" "View Sale Report" "View Detailed Report" "View Full Report" "CPU" "Memory" "Motherboard / Firmware" "PCI Devices" "USB Devices" "Graphics" "Storage" "Network" "Sensors / Power" "Windows License Summary" "Show Windows Product Key" "Export Windows License Information" "Run Benchmarks" "Refresh Probe" "Export Sale Report" "Export Detailed Report" "Export Full Report" "Open Terminal" "Reboot" "Power Off") || exit 0
    case "$choice" in
        "View Sale Report") show_file "$choice" "$REPORT_DIR/sale.txt" ;; "View Detailed Report") show_file "$choice" "$REPORT_DIR/detailed.txt" ;; "View Full Report") show_file "$choice" "$REPORT_DIR/full.txt" ;; "CPU") show_json "$choice" '.cpu' ;; "Memory") show_json "$choice" '.memory' ;;
        "Motherboard / Firmware") show_json "$choice" '{motherboard,firmware}' ;; "PCI Devices") show_json "$choice" '.pci' ;; "USB Devices") show_json "$choice" '.usb' ;;
        "Graphics") show_json "$choice" '.graphics' ;; "Storage") show_json "$choice" '.storage' ;; "Network") show_json "$choice" '.network' ;;
        "Sensors / Power") show_json "$choice" '{sensors,power}' ;; "Windows License Summary") show_json "$choice" '.windows' ;; "Show Windows Product Key") reveal_key ;; "Export Windows License Information") export_license ;; "Run Benchmarks") benchmark_menu ;; "Refresh Probe") refresh_probe ;;
        "Export Sale Report") export_report sale ;; "Export Detailed Report") export_report detailed ;; "Export Full Report") export_report full ;; "Open Terminal") rxvt & ;; "Reboot") reboot ;; "Power Off") poweroff ;;
    esac
done
