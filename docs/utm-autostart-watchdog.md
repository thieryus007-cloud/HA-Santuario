# Démarrage automatique et relance de Home Assistant (UTM) — Santuario

> Procédure validée pour que la VM Home Assistant, hébergée dans UTM sur le Mac Mini M4,
> démarre automatiquement au boot **et** se relance seule si UTM plante.

**Date :** 21 juillet 2026
**Hôte :** Mac Mini M4 — macOS 26.5.2
**Virtualisation :** UTM 4.7.5 (QEMU ARM64)
**VM :** `HA-Santuario` — Home Assistant OS 18.1
**IP VM :** 192.168.1.10
**Statut :** ✅ Autostart + watchdog opérationnels

---

## 1. Contexte et problème résolu

Home Assistant tourne dans une **VM UTM**. Deux risques d'indisponibilité :

1. **Reboot du Mac** → la VM ne redémarre pas seule par défaut.
2. **Crash de l'application UTM** → la VM étant un processus enfant d'UTM, elle
   s'arrête avec lui. Un crash de rendu graphique d'UTM (observé :
   `EXC_BAD_ACCESS` dans CoreGraphics/QuartzCore après plusieurs heures) coupe
   alors Home Assistant tant qu'aucune relance n'intervient.

La solution combine un **mode headless** (réduit les crashs de rendu) et un
**watchdog launchd** (relance automatique périodique).

## 2. Mode headless de la VM

Retirer l'affichage virtuel réduit fortement les crashs de rendu d'UTM et allège
la VM. L'accès se fait uniquement par le réseau (web + SSH).

Procédure (VM arrêtée) : UTM → sélectionner `HA-Santuario` → **Edit** →
périphérique **Display** → bouton **Remove** → **Save**.

> L'arrêt de la VM doit être propre : depuis HA (**Paramètres → Système → Arrêter**),
> ou `ha host shutdown`, ou `utmctl stop`. Jamais d'arrêt forcé.

## 3. Contrôle en ligne de commande — utmctl

UTM fournit l'outil `utmctl` (l'ancienne méthode par URL `utm://` est dépréciée).

Lister les VM et vérifier le nom exact :

```bash
/Applications/UTM.app/Contents/MacOS/utmctl list
```

Démarrer / arrêter / interroger :

```bash
/Applications/UTM.app/Contents/MacOS/utmctl start  "HA-Santuario"
/Applications/UTM.app/Contents/MacOS/utmctl stop   "HA-Santuario"
/Applications/UTM.app/Contents/MacOS/utmctl status "HA-Santuario"
```

## 4. Watchdog de relance automatique (launchd)

C'est le cœur du dispositif. Un service vérifie toutes les 2 minutes que la VM
tourne, relance UTM si besoin, et redémarre la VM si elle n'est pas active. Il
couvre **à la fois** le démarrage au boot (`RunAtLoad`) et la relance après crash
(`StartInterval`).

### 4.1 Script de surveillance

```bash
mkdir -p ~/Scripts
cat > ~/Scripts/ha-watchdog.sh << 'EOF'
#!/bin/bash
VM="HA-Santuario"
UTMCTL="/Applications/UTM.app/Contents/MacOS/utmctl"

# S'assurer qu'UTM est lancé
if ! pgrep -x "UTM" > /dev/null; then
    open -a UTM
    sleep 15
fi

# Vérifier l'état de la VM ; la démarrer si elle ne tourne pas
STATUS=$("$UTMCTL" status "$VM" 2>/dev/null)
if [ "$STATUS" != "started" ]; then
    "$UTMCTL" start "$VM"
fi
EOF
chmod +x ~/Scripts/ha-watchdog.sh
```

### 4.2 Service launchd (LaunchAgent)

```bash
cat > ~/Library/LaunchAgents/com.santuario.ha-watchdog.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.santuario.ha-watchdog</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/Scripts/ha-watchdog.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Scripts/ha-watchdog.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Scripts/ha-watchdog.log</string>
</dict>
</plist>
EOF
```

### 4.3 Charger le service

```bash
launchctl unload ~/Library/LaunchAgents/com.santuario.ha-watchdog.plist 2>/dev/null
launchctl load   ~/Library/LaunchAgents/com.santuario.ha-watchdog.plist
```

## 5. Configuration système du Mac (serveur autonome)

Pour un vrai fonctionnement sans intervention :

- **Réglages Système → Économie d'énergie** → activer *Démarrer automatiquement
  après une coupure de courant*.
- **Réglages Système → Utilisateurs et groupes → Ouverture de session automatique**
  → sélectionner l'utilisateur (sinon la session ne s'ouvre pas seule et les
  services de session ne se lancent pas).

> ⚠️ L'ouverture automatique de session est **incompatible avec FileVault**. Pour
> un serveur domotique domestique, FileVault est généralement désactivé sur cette
> machine dédiée. Sinon, un reboot exigera une saisie manuelle du mot de passe.

## 6. Validation

| Test | Commande / action | Résultat attendu |
|---|---|---|
| Démarrage manuel VM | `utmctl start "HA-Santuario"` | `started` |
| Watchdog après arrêt | `utmctl stop` puis attendre ~2 min | repasse à `started` seul ✅ |
| Accès web HA | `nc -vz 192.168.1.10 8123` | `succeeded` |
| Accès SSH HA | `nc -vz 192.168.1.10 22222` | `succeeded` |
| Reboot complet | `sudo reboot` puis attendre ~2 min | HA de nouveau joignable |

Test réalisé : la VM, arrêtée manuellement, est repassée d'elle-même de `stopped`
à `started` en moins de 2 minutes. Relance automatique confirmée.

## 7. Maintenance

- **Journal du watchdog :** `~/Scripts/ha-watchdog.log`
- **Recharger après modification du plist :**
  ```bash
  launchctl unload ~/Library/LaunchAgents/com.santuario.ha-watchdog.plist
  launchctl load   ~/Library/LaunchAgents/com.santuario.ha-watchdog.plist
  ```
- **Désactiver temporairement :**
  ```bash
  launchctl unload ~/Library/LaunchAgents/com.santuario.ha-watchdog.plist
  ```
- **Réduire les crashs UTM :** garder la VM en headless, maintenir UTM à jour
  (les versions récentes corrigent des bugs de rendu sur macOS 26).

---

## Récapitulatif

Home Assistant redémarre désormais automatiquement au boot du Mac Mini et se
relance seul en cas d'arrêt de la VM ou de crash d'UTM, grâce à un watchdog
launchd vérifiant l'état toutes les 2 minutes. Le mode headless réduit le risque
de crash de rendu d'UTM.
