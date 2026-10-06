#!/bin/sh
# Auto-recovery for Intel AX201 CNVi Wi-Fi upon resume from suspend
case "$1/$2" in
  post/*)
    # Ensure RF is unblocked
    rfkill unblock wifi 2>/dev/null || true
    # Wait briefly for driver resume
    sleep 1
    # If interface is missing or card is wedged, trigger clean PCIe rescan
    if ! ip link show wlp0s20f3 >/dev/null 2>&1; then
      if [ -d "/sys/bus/pci/devices/0000:00:14.3" ]; then
        echo 1 > /sys/bus/pci/devices/0000:00:14.3/remove 2>/dev/null || true
        sleep 0.5
      fi
      echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
      sleep 1
      modprobe iwlwifi 2>/dev/null || true
      systemctl restart wpa_supplicant 2>/dev/null || true
    fi
    ;;
esac
exit 0
