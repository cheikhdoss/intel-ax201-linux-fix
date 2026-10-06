# Journal de Débogage Complet : Résolution du Bug Wi-Fi Intel AX201 (CNVi) sous Linux

Ce document retrace l'intégralité de la démarche d'ingénierie, des hypothèses techniques, des échecs intermédiaires, des découvertes décisives et de la stabilisation finale du contrôleur Wi-Fi **Intel AX201** sur un **Lenovo ThinkPad L13 Yoga Gen 1**.

---

## 1. Environnement Matériel et Logiciel de Départ

- **Machine hôte** : Lenovo ThinkPad L13 Yoga Gen 1 (Modèle `20R6S3HQ00`, BIOS version `R15ET62W 1.43` du 18/02/2025).
- **Processeur / Chipset** : Intel Core 10ème génération (Comet Lake PCH-LP).
- **Carte Wi-Fi physique** : Module intégré CNVi **Intel Wi-Fi 6 AX201 160MHz** (`QuZ-a0-hr-b0`).
  - Identifiant PCI : `0000:00:14.3 [8086:02f0]`
  - Sous-système : `Dual Band Wi-Fi 6(802.11ax) AX201 160MHz 2x2 [Harrison Peak] [8086:0070]`
  - CRF ID : `0x3617` | CNV-ID : `0x20000302` | WFPM ID : `0x80000000` | RF : `HR B3`
- **Système d'exploitation** : Ubuntu 24.04 LTS.
- **Noyaux en jeu** :
  - Noyau initial actif : `7.0.0-34-generic` (noyau récent en cours de développement, hautement expérimental).
  - Noyau stable LTS cible : `6.17.0-35-generic`.
- **Réseau cible** : Box résidentielle `Flybox_E940` (Orange Sénégal / Sonatel) émettant simultanément en 2.4 GHz et 5 GHz.
- **Liaison de secours** : Partage de connexion USB iPhone (`ipheth`, interface `enxba7bc549a3e9`).

---

## 2. Symptômes Initiaux : La Mort Silencieuse de la Carte

Au démarrage de la session, la machine n'avait plus aucun accès Wi-Fi :
- `nmcli radio all` affichait : `WIFI-HW: missing`.
- `rfkill list` ne montrait que le Bluetooth (`hci0`), la section Wi-Fi ayant totalement disparu.
- Les logs du noyau (`dmesg`) renvoyaient en boucle des erreurs d'initialisation matérielle :
  ```text
  iwlwifi 0000:00:14.3: Failed to run INIT ucode: -110
  iwlwifi 0000:00:14.3: retry init count 2
  iwlwifi 0000:00:14.3: LMAC1 CURRENT PC: 0xd0
  iwlwifi 0000:00:14.3: Failed to start RT ucode: -110
  ```

### Le piège du redémarrage doux (Soft Reboot)
Un simple redémarrage logiciel (`sudo reboot`) ne résolvait jamais la situation.  
**Pourquoi ?** Parce que l'architecture Intel CNVi sépare la logique MAC (dans le PCH) de l'étage radio RF (le module CRF). Sur un ThinkPad moderne sur batterie ou secteur, les rails d'alimentation standby (3.3V / 1.8V) maintiennent la puce sous tension même lors d'un redémarrage. Le processeur interne du microcode reste alors verrouillé sur son compteur d'instructions figé (`PC: 0xd0`).

Pour atteindre le **0V absolu** et forcer un reset de niveau composant, deux méthodes ont été identifiées :
1. **Méthode physique** : Éteindre le PC et insérer un trombone pendant 15 secondes dans le trou de réinitialisation d'urgence (*Emergency Reset Hole*) situé sous le châssis du ThinkPad.
2. **Méthode logicielle à chaud** : Forcer la déconnexion et la réinitialisation électrique du pont PCIe via sysfs :
   ```bash
   echo 1 > /sys/bus/pci/devices/0000:00:14.3/remove
   echo 1 > /sys/bus/pci/rescan
   ```

---

## 3. L'Enquête sur le Microcode : L'Inversion de Version

En analysant l'historique des démarrages de la machine :
- Au boot de **03:09 du matin**, la carte s'était initialisée avec succès en chargeant le microcode `77.563a6e92.0`.
- À **03:11 du matin**, suite à une mise à jour de paquets Ubuntu, le microcode avait été remplacé par `77.f39cc7f9.0`. Immédiatement après, la carte est entrée dans une spirale de paniques mémoires :
  ```text
  ADVANCED_SYSASSERT 0x90
  ADVANCED_SYSASSERT 0x92
  ```

