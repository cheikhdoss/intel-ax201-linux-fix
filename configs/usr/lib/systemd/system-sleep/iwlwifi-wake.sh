#!/bin/bash
# Auto-recovery for Intel AX201 CNVi Wi-Fi upon resume from suspend
case "$1/$2" in
  post/*)
    rfkill unblock wifi 2>/dev/null || true
    
    # Always force PCIe power control to on (prevent runtime D3 sleep)
    if [ -d "/sys/bus/pci/devices/0000:00:14.3" ]; then
      echo on > /sys/bus/pci/devices/0000:00:14.3/power/control 2>/dev/null || true
    fi
    
    sleep 1.5
    
    # Check if interface is missing or if kernel microcode crashed on resume
    NEED_RESET=0
    if ! ip link show wlp0s20f3 >/dev/null 2>&1; then
      NEED_RESET=1
    elif dmesg | tail -n 25 | grep -q -E "Microcode SW error|NMI_INTERRUPT_LMAC|Failed to start RT ucode"; then
      NEED_RESET=1
    fi
    
    if [ "$NEED_RESET" -eq 1 ]; then
      if [ -d "/sys/bus/pci/devices/0000:00:14.3" ]; then
        echo 1 > /sys/bus/pci/devices/0000:00:14.3/remove 2>/dev/null || true
        sleep 0.5
      fi
      echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
      sleep 1
      if [ -d "/sys/bus/pci/devices/0000:00:14.3" ]; then
        echo on > /sys/bus/pci/devices/0000:00:14.3/power/control 2>/dev/null || true
      fi
      modprobe iwlwifi 2>/dev/null || true
      systemctl restart wpa_supplicant 2>/dev/null || true
    fi
    ;;
esac
exit 0
