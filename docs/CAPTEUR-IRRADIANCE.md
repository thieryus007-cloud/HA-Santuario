# Capteur d'irradiance dans Home Assistant

> **Statut :** 🟢 Opérationnel
> **Date :** 24 juillet 2026
> **Installation :** Santuario, Badalucco (Liguria)
> **Source retenue :** intégration Victron

---

## 1. Configuration retenue

### 1.1 Chaîne

```
Capteur PRALRAN (RS485, adresse 0x05)
            │
            ▼
    daly-bms-server
            │  HTTP GET /api/v1/irradiance/status (30 s)
            ▼
  energymanager (Rust) — logic/irradiance.rs
            │
            ▼
      Venus OS — NanoPi 192.168.1.120 (GX master)
            │  intégration Victron
            ▼
      Home Assistant — 192.168.1.10
            │
            ├── sensor.capteur_irradiance_id_40_irradiance  (brut)
            └── sensor.irradiance_lissee                    (moyenne 5 min)
```

### 1.2 Entités

| Entité | Rôle | Origine |
|---|---|---|
| `sensor.capteur_irradiance_id_40_irradiance` | Valeur brute | Intégration Victron — automatique |
| `sensor.irradiance_lissee` | Moyenne glissante 5 min | Package `irradiance.yaml` |

Le capteur brut est fourni par l'intégration Victron sans configuration : le Pi5 remonte déjà l'irradiance à Venus OS, qui l'expose comme n'importe quel appareil du bus.

---

## 2. Implémentation — `packages/irradiance.yaml`

```yaml
# =============================================================================
# Lissage de l'irradiance — source : integration Victron (Pi5 -> Venus OS)
# Entite source : sensor.capteur_irradiance_id_40_irradiance
# Doc : docs/CAPTEUR-IRRADIANCE.md
# =============================================================================

sensor:
  - platform: filter
    name: "Irradiance lissee"
    unique_id: santuario_irradiance_lissee
    entity_id: sensor.capteur_irradiance_id_40_irradiance
    filters:
      - filter: time_simple_moving_average
        window_size: "00:05"
        precision: 0
```

> Prérequis : `homeassistant: packages: !include_dir_named packages` dans `configuration.yaml` (voir `PILOTAGE-DEYE-SURPRODUCTION.md` §6.1).

**Mise en place :** créer le fichier → Outils de développement → YAML → Vérifier la configuration → Recharger.

---

## 3. Quel capteur utiliser

| Usage | Capteur |
|---|---|
| Affichage instantané, dashboard | `sensor.capteur_irradiance_id_40_irradiance` |
| **Pilotage, automatisations** | `sensor.irradiance_lissee` |

L'irradiance est très bruitée par temps variable : un passage nuageux fait chuter la valeur brute de plusieurs centaines de W/m² en quelques secondes. Une automatisation branchée sur le brut ferait cycler l'équipement piloté.

**Toujours utiliser le lissé pour toute décision.**

---

## 4. Historique — pourquoi pas MQTT

Un capteur MQTT lisant directement `santuario/irradiance/raw` a été mis en place le 24/07/2026, puis retiré le jour même : l'intégration Victron exposait déjà la même mesure.

**Comparaison des deux chemins :**

| Critère | Victron | MQTT direct |
|---|---|---|
| Configuration | aucune | package à maintenir |
| Longueur du chemin | Pi5 → Venus → HA | Pi5 → HA |
| Fraîcheur | cycle Venus + polling HA | plusieurs msg/min |
| Dépendance | Venus OS | broker Mosquitto |
| Cohérence | avec les autres entités Victron | source primaire |

**Arbitrage :** la fréquence du MQTT (plusieurs messages par minute) est très supérieure au besoin pour une donnée d'irradiance destinée à piloter un chauffe-eau. Un capteur de moins à maintenir est un capteur de moins qui casse.

> Le chemin MQTT reste pertinent pour un capteur du Pi5 que Venus OS n'exposerait pas. La méthode est conservée en annexe.

---

## 5. Annexe — méthode MQTT pour les futurs capteurs du Pi5

À utiliser pour toute donnée publiée par le Rust et absente de Venus OS.

### 5.1 Broker

| Paramètre | Valeur |
|---|---|
| Hôte | `192.168.1.141` (Pi5) |
| Port | `1883` |
| Protocole MQTT | `5` |
| Authentification | aucune (accès anonyme sur LAN) |

