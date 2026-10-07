#!/bin/bash
# Self-healing watchdog for Intel AX201 CNVi Wi-Fi
# Rate-limited to max 3 recovery attempts per 5 minutes

LOCKFILE="/tmp/wifi-autoheal-state"
NOW=$(date +%s)

# Ensure PCIe runtime power control is always ON
if [ -f "/sys/bus/pci/devices/0000:00:14.3/power/control" ]; then
    CURRENT_PC=$(cat /sys/bus/pci/devices/0000:00:14.3/power/control 2>/dev/null)
    if [ "$CURRENT_PC" != "on" ]; then
        echo on > /sys/bus/pci/devices/0000:00:14.3/power/control 2>/dev/null || true
    fi
fi

# Only act if WiFi is administratively enabled in NetworkManager
if nmcli radio wifi 2>/dev/null | grep -q -E "activé|enabled"; then
    NEED_HEAL=0
    
    # Check 1: Interface missing completely
    if ! ip link show wlp0s20f3 >/dev/null 2>&1; then
        NEED_HEAL=1
    # Check 2: Interface marked unavailable in NetworkManager
    elif nmcli dev status 2>/dev/null | grep -E "wlp0s20f3|wlan0" | grep -q -E "indisponible|unavailable"; then
        NEED_HEAL=1
    # Check 3: Connected but unresponsive to traffic (hardware wedged)
    elif nmcli dev status 2>/dev/null | grep -E "wlp0s20f3|wlan0" | grep -q -E "connecté|connected"; then
        if ! ping -I wlp0s20f3 -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            sleep 2
            if ! ping -I wlp0s20f3 -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
                NEED_HEAL=1
            fi
        fi
    fi

    if [ "$NEED_HEAL" -eq 1 ]; then
        # Read state: timestamp and counter
        LAST_TIME=0
        COUNT=0
        if [ -f "$LOCKFILE" ]; then
            read LAST_TIME COUNT < "$LOCKFILE"
        fi

        # Reset counter if older than 300s (5 minutes)
        if [ $((NOW - LAST_TIME)) -gt 300 ]; then
            COUNT=0
        fi

        if [ "$COUNT" -lt 3 ]; then
            COUNT=$((COUNT + 1))
            echo "$NOW $COUNT" > "$LOCKFILE"
            logger -t wifi-autoheal "Wi-Fi failure detected. Attempt $COUNT/3: Triggering PCIe hot reset."
            
            if [ -d "/sys/bus/pci/devices/0000:00:14.3" ]; then
                echo 1 > /sys/bus/pci/devices/0000:00:14.3/remove 2>/dev/null || true
                sleep 0.5
            fi
            echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
            sleep 1
            if [ -f "/sys/bus/pci/devices/0000:00:14.3/power/control" ]; then
                echo on > /sys/bus/pci/devices/0000:00:14.3/power/control 2>/dev/null || true
            fi
            modprobe iwlwifi 2>/dev/null || true
            rfkill unblock wifi 2>/dev/null || true
            systemctl restart wpa_supplicant 2>/dev/null || true
            logger -t wifi-autoheal "PCIe hot reset attempt $COUNT completed."
        else
            logger -t wifi-autoheal "Max recovery attempts (3) reached. Awaiting cooldown."
        fi
    else
        # Wi-Fi is healthy, clear failure counter
        rm -f "$LOCKFILE"
    fi
fi
exit 0