### La cause racine
Le binaire de microcode fourni par le paquet standard Ubuntu Noble pour la révision `QuZ-a0-hr-b0-77` souffre d'un bug majeur d'allocation de tampons DMA lors des scans multi-bandes.  
La version amont (*upstream*) disponible sur le dépôt officiel `linux-firmware` de `kernel.org` (commit `563a6e92`) corrigeait précisément ce défaut.

### La résolution
Nous avons téléchargé l'archive amont officielle, extrait le microcode certifié `iwlwifi-QuZ-a0-hr-b0-77.ucode` (1,4 Mo) et sa version compressée `.zst`, remplacé les binaires corrompus dans `/lib/firmware/intel/iwlwifi/`, et régénéré l'initramfs.

---

## 4. La Découverte du Paramètre Toxique `power_scheme=1`

En inspectant `/etc/modprobe.d/`, nous avons découvert un ancien fichier résiduel contenant :
```ini
options iwlwifi power_scheme=1
```
Sur les puces Intel CNVi, `power_scheme=1` ordonne au pilote de couper l'alimentation de l'étage RF dès que le trafic réseau passe sous un certain seuil.  
Dès que la carte tentait d'émettre des trames d'authentification ou d'association, le coupe-circuit s'activait en pleine transmission, coupant l'alimentation de l'horloge et provoquant le gel immédiat du processeur LMAC (`PC: 0xd0`).

**Action** : Éradication totale de `power_scheme=1`.

---

## 5. Le Bug Wi-Fi 6 (802.11ax) et la Box Hybride

La puce Intel AX201 est un adaptateur Wi-Fi 6 (802.11ax). Or, les box 4G/Fibre résidentielles (telles que la Flybox Orange E940) émettent en mode mixte ou gèrent de manière non standard les trames HE (High Efficiency) et les balises d'économie d'énergie TWT.  
Lors de la négociation initiale, le pilote `iwlmvm` sous Linux rencontrait des assertions système non gérées.

**Action corrective** :  
Désactivation de la couche 11ax via `/etc/modprobe.d/iwlwifi.conf` :
```ini
options iwlwifi disable_11ax=1
```
*Effet : La carte bascule de manière transparente en Wi-Fi 5 (802.11ac VHT) sur le 5 GHz et en Wi-Fi 4 (802.11n) sur le 2.4 GHz, éliminant 100 % des crashes tout en offrant des débits réels supérieurs à 35 Mbit/s.*

---

## 6. Le Décrochage Dramatique de 15:45 : La Régression du Noyau 7.0

Après avoir résolu les trois premiers bugs, la connexion Wi-Fi s'est établie à 15:36 avec un ping parfait vers Google. Mais à **15:45**, la carte a soudainement décroché à nouveau.

### L'autopsie des logs noyau (`dmesg`)
L'analyse à la milliseconde près a révélé le déclencheur exact :
```text
[ 1272.903290] iwlwifi 0000:00:14.3: Failed to send LINK_CONFIG_CMD (action:3): -5
[ 1272.903343] wlp0s20f3: deauthenticating from 82:82:92:40:e9:a3 by local choice (Reason: 3=DEAUTH_LEAVING)
[ 1272.903504] wlp0s20f3: HW problem - can not stop rx aggregation for 82:82:92:40:e9:a3 tid 0
[ 1272.903522] iwlwifi: Failed to trigger RX queues sync (-5)
[ 1272.905337] iwlwifi: PHY ctxt cmd error. ret=-5
[ 1275.150040] iwlwifi: LMAC1 CURRENT PC: 0xd0
[ 1275.150067] iwlwifi: Failed to start RT ucode: -110
```
Et plus haut dans le noyau :
```text
Workqueue: events_freezable ieee80211_restart_work [mac80211]
RIP: 0010:_sta_info_move_state+0x189/0x430 [mac80211]
7.0.0-34-generic #34~24.04.1-Ubuntu PREEMPT(lazy)
```

### Le diagnostic
1. **La régression `mac80211` de Linux 7.0** : Le noyau 7.0 (en cours de développement) intègre des refontes majeures pour le Wi-Fi 7 (MLO) qui ont introduit une régression dans `_sta_info_move_state` et dans la gestion de l'agrégation de trames RX (`A-MPDU`).
2. Lors d'un réajustement de signal, la carte n'a pas pu arrêter la file d'attente d'agrégation (`can not stop rx aggregation`), déclenchant un timeout matériel (`-5`, EIO) qui a fait planter le microcode.

