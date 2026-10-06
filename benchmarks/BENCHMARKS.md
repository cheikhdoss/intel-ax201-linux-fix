# Benchmarks & Mesures Réelles de Stabilité

Ce document consigne les tests réels effectués sur la machine cible (**Lenovo ThinkPad L13 Yoga Gen 1** équipée de la puce **Intel Wi-Fi 6 AX201 160MHz CNVi** et connectée à une box résidentielle **Flybox E940**).

---

## 1. Comparatif de Débit Réel (Transfert de 10 Mo)

Un payload de test standardisé de 10 Mo a été téléchargé depuis le CDN Cloudflare (`speed.cloudflare.com`) sur les deux bandes de fréquences après application des correctifs.

| Bande de fréquence | Canal | Protocole négocié | Débit réel constaté | Temps total de transfert | Ratio de vitesse |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **2.4 GHz** (`Flybox_E940`) | 1 | 802.11n (HT20/40) | 247 Ko/s | **40,46 secondes** | 1× (Référence) |
| **5 GHz** (`Flybox_E940_5G`) | 36 | 802.11ac (VHT80) | **4,18 Mo/s (~35 Mbit/s)** | **2,39 secondes** | **16,9× plus rapide** ⚡ |

> **Conclusion** : En désactivant le Wi-Fi 6 instable (`disable_11ax=1`), la puce bascule proprement en Wi-Fi 5 (802.11ac). La bande 5 GHz délivre un débit réel presque 17 fois supérieur à la bande 2.4 GHz sans provoquer le moindre crash de microcode.

---

## 2. Latence et Perte de Paquets (ICMP Ping)

### Test vers la passerelle locale (192.168.1.1)
- **2.4 GHz** :
  ```text
  4 packets transmitted, 4 received, 0% packet loss, time 3004ms
  rtt min/avg/max/mdev = 1.134/1.391/1.834/0.274 ms
  ```
- **5 GHz** :
  ```text
  4 packets transmitted, 4 received, 0% packet loss, time 3003ms
  rtt min/avg/max/mdev = 1.126/1.376/1.718/0.253 ms
  ```

### Test vers Cloudflare DNS (1.1.1.1)
- **2.4 GHz** :
  ```text
  4 packets transmitted, 4 received, 0% packet loss, time 3003ms
  rtt min/avg/max/mdev = 25.584/40.271/61.665/13.205 ms
  ```
- **5 GHz** :
  ```text
  4 packets transmitted, 4 received, 0% packet loss, time 3004ms
  rtt min/avg/max/mdev = 18.543/29.437/40.648/9.752 ms
  ```

---

## 3. Comportement du Noyau (`dmesg`)

Pendant toute la durée des tests de charge, des transferts de fichiers et de la transition à chaud entre 2.4 GHz et 5 GHz :
- **Nombre d'assertions système (`SYSASSERT`)** : 0
- **Nombre de plantages LMAC (`CURRENT PC: 0xd0`)** : 0
- **Nombre de timeouts de microcode (`-110`)** : 0
- **Nombre d'erreurs d'agrégation RX (`ret=-5`)** : 0
