# 🛰️ Intel Wi-Fi 6 AX201 (CNVi / iwlwifi) Ultimate Linux Fix & Self-Healing Guide

> **Guide complet d'ingénierie, résolution de bogues matériels et système d'auto-guérison pour la puce Intel Wi-Fi 6 AX201 160MHz (Comet Lake CNVi) sous Linux / Ubuntu.**  
> *Testé et validé sur Lenovo ThinkPad L13 Yoga Gen 1.*

[![Platform](https://img.shields.io/badge/Platform-Linux%20%2F%20Ubuntu-orange.svg)](https://ubuntu.com)
[![Hardware](https://img.shields.io/badge/Hardware-Intel%20AX201%20CNVi-blue.svg)](https://ark.intel.com)
[![Status](https://img.shields.io/badge/Status-100%25%20Stable%20%26%20Tested-brightgreen.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🎯 Aperçu du Problème (The Problem)

Les puces **Intel Wi-Fi 6 AX201 (architecture CNVi Comet Lake `[8086:02f0]` / sous-système `[8086:0070]`)** sont tristement célèbres sous Linux pour disparaître subitement du système d'exploitation :
- `WIFI-HW: missing` dans NetworkManager.
- L'interface `wlp0s20f3` s'évapore, `rfkill list` ne montre plus aucune radio Wi-Fi.
- `dmesg` est inondé d'erreurs critiques :
  - `iwlwifi: Failed to run INIT ucode: -110`
  - `iwlwifi: LMAC1 CURRENT PC: 0xd0`
  - `ADVANCED_SYSASSERT 0x90` / `0x92`
  - `HW problem - can not stop rx aggregation for <BSSID> tid 0`
  - `Failed to trigger RX queues sync (-5)`
- **Le piège du redémarrage doux** : Un simple `sudo reboot` ne résout rien car les rails d'alimentation standby (3.3V/1.8V) du ThinkPad maintiennent le registre gelé (`PC: 0xd0`).

Ce dépôt fournit **l'analyse technique exhaustive des 8 causes racines identifiées**, la suite complète de scripts de remédiation, les fichiers de configuration système ainsi qu'un **système de résilience et d'auto-guérison (*Self-Healing Watchdog*)**.

---

## 🔬 Les 8 Bogues Identifiés et Leurs Résolutions

| # | Bogue Identifié | Symptôme dans les journaux noyau (`dmesg`) | Cause Racine | Correctif Déployé |
|---|-----------------|---------------------------------------------|--------------|-------------------|
| **1** | **Régression Microcode Ubuntu** | `ADVANCED_SYSASSERT 0x90` / `0x92` lors des scans | Le paquet Ubuntu `linux-firmware` a écrasé le microcode par la révision dépréciée `77.f39cc7f9.0`. | Remplacement par le microcode officiel amont `77.563a6e92.0` de `kernel.org`. |
| **2** | **Paramètre Toxique `power_scheme=1`** | `LMAC1 CURRENT PC: 0xd0` (Gel physique de l'horloge) | Coupe agressive de l'alimentation RF en pleine phase d'émission. | Suppression définitive de `power_scheme=1` dans `/etc/modprobe.d/`. |
| **3** | **Instabilité Wi-Fi 6 (802.11ax)** | Timeout d'association HE sur box hybrides (Flybox, Livebox) | Négociation des balises HE/TWT non conforme avec le pilote `iwlmvm`. | `disable_11ax=1` dans `/etc/modprobe.d/iwlwifi.conf` (bascule transparente en Wi-Fi 5 AC). |
| **4** | **Désynchronisation d'Agrégation RX** | `can not stop rx aggregation`, `Failed to trigger RX queues sync (-5)` | Régression du sous-système `mac80211` sur les noyaux récents/expérimentaux (ex: Linux 7.0). | `11n_disable=4` (désactivation agg RX) + Verrouillage boot sur **Linux LTS 6.17**. |
| **5** | **Powersave Agressif NetworkManager** | Latence en dents de scie, déconnexions aléatoires | NetworkManager active par défaut `wifi.powersave = 3`. | Forcé à `wifi.powersave = 2` (désactivé) dans `/etc/NetworkManager/conf.d/`. |
| **6** | **Verrou Électrique (0V Latch)** | Blocage persistant après redémarrage classique | La puce CNVi reste alimentée par les rails résiduels. | Utilisation du bouton d'urgence sous le châssis ou réinitialisation PCIe logicielle sysfs. |
| **7** | **Échec de Réveil en Sortie de Veille** | Carte endormie après mise en veille S3 (*deep sleep*) | Délai de resynchronisation d'horloge PCIe / verrou `rfkill`. | Hook systemd-sleep `/usr/lib/systemd/system-sleep/iwlwifi-wake.sh`. |
| **8** | **Absence d'Auto-Réparation** | Obligation de redémarrer en cas de pépin futur | Aucun mécanisme de supervision matériel autonome. | Déploiement du watchdog `wifi-autoheal.timer` (toutes les 30s) avec résurrection PCIe < 1s. |

---

## ⚡ Résultats & Benchmarks Réels

Tests réalisés sur Lenovo ThinkPad L13 Yoga connecté à une Flybox Orange 4G/Fibre :

- **Bande 2.4 GHz (802.11n)** : 10 Mo téléchargés en **40,46 s** (~247 Ko/s).
- **Bande 5 GHz (802.11ac)** : 10 Mo téléchargés en **2,39 s** (**4,18 Mo/s / ~35 Mbit/s réel**).  
  🚀 **Gain de vitesse : 16,9× plus rapide en 5 GHz, avec 0 erreur noyau.**
- **Latence passerelle** : **1,1 ms** | **Perte de paquets** : **0 %**.

Consultez le document complet : [`benchmarks/BENCHMARKS.md`](benchmarks/BENCHMARKS.md).

---

## 🚀 Installation Rapide (Quick Start)

### 1. Cloner le dépôt
```bash
git clone https://github.com/cheikhdoss/intel-ax201-linux-fix.git
cd intel-ax201-linux-fix
```

### 2. Déployer l'intégralité des correctifs
Exécutez le script d'installation automatisé avec les privilèges root :
```bash
sudo ./scripts/install-all-fixes.sh
```
Ce script applique :
- Les options modprobe anti-crash (`disable_11ax=1 11n_disable=4`).
- La désactivation du powersave agressif dans NetworkManager.
- Le hook de sortie de veille dans `/usr/lib/systemd/system-sleep/`.
- Le service et le timer d'auto-guérison `wifi-autoheal`.
- La mise à jour des images `initramfs`.

### 3. Vérifier la santé du Wi-Fi
```bash
./scripts/test-wifi-health.sh
```

---

## 🛠️ Outils Inclus

### 🔄 Réinitialisation à chaud du bus PCIe (`scripts/pci-hot-reset.sh`)
Si votre carte est actuellement bloquée dans l'état `PC: 0xd0` ou `missing`, ce script décharge le périphérique du bus PCIe, déclenche un rescan matériel et recharge le pilote sans avoir besoin d'éteindre l'ordinateur :
```bash
sudo ./scripts/pci-hot-reset.sh
```

### 🛡️ Le Watchdog d'Auto-Guérison (`scripts/wifi-autoheal.sh`)
Ce script est exécuté silencieusement toutes les 30 secondes par `wifi-autoheal.timer` :
- **Si tout va bien (99,99 % du temps)** : Le script vérifie l'existence de `wlp0s20f3` en moins de 5 ms et s'arrête sans toucher à rien.
- **Si l'interface a disparu suite à un crash** : Il réinitialise immédiatement le bus PCIe et rétablit le Wi-Fi en 1 seconde.
- **Si vous coupez le Wi-Fi vous-même (mode Avion)** : Il détecte l'état administratif et n'intervient pas.

---

## 📖 Journal de Débogage Détaillé

Pour comprendre le cheminement technique pas à pas, les fausses pistes évitées et l'analyse poussée des registres du microcode, lisez :  
👉 **[`JOURNAL_DE_DEBUG.md`](JOURNAL_DE_DEBUG.md)**

---

## 📜 Licence

Ce projet est distribué sous licence MIT. Libre de droit pour utilisation personnelle, professionnelle ou intégration dans des distributions Linux. Consultez le fichier [`LICENSE`](LICENSE) pour plus de détails.
