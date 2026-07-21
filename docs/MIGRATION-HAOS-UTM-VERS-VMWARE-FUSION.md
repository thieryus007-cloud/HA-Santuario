# Migration Home Assistant OS : UTM → VMware Fusion — Santuario

> Migration de la VM Home Assistant depuis UTM vers VMware Fusion sur le Mac Mini M4,
> avec conservation de FileVault et résilience 24/7 (démarrage après coupure + relance sur crash).

**Date :** 21 juillet 2026
**Hôte :** Mac Mini M4 — macOS 26
**Virtualisation cible :** VMware Fusion 26H1 (Player, licence usage personnel gratuite)
**VM :** `HAOS-Santuario` — Home Assistant OS 18.1
**IP VM :** 192.168.1.10 (statique, reprise de l'ancienne instance UTM)
**Utilisateur Mac :** `thieryfontaine`

---

## 1. Sauvegarde Home Assistant (source UTM)

Sauvegarde complète chiffrée créée depuis l'ancienne instance :
Paramètres → Système → Sauvegardes → Créer une sauvegarde (complète).

- Fichier : `HA-full-pre-migration-2026-07-21.tar` (39.69 MB)
- Clé de chiffrement conservée hors ligne (kit de secours téléchargé).

La clé est indispensable à la restauration si la sauvegarde est chiffrée.

## 2. Installation de VMware Fusion

- Image : `VMware-Fusion-26H1-25388279_universal.dmg` (universal = Intel + Apple Silicon).
- Installée depuis le portail Broadcom, licence « Personal Use » (gratuite).

## 3. Préparation de l'image HAOS

Téléchargement de l'image VMDK ARM64 (aarch64) de HAOS 18.1 et décompression :

```bash
mkdir -p ~/HAOS-Fusion && cd ~/HAOS-Fusion
curl -L -O https://github.com/home-assistant/operating-system/releases/download/18.1/haos_generic-aarch64-18.1.vmdk.zip
unzip haos_generic-aarch64-18.1.vmdk.zip
```

Résultat : `haos_generic-aarch64-18.1.vmdk` (disque de 32 Go, image ~433 Mo).

> Bien prendre la variante **`generic-aarch64`** (ARM64, pour Apple Silicon),
> pas la variante `ova` qui est x86-64.

## 4. Création de la VM sous Fusion

Fusion → **Create a custom virtual machine** :

- OS : **Other Linux 6.x kernel 64-bit Arm**
- Firmware : **UEFI** (Secure Boot désactivé)
- Disque : **Use an existing virtual disk** → sélectionner le `.vmdk` ci-dessus →
  **Make a separate copy of the virtual disk**
- Nom : `HAOS-Santuario`

Réglages avant premier démarrage :

- **Processors & Memory** : 2 cœurs, 6144 MB
- **Network Adapter** : **Bridged Networking → Autodetect** (indispensable pour être
  visible sur le LAN `192.168.1.x` et pour mDNS / Matter / Thread)

## 5. Correction réseau (root cause : double adaptateur)

Au premier boot, la VM obtenait une IP NAT `172.16.x.x` et `supervisor_internet: false`.
Cause : deux adaptateurs réseau (un bridgé + un NAT résiduel) en conflit sur la route
par défaut.

Correction : supprimer l'adaptateur NAT dans les réglages Fusion, ne conserver qu'un
seul adaptateur en **Bridged**. Après redémarrage : IP `192.168.1.x`, une seule
interface, `supervisor_internet: true`.

## 6. Restauration de la sauvegarde

Depuis le navigateur du Mac sur la nouvelle instance :
Paramètres → Système → Sauvegardes → menu ⋮ → **Upload backup** → sélectionner le
`.tar`, puis restauration complète (config + add-ons).

Config restaurée à l'identique (Victron, HACS, Node-RED, Matter Server, OpenThread
Border Router, Terminal & SSH).

## 7. IP statique

Bascule de l'IP vers celle de l'ancienne instance, une fois l'ancien HA arrêté :
Paramètres → Système → Réseau → IPv4 → **Statique** → `192.168.1.10`
(passerelle `192.168.1.1`, DNS `192.168.1.1`).

## 8. Désinstallation complète d'UTM

Arrêt du watchdog UTM et suppression de tous ses composants :

