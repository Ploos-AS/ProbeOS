#!/bin/sh

# ProbeOS Text User Interface
# https://probeos.eu
# © 2026 Ploos AS

DIALOG=dialog
TITLE="ProbeOS"
SUBTITLE="Hardware Inspection & Diagnostics"
FOOTER="https://probeos.eu  © 2026 Ploos AS"

export NCURSES_NO_UTF8_ACS=1

main_menu() {
    $DIALOG \
        --clear \
        --backtitle "$FOOTER" \
        --title "$TITLE" \
        --menu "$SUBTITLE" 15 60 8 \
        1 "System Summary" \
        2 "CPU Information" \
        3 "Memory Information" \
        4 "Storage Devices" \
        5 "Sensors & Thermals" \
        6 "Run Benchmarks" \
        7 "Export Report" \
        8 "Drop to Shell" \
        9 "Reboot" \
        10 "Power Off" \
        2> /tmp/probeos_choice

    choice=$(cat /tmp/probeos_choice)
    rm -f /tmp/probeos_choice

    case "$choice" in
        1) system_summary ;;
        2) cpu_info ;;
        3) mem_info ;;
        4) storage_info ;;
        5) sensor_info ;;
        6) benchmark_menu ;;
        7) export_report ;;
        8) drop_shell ;;
        9) reboot ;;
        10) poweroff ;;
        *) exit 0 ;;
    esac
}

system_summary() {
    {
        echo "Hostname: $(hostname)"
        echo
        uname -a
        echo
        inxi -Fxz
    } | $DIALOG --textbox - 30 100
}

cpu_info() {
    {
        lscpu
    } | $DIALOG --textbox - 30 100
}

mem_info() {
    {
        free -h
        echo
        cat /proc/meminfo
    } | $DIALOG --textbox - 30 100
}

storage_info() {
    {
        lsblk
        echo
        blkid
    } | $DIALOG --textbox - 30 100
}

sensor_info() {
    {
        sensors 2>/dev/null || echo "No sensors detected."
    } | $DIALOG --textbox - 30 100
}

benchmark_menu() {
    $DIALOG \
        --clear \
        --backtitle "$FOOTER" \
        --title "Benchmarks" \
        --menu "Select benchmark" 15 60 5 \
        1 "CPU Stress Test" \
        2 "Memory Bandwidth Test" \
        3 "Disk Benchmark" \
        4 "Back" \
        2> /tmp/probeos_bench

    choice=$(cat /tmp/probeos_bench)
    rm -f /tmp/probeos_bench

    case "$choice" in
        1) run_cpu_bench ;;
        2) run_mem_bench ;;
        3) run_disk_bench ;;
        *) return ;;
    esac
}

run_cpu_bench() {
    $DIALOG --infobox "Running CPU stress test...\nPress Ctrl+C to abort." 6 50
    stress-ng --cpu 0 --timeout 30s
}

run_mem_bench() {
    $DIALOG --infobox "Running memory bandwidth test..." 5 50
    mbw 128
}

run_disk_bench() {
    $DIALOG --msgbox "Disk benchmark is read-only and may take time." 6 50
    fio --name=readtest --rw=read --size=256M --filename=/tmp/fio.test --direct=1
    rm -f /tmp/fio.test
}

export_report() {
    OUT="/tmp/probeos-report.txt"
    {
        echo "ProbeOS Report"
        echo "https://probeos.eu"
        echo "© 2026 Ploos AS"
        echo
        date
        echo
        inxi -Fxz
        echo
        lscpu
        echo
        free -h
        echo
        lsblk
    } > "$OUT"

    $DIALOG --msgbox "Report written to:\n$OUT" 7 50
}

drop_shell() {
    clear
    echo "Dropping to shell. Type 'exit' to return."
    /bin/sh
}

# Main loop
while true; do
    main_menu
done
