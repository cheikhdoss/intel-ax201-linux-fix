#!/bin/bash
# ==============================================================================
# Script : test-wifi-health.sh
# Description : Audit complet de santé du Wi-Fi Intel AX201 (CNVi)
# Usage : ./test-wifi-health.sh
# ==============================================================================

echo "=================================================================="
echo "          AUDIT DE SANTÉ WI-FI INTEL AX201 (iwlwifi)             "
echo "=================================================================="

echo ""
echo "--- 1. Noyau et Système ---"
uname -sr
uptime -p

echo ""
echo "--- 2. Périphérique PCIe (Intel AX201) ---"
lspci -nnk -s 00:14.3 || echo "[-] Périphérique PCIe 00:14.3 introuvable !"

echo ""
echo "--- 3. Paramètres iwlwifi chargés ---"
echo -n "disable_11ax : "
cat /sys/module/iwlwifi/parameters/disable_11ax 2>/dev/null || echo "N/A"
echo -n "11n_disable  : "
cat /sys/module/iwlwifi/parameters/11n_disable 2>/dev/null || echo "N/A"
echo -n "power_save   : "
cat /sys/module/iwlwifi/parameters/power_save 2>/dev/null || echo "N/A"

echo ""
echo "--- 4. État rfkill ---"
rfkill list wifi

echo ""
echo "--- 5. Interfaces réseau et Adresses IP ---"
ip -br addr show | grep -E "wl|wlp|lo"

echo ""
echo "--- 6. État NetworkManager ---"
nmcli dev status | grep -E "DEVICE|wifi" || true

echo ""
echo "--- 7. Réseau actif et Métriques de routage ---"
ip route show default

echo ""
echo "--- 8. Test de Connectivité et Latence ---"
if ping -c 3 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo "[+] Ping 1.1.1.1 : SUCCÈS (Connexion Internet active)"
    ping -c 3 1.1.1.1 | tail -n 2
else
    echo "[-] Ping 1.1.1.1 : ÉCHEC (Pas d'accès Internet)"
fi

echo ""
echo "--- 9. Dernières lignes dmesg (recherche d'erreurs iwlwifi) ---"
dmesg 2>/dev/null | grep -E "iwl|wlp" | tail -n 8 || sudo dmesg | grep -E "iwl|wlp" | tail -n 8 || true

echo ""
echo "=================================================================="
echo "                       FIN DE L'AUDIT                             "
echo "=================================================================="
