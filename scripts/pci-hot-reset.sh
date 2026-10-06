#!/bin/bash
# ==============================================================================
# Script : pci-hot-reset.sh
# Description : Réinitialisation à chaud du bus PCIe pour Intel AX201 (CNVi)
# Usage : sudo ./pci-hot-reset.sh
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[-] Ce script doit être exécuté en tant que root (sudo)."
   exit 1
fi

PCI_DEV="0000:00:14.3"

echo "[*] Diagnostic initial de la carte Wi-Fi..."
lspci -nnk -s "${PCI_DEV}" || true

echo "[*] Suppression du périphérique PCIe..."
if [ -d "/sys/bus/pci/devices/${PCI_DEV}" ]; then
    echo 1 > "/sys/bus/pci/devices/${PCI_DEV}/remove"
    sleep 0.5
fi

echo "[*] Rescan du bus PCIe..."
echo 1 > /sys/bus/pci/rescan
sleep 1

echo "[*] Rechargement du module iwlwifi..."
modprobe iwlwifi || true
sleep 1

echo "[*] Déblocage rfkill..."
rfkill unblock wifi || true

echo "[*] Redémarrage des services réseau..."
systemctl restart wpa_supplicant || true
systemctl restart NetworkManager || true

echo "[+] Réinitialisation terminée avec succès !"
echo "[*] État de l'interface :"
ip -br link show | grep -E "wl|wlp" || echo "[-] Aucune interface wlp trouvée."