HA se connecte au broker distant en **client**. Pas de broker local, pas de pont.

### 5.2 Modèle de capteur

```yaml
mqtt:
  sensor:
    - name: "Nom du capteur"
      unique_id: santuario_xxx
      state_topic: "santuario/xxx/raw"
      unit_of_measurement: "unite"
      device_class: xxx
      state_class: measurement
      value_template: "{{ value | int(0) }}"
      expire_after: 120
      device:
        identifiers: santuario_pi5_capteurs
        name: "Capteurs Santuario"
        manufacturer: "Santuario"
        model: "Pi5 / Rust"
```

| Élément | Raison |
|---|---|
| `unique_id` | **Indispensable** pour le rattachement à un appareil |
| Bloc `device` | Crée l'appareil « Capteurs Santuario ». Sans lui, l'entité reste isolée. Réutiliser le même `identifiers` regroupe automatiquement les capteurs |
| `expire_after` | Les topics du Rust sont en `retain=false` : aucune valeur au démarrage de HA. Passe en `unavailable` si la source se tait — détection de panne |
| `value_template` avec `int` | Les payloads sont en texte brut, pas en JSON |

Ajouter un `time_throttle` si la publication dépasse quelques messages par minute.

### 5.3 Diagnostic MQTT

**Vérifier que HA reçoit :** Paramètres → Appareils et services → Intégrations → carte MQTT → « Configurer » → section **« Écouter un sujet »** → saisir le topic → « Commencer à écouter ».

> C'est le seul moyen de vérifier l'écoute côté HA. Les journaux ne montrent pas le trafic MQTT, uniquement les erreurs de connexion.

**Vérifier que le broker publie**, depuis le Pi5 :

```bash
mosquitto_sub -h localhost -t 'santuario/#' -v    # tout l'arbre santuario
mosquitto_sub -h localhost -t '#' -v              # tout le trafic
```

Ce test isole le broker de HA.

**Informations de débogage d'un appareil MQTT :** Paramètres → Appareils et services → Appareils → sélectionner l'appareil → ⋮ → Informations de débogage. Affiche les topics souscrits et les 10 derniers messages reçus.

**Message `Error returned from MQTT server: The connection was lost`** — apparaît lors d'un redémarrage du Pi5 (arrêt de Mosquitto). Sans gravité, HA se reconnecte. Une occurrence isolée est normale ; une répétition continue indiquerait un vrai problème.

---

## 6. Points de vigilance

### 6.1 Documentation Rust périmée

La documentation `app-energy-manager` du dépôt `Daly-BMS-Rust` indique que `santuario/irradiance/raw` serait *souscrit* mais jamais traité (dead code), et que la source réelle serait le polling HTTP.

**Ce n'est pas exact au 24/07/2026 :** le topic est bien **publié** et alimenté en continu, vérifié par écoute directe (valeur 1016 W/m² à 14h02). La note est à corriger dans le dépôt Rust.

### 6.2 Plage de validité

Le Rust valide la mesure dans `0.0..=2000.0` W/m². Hors plage, la valeur est tout de même écrite dans `EnergyState` mais l'événement WebSocket n'est pas émis. Côté HA, aucun filtrage n'est appliqué — à ajouter si des valeurs aberrantes apparaissent.

### 6.3 Doublon d'entités

Si le package MQTT est recréé un jour, il produira un second capteur pour la même mesure. Vérifier avant toute création qu'aucune entité Victron ne couvre déjà le besoin.

---

## 7. Suite prévue

**Pilotage du chauffe-eau LG ThinQ.** L'irradiance lissée servira de critère d'anticipation : contrairement à la puissance PV instantanée, elle permet de distinguer un ensoleillement durable d'une éclaircie passagère. À croiser avec le SOC batterie et l'excédent solaire.

---

## 8. Références

| Sujet | URL |
|---|---|
| Plateforme Filter | https://www.home-assistant.io/integrations/filter/ |
| Intégration Victron | https://www.home-assistant.io/integrations/victron_remote_monitoring/ |
| Intégration MQTT HA | https://www.home-assistant.io/integrations/mqtt/ |
| Dépôt energymanager | https://github.com/thieryus007-cloud/Daly-BMS-Rust |
| Dépôt HA | https://github.com/thieryus007-cloud/HA-Santuario |

---

*Document rédigé pour le projet Santuario — 24 juillet 2026.*