```bash
launchctl bootout gui/$(id -u)/com.santuario.ha-watchdog 2>/dev/null
rm -f ~/Library/LaunchAgents/com.santuario.ha-watchdog.plist \
      ~/Scripts/ha-watchdog.sh ~/Scripts/ha-watchdog.log
```

Suppression d'UTM et de ses données :

```bash
/Applications/UTM.app/Contents/MacOS/utmctl stop "HA-Santuario"
osascript -e 'quit app "UTM"'
rm -rf /Applications/UTM.app
```

(Le dossier `~/Library/Containers/com.utmapp.UTM` peut subsister — résidu inoffensif,
supprimable via le Finder si souhaité.)

---

## 9. Résilience 24/7

Objectif : après une coupure de courant, tout redémarre seul ; et si HA tombe pendant
que le Mac tourne, il se relance seul. **FileVault conservé.**

### 9.1 Redémarrage du Mac après coupure secteur

```bash
sudo pmset -a autorestart 1
```

### 9.2 Déverrouillage FileVault automatique au boot (sans mot de passe)

FileVault reste actif (`fdesetup status` → On) mais le Mac supporte le redémarrage
authentifié (`fdesetup supportsauthrestart` → true). Armé de façon persistante :

```bash
sudo fdesetup authrestart -delayminutes -1
```

(Demande nom d'utilisateur + mot de passe.)

### 9.3 Lancement automatique de VMware Fusion à l'ouverture de session

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/VMware Fusion.app", hidden:false}'
```

### 9.4 Démarrage automatique de la VM au lancement de Fusion

Dans Fusion → réglages de la VM → **General** → cocher
**« Start automatically when VMware Fusion launches »**.

### 9.5 Watchdog de relance sur crash (LaunchAgent)

> Important : sur Fusion Apple Silicon, `vmrun start … nogui` échoue. Le démarrage
> doit se faire en mode **gui**. Le watchdog utilise donc `gui`.

Script :

```bash
mkdir -p ~/Scripts && cat > ~/Scripts/haos-watchdog.sh << 'EOF'
#!/bin/bash
VMX="/Users/thieryfontaine/Virtual Machines.localized/HAOS-Santuario.vmwarevm/HAOS-Santuario.vmx"
VMRUN="/Applications/VMware Fusion.app/Contents/Public/vmrun"
if ! pgrep -x "VMware Fusion" > /dev/null; then
    open -a "VMware Fusion"
    sleep 15
fi
if ! "$VMRUN" list | grep -qF "$VMX"; then
    "$VMRUN" start "$VMX" gui
fi
EOF
chmod +x ~/Scripts/haos-watchdog.sh
```

LaunchAgent (niveau session utilisateur, vérification toutes les 120 s) :

```bash
cat > ~/Library/LaunchAgents/com.santuario.haos-watchdog.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.santuario.haos-watchdog</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/thieryfontaine/Scripts/haos-watchdog.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/thieryfontaine/Scripts/haos-watchdog.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/thieryfontaine/Scripts/haos-watchdog.log</string>
</dict>
</plist>
EOF
launchctl bootout gui/$(id -u)/com.santuario.haos-watchdog 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.santuario.haos-watchdog.plist
```

---

## 10. Tests validés

| Test | Action | Résultat |
|---|---|---|
| Réseau bridged | Boot VM | IP `192.168.1.10/24`, `supervisor_internet: true` |
| Restauration | Upload `.tar` + restauration complète | Config + add-ons restaurés |
| Watchdog manuel | `vmrun stop` puis `~/Scripts/haos-watchdog.sh` | VM relancée en GUI (VMs: 1) |
| Watchdog auto | `vmrun stop`, attente ~2 min sans intervention | VM relancée seule (22:15 → 22:17) |

Test restant à faire en conditions réelles : `sudo reboot` ou coupure/rétablissement
secteur → HA doit revenir seul sur `192.168.1.10`.

---

## Maintenance

- **Journal watchdog :** `~/Scripts/haos-watchdog.log`
- **Recharger le watchdog après modification :**
  ```bash
  launchctl bootout gui/$(id -u)/com.santuario.haos-watchdog
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.santuario.haos-watchdog.plist
  ```
- **Désactiver temporairement :**
  ```bash
  launchctl bootout gui/$(id -u)/com.santuario.haos-watchdog
  ```
