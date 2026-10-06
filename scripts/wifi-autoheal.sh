#!/bin/bash
# Self-healing watchdog for Intel AX201 CNVi Wi-Fi
# Only act if WiFi is administratively enabled in NetworkManager
if nmcli radio wifi 2>/dev/null | grep -q -E "activé|enabled"; then
    if ! ip link show wlp0s20f3 >/dev/null 2>&1; then
        logger -t wifi-autoheal "wlp0s20f3 missing while WiFi enabled. Triggering PCIe recovery."
        if [ -d "/sys/bus/pci/devices/0000:00:14.3" ]; then
            echo 1 > /sys/bus/pci/devices/0000:00:14.3/remove 2>/dev/null || true
            sleep 0.5
        fi
        echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
        sleep 1
        modprobe iwlwifi 2>/dev/null || true
        rfkill unblock wifi 2>/dev/null || true
        systemctl restart wpa_supplicant 2>/dev/null || true
        logger -t wifi-autoheal "PCIe recovery completed."
    fi
fi
exit 0
