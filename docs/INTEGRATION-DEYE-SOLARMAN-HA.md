# Intégration micro-onduleurs DEYE dans Home Assistant (Solarman)

> **Statut :** ✅ Opérationnel — 2 appareils, 110 entités
> **Date de mise en service :** 22 juillet 2026
> **Installation :** Santuario, Badalucco (Liguria)

---

## 1. Configuration finale validée

### 1.1 Matériel

| Élément | Détail |
|---|---|
| Micro-onduleurs | 2 × DEYE SUN-M200G4-EU-Q0 (3720 W) |
| Logger WiFi | Intégré, Web Ver `DE1.0.25` |
| Onduleur n°1 | `192.168.1.250` — S/N `3871081176` — AP `AP_3871081176` |
| Onduleur n°2 | `192.168.1.251` — S/N `3867806531` — AP `AP_3867806531` |
| Hôte HA | Home Assistant OS en VM (VMware Fusion) sur Mac Mini M4 — `192.168.1.10` |

### 1.2 Configuration des loggers DEYE

Accès : `http://192.168.1.250` (et `.251`) → menu **Advanced**

**Internal server parameters setting** — section déterminante :

| Paramètre | Valeur | Remarque |
|---|---|---|
| Protocol | **`TCP-Server`** | ⚠️ Critique — était en `TCP-Client` d'origine |
| Port | **`8889`** | ⚠️ Pas 8899 (standard Solarman) sur ce firmware |
| Server address | *(grisé)* | Inactif en mode serveur |
| TCP time out setting | **`60`** | Réduit de 300 → 60 s (voir §3.3) |

**Serial port parameters setting** — inchangé, valeurs d'usine :

| Paramètre | Valeur |
|---|---|
| Baud rate | 9600 |
| Data bit | 8 |
| Parity bit | None |
| Stop bit | 1 |
| CTSRTS | Disable |

**Mode Select :** `AP+STA`
**Invertor Brand Select :** `Deye`

> ⚠️ Après toute modification : **Save** puis **Restart** depuis le menu de gauche. Les changements ne prennent effet qu'après redémarrage du logger.

### 1.3 Intégration Home Assistant