### La double parade déployée
1. **Désactivation de l'agrégation RX dans le pilote** :  
   Dans la documentation du module `iwlwifi` :
   ```text
   parm: 11n_disable: disable 11n functionality, bitmap: 1: full, 2: disable agg TX, 4: disable agg RX, 8 enable agg TX
   ```
   Le masque `4` correspond à `IWL_DISABLE_HT_RXAGG` (désactivation de l'agrégation de réception).  
   Nous avons mis à jour `/etc/modprobe.d/iwlwifi.conf` :
   ```ini
   options iwlwifi disable_11ax=1 11n_disable=4
   ```
2. **Verrouillage du boot sur le noyau LTS 6.17 dans GRUB** :  
   Le noyau **Linux 6.17 LTS** possède une pile réseau mature et exempte de ce bug.  
   Nous avons configuré `/etc/default/grub` de manière explicite :
   ```bash
   GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-35-generic"
   ```
   Et exécuté `update-grub` pour graver ce choix.

---

## 7. La Résurrection à Chaud

Sans même redémarrer le système d'exploitation, nous avons réinitialisé le bus PCIe :
```bash
echo 1 > /sys/bus/pci/devices/0000:00:14.3/remove
sleep 1
echo 1 > /sys/bus/pci/rescan
sleep 2
modprobe iwlwifi
```
**Résultat immédiat** :
- La puce physique s'est réveillée, a chargé le microcode amont `77.563a6e92.0`.
- Interface renommée en `wlp0s20f3`.
- Association et authentification automatiques à `Flybox_E940` (IP `192.168.1.173`).
- Routage par défaut actif avec métrique 50 (prioritaire sur l'iPhone).
- L'utilisateur a pu débrancher son iPhone sans interruption de connexion.

---

## 8. Le Blindage Permanent : Veille & Watchdog Auto-Healing

Pour garantir que le Wi-Fi ne plantera plus jamais après des redémarrages ou des mises en veille, deux composants logiciels ont été créés :

### 1. Le Hook de sortie de veille (`/usr/lib/systemd/system-sleep/iwlwifi-wake.sh`)
Exécuté par systemd lors de tout réveil (`post/suspend`) :
- Débloque automatiquement `rfkill`.
- Vérifie si `wlp0s20f3` est bien présent. Si le bus PCIe est resté en sommeil profond, il déclenche silencieusement un `rescan` pour réveiller la carte sous 1 seconde.

### 2. Le Watchdog d'Auto-Guérison (`wifi-autoheal`)
- Service : `/etc/systemd/system/wifi-autoheal.service`
- Timer : `/etc/systemd/system/wifi-autoheal.timer` (actif toutes les 30 secondes).
- **Règle stricte** :
  - Si le Wi-Fi est actif dans Ubuntu ET que l'interface `wlp0s20f3` a disparu (crash matériel exceptionnel), le script réinitialise le bus PCIe et relance le pilote en moins d'une seconde.
  - Tant que la connexion est présente (99,99 % du temps), le script vérifie en 5 ms et ne fait rien.
  - Si l'utilisateur désactive le Wi-Fi manuellement (mode Avion), le watchdog n'intervient pas.

---

## 9. Le Test Ultime du 5 GHz

À la demande de l'utilisateur, nous avons testé la connexion sur la bande 5 GHz (`Flybox_E940_5G`) :
- Canal 36, vitesse négociée à **270 Mbit/s**.
- Ping passerelle : **1,1 ms** | Ping 1.1.1.1 : **18 ms** (0 % de perte).
- Téléchargement test de 10 Mo : effectué en **2,39 secondes** (**4,18 Mo/s**), contre 40 secondes en 2.4 GHz (**16,9 fois plus rapide**).
- Zéro erreur dans `dmesg`.

Puis, conformément au souhait de l'utilisateur de conserver le choix manuel, nous avons désactivé l'autoconnexion du 5 GHz (`connection.autoconnect: non`) et réactivé par défaut le 2.4 GHz (`Flybox_E940`).

---

## 10. Synthèse des Correctifs Actifs sur le Système

1. `/etc/modprobe.d/iwlwifi.conf` : `options iwlwifi disable_11ax=1 11n_disable=4`
2. `/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf` : `wifi.powersave = 2`
3. `/usr/lib/systemd/system-sleep/iwlwifi-wake.sh` : Hook post-veille
4. `/etc/systemd/system/wifi-autoheal.timer` : Surveillance toutes les 30s
5. `/etc/default/grub` : Boot automatique verrouillé sur Linux LTS 6.17
6. Microcode officiel amont `77.563a6e92.0` déployé dans `/lib/firmware/intel/iwlwifi/`
