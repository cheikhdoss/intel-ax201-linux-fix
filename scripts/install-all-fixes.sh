#!/bin/bash
# ==============================================================================
# Script : install-all-fixes.sh
# Description : Déploiement automatisé de l'ensemble des correctifs Intel AX201
# Usage : sudo ./install-all-fixes.sh
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[-] Ce script doit être exécuté avec les privilèges root (sudo)."
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=================================================================="
echo "    DÉPLOIEMENT DES CORRECTIFS WI-FI INTEL AX201 (THINKPAD/LINUX) "
echo "=================================================================="

# 1. Configuration modprobe iwlwifi
echo "[1/6] Application des options modprobe (/etc/modprobe.d/iwlwifi.conf)..."
mkdir -p /etc/modprobe.d
cat << 'EOF' > /etc/modprobe.d/iwlwifi.conf
options iwlwifi disable_11ax=1 11n_disable=4
EOF

# 2. Configuration NetworkManager (powersave = 2)
echo "[2/6] Désactivation du powersave agressif dans NetworkManager..."
mkdir -p /etc/NetworkManager/conf.d
cat << 'EOF' > /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
[connection]
wifi.powersave = 2
EOF

# 3. Hook de réveil de mise en veille (systemd-sleep)
echo "[3/6] Installation du hook de sortie de veille..."
mkdir -p /usr/lib/systemd/system-sleep
cp "$REPO_DIR/configs/usr/lib/systemd/system-sleep/iwlwifi-wake.sh" /usr/lib/systemd/system-sleep/
chmod +x /usr/lib/systemd/system-sleep/iwlwifi-wake.sh

# 4. Service et Timer de Self-Healing (wifi-autoheal)
echo "[4/6] Installation du service d'auto-guérison (wifi-autoheal)..."
cp "$REPO_DIR/scripts/wifi-autoheal.sh" /usr/local/bin/
chmod +x /usr/local/bin/wifi-autoheal.sh

cp "$REPO_DIR/configs/etc/systemd/system/wifi-autoheal.service" /etc/systemd/system/
cp "$REPO_DIR/configs/etc/systemd/system/wifi-autoheal.timer" /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now wifi-autoheal.timer

# 5. Régénération de l'initramfs
echo "[5/6] Mise à jour des initramfs..."
update-initramfs -u -k all

# 6. Vérification du microcode officiel amont
echo "[6/6] Vérification du firmware Intel QuZ-a0-hr-b0-77..."
if [ -f "/lib/firmware/intel/iwlwifi/iwlwifi-QuZ-a0-hr-b0-77.ucode" ]; then
    echo "[+] Microcode QuZ-77 présent."
else
    echo "[!] Attention : vérifiez la présence du microcode officiel 77.563a6e92.0 dans /lib/firmware/."
fi

echo ""
echo "=================================================================="
echo "  [+] TOUS LES CORRECTIFS ONT ÉTÉ APPLIQUÉS AVEC SUCCÈS !        "
echo "=================================================================="