**Composant :** [`davidrapan/ha-solarman`](https://github.com/davidrapan/ha-solarman) — version `25.08.16`
**Installation :** disponible directement dans le store HACS par défaut (pas besoin de dépôt personnalisé)

Paramètres identiques pour les deux entrées :

| Champ | Valeur |
|---|---|
| Hostname or IP address | `192.168.1.250` / `192.168.1.251` |
| Port | `8889` |
| Transport protocol | `TCP` |
| Profile | **`deye_micro.yaml`** |
| Modbus Slave ID | `1` |
| Number of MPPTs | `4` |
| Number of Phases | `1` |
| Number of Battery packs | *(décoché)* |

> Le numéro de série n'est pas demandé : ce fork le récupère automatiquement pendant le handshake Solarman V5.

**Résultat :** 2 appareils × 55 entités = **110 entités**

---

## 2. Historique du diagnostic

Cinq problèmes distincts se sont superposés. Ordre de résolution :

### 2.1 Mode TCP-Client au lieu de TCP-Server

**Symptôme :** aucune communication, statut `disconnected`.

**Cause :** le logger était configuré en `TCP-Client` pointant vers `192.168.1.10:502`. Dans ce mode, le logger *sort* vers une machine distante pour y pousser des trames. L'intégration Solarman fait l'inverse : elle se connecte *au logger* comme client. Il faut donc que le logger **écoute** en `TCP-Server`.

**Résolution :** Protocol → `TCP-Server`.

### 2.2 Port applicatif

**Symptôme :** `nc -zv 192.168.1.250 8899` → `Connection refused`.

**Cause :** le port par défaut du protocole Solarman V5 est 8899, mais ce firmware DEYE utilise **8889**. Le champ Port du logger affichait bien 8889 ; c'est le test qui visait le mauvais port.

**Résolution :** conserver 8889 côté logger, et le renseigner tel quel dans HA. Le protocole est identique quel que soit le port.

### 2.3 Fork Solarman inadapté

**Symptôme :** `NoSocketAvailableError: No socket available`, en boucle toutes les 13 secondes, échec en ~4 ms.

**Cause :** `StephanJoubert/home_assistant_solarman` ouvre un socket au démarrage et ne le rouvre jamais s'il tombe. Le logger fermant les connexions inactives, l'intégration reste bloquée indéfiniment. L'échec quasi instantané (4 ms) — bien plus rapide qu'un timeout réseau — signalait que le socket était absent avant même l'appel.

Ce fork ne propose par ailleurs **aucun profil micro-onduleur** (uniquement `deye_hybrid`, `deye_string`, `deye_4mppt`, `deye_sg04lp3`).

**Résolution :** remplacement par `davidrapan/ha-solarman`, qui gère la reconnexion et fournit `deye_micro.yaml`.

### 2.4 Profil « Auto » défaillant

**Symptôme :** `Error setuping Inverter: 'NoneType' object has no attribute 'parser'`.

**Cause :** l'auto-détection interroge un registre d'identification que les micro-onduleurs ne renseignent pas. Le profil reste à `None` et le setup plante.

**Résolution :** sélectionner explicitement `deye_micro.yaml` au lieu de `Auto`.

### 2.5 Saturation du logger — cause finale

**Symptôme :** après plusieurs tentatives, `nc -zv 192.168.1.250 8889` ne répondait plus du tout, alors qu'il répondait auparavant.

**Cause :** **le logger DEYE n'accepte qu'une seule connexion TCP simultanée.** Chaque tentative ratée (tests `nc`, script Python, ancien fork, nouveau fork) avait laissé une session pendante. Avec un timeout de 300 s, le slot restait occupé 5 minutes par session morte — saturation complète.

**Résolution :** redémarrage du logger (Advanced → Restart) pour libérer les sessions, puis réduction du `TCP time out setting` de 300 à **60 secondes**.

---

## 3. Points de vigilance pour l'exploitation

### 3.1 Une seule connexion à la fois

C'est la contrainte structurante. Tout client concurrent fait tomber HA :

- ❌ Script Python `pysolarmanv5` pendant que HA tourne
- ❌ Application mobile Solarman connectée en local
- ❌ Cloud Solarman si `Remote Server A` reste actif
- ❌ Tests `nc` répétés

**En cas de coupures intermittentes**, vérifier en priorité qu'aucun second client ne parle au logger.

### 3.2 Remote server

La section **Remote server** contient `Server A` (cloud Solarman) et `Server B`. Le `Server B` pointait vers `192.168.1.10:502` — vestige de la configuration TCP-Client, à vider.

Si des déconnexions surviennent, envisager de désactiver aussi le `Server A` (cloud) pour libérer définitivement le slot au profit de HA.

### 3.3 Timeout à 60 s

Ramené de 300 à 60 secondes. Une session morte se libère désormais en une minute au lieu de cinq, ce qui rend le système bien plus tolérant aux reconnexions et aux redémarrages de HA.

### 3.4 Redémarrage obligatoire du logger

Toute modification dans **Advanced** exige un Save **puis** un Restart. L'interface le rappelle explicitement. Sans redémarrage, les paramètres affichés ne reflètent pas le comportement réel.

### 3.5 Si le logger ne répond plus du tout

Si même l'interface web devient inaccessible : couper l'alimentation du micro-onduleur quelques secondes. Le logger étant alimenté par l'onduleur, c'est le seul reset matériel possible.

---

## 4. Procédure de diagnostic (réutilisable)

En cas de panne, dérouler dans cet ordre — chaque étape isole une couche.

### Étape 1 — Le port répond-il ?

```bash
nc -zv 192.168.1.250 8889
```

- ✅ `succeeded` → passer à l'étape 2
- ❌ `refused` → logger saturé ou mal configuré → Restart du logger

### Étape 2 — Le protocole Solarman V5 fonctionne-t-il ?

```bash
pip3 install pysolarmanv5 --break-system-packages
python3 -c "
from pysolarmanv5 import PySolarmanV5
m = PySolarmanV5('192.168.1.250', 3871081176, port=8889, mb_slave_id=1, verbose=True)
print(m.read_holding_registers(register_addr=3, quantity=1))
"
```

- ✅ Une valeur est retournée → le problème est côté HA
- ❌ Timeout → mauvais port applicatif
- ❌ Erreur checksum/serial → numéro de série incorrect

> ⚠️ **Fermer ce test avant de relancer HA** — sinon le slot TCP reste occupé.

### Étape 3 — La VM HA atteint-elle le logger ?

Via SSH sur HA (Tabby, port 22222) :

```bash
nc -zv 192.168.1.250 8889
```

Si le Mac hôte réussit mais que la VM échoue → problème de routage VMware.

### Étape 4 — Que disent les logs HA ?

```bash
ha core logs | grep -i solarman | tail -40
```

Puis, si rien n'apparaît (le fork peut utiliser un autre nom de logger) :

```bash
ha core logs | tail -100
```

> ⚠️ Vérifier les **timestamps** : les logs HA conservent les sessions précédentes. Une erreur affichée dans l'UI peut être figée sur une tentative ancienne.

---

## 5. Résultat de référence — trame Solarman V5 valide

Test ayant confirmé le bon fonctionnement du protocole (22/07/2026) :

```
SENT: a5 17 00 10 45 4e 00 d8 02 bc e6 02 00 00 00 00 00 00 00 00
      00 00 00 00 00 00 01 03 00 03 00 01 74 0a be 15
RECD: a5 15 00 10 15 4e 01 d8 02 bc e6 02 01 a2 3f 98 00 0e 03 00
      00 00 00 00 00 01 03 02 32 34 ac f3 9d 15
→ [12852]
```

Lecture du registre holding `3`, quantité `1`, slave ID `1` → valeur `12852`.

---

## 6. Prolongements envisagés

- **InfluxDB / Grafana** — historiser la production par micro-onduleur, en cohérence avec l'infrastructure de monitoring existante sur le Pi5 (`192.168.1.141`).
- **Contrôle par décalage de fréquence** — croiser les données Solarman avec le pilotage Shelly Pro 2PM (>52 Hz pendant 15 s → déconnexion ; <50,3 Hz pendant 45 s → reconnexion). Permet enfin de vérifier côté onduleur ce que le relais commande côté Shelly.
- **Repli MQTT** — en cas d'instabilité de l'intégration, un service Python autonome sur le Pi5 utilisant `pysolarmanv5` pourrait interroger les deux loggers et publier via MQTT discovery vers HA. S'aligne avec l'architecture Mosquitto existante et supprime la dépendance à un composant tiers.

---

## 7. Références

| Sujet | URL |
|---|---|
| Intégration retenue | https://github.com/davidrapan/ha-solarman |
| Ancien fork (abandonné) | https://github.com/StephanJoubert/home_assistant_solarman |
| Bibliothèque Python | https://pypi.org/project/pysolarmanv5/ |

---

*Document rédigé pour le projet Santuario — 22 juillet 2026.*
