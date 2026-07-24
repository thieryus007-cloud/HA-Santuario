# Pilotage des micro-onduleurs DEYE en surproduction

> **Statut :** 🟢 Test validé le 24/07/2026 — implémentation HA à réaliser
> **Date :** 24 juillet 2026
> **Installation :** Santuario, Badalucco (Liguria)
> **Documents liés :** `INTEGRATION-DEYE-SOLARMAN-HA.md`

---

## 1. Problème traité

En surproduction (batteries pleines, MPPT en Float/Storage), l'excédent PV des micro-onduleurs DEYE doit être écrêté.

**Mécanisme primaire, validé depuis février–mars 2026 :** lorsque le Victron monte en fréquence, les DEYE se coupent. Pas toujours brusquement, mais ils se coupent. Ce comportement est établi et fonctionne sans aucun logiciel.

**Surcouche ajoutée ensuite :** coupure du relais Shelly pilotée par l'`energymanager`, soit 3720 W qui disparaissent instantanément puis reviennent instantanément après le délai de restauration.

Conséquences de la surcouche relais :

- à-coups sur la MultiPlus-II à chaque transition ;
- overshoot de fréquence lors des reconnexions ;
- logique de régulation implantée dans un projet dont ce n'est pas le périmètre.

**Objectif :** passer d'un écrêtage tout-ou-rien à un écrêtage proportionnel, avec la logique centralisée dans Home Assistant.

> ⚠️ **Cadrage.** Le bridage `Active Power Regulation` est un **confort de régulation**, pas une nécessité de sécurité. Le filet fréquence fonctionne depuis cinq mois et reste le socle.

---

## 2. Existant

### 2.1 Chaîne matérielle

```
PV 9,3 kWc ──> MPPT 250/100 + 150/35 ──> Bus DC 48 V ──> Batteries Daly (320 + 360 Ah)
                                              │
                                       MultiPlus-II 48/5000/70
                                              │
                                          AC Out 1
                                              │
                                ┌─────────────┴─────────────┐
                          Shelly Pro 2PM (2 canaux)
                                ├── canal 1 ──> DEYE .250 (S/N 3871081176)
                                └── canal 2 ──> DEYE .251 (S/N 3867806531)
```

### 2.2 Réglages fréquence en place

| Élément | Paramètre | Valeur |
|---|---|---|
| Victron — Assistant *PV Inverter Support* | Début réduction | 50.30 Hz |
| | Puissance minimale atteinte à | 51.00 Hz |
| | Déconnexion au-dessus de | 51.50 Hz |
| | PV inverter installé | 3720 W |
| | PV panel installé | 5580 W |
| | PSMax / droop | 2400 W / 1.20 % |
| | PCMax / droop | 1250 W / 2.40 % |
| Victron — Grid / CEI | Over frequency (trip réseau) | 55 Hz |
| | Under frequency (trip réseau) | 45 Hz |
| DEYE (Modbus) | Grid Frequency Upper Limit | **51.5 Hz** |
| | Grid Frequency Lower Limit | 47.5 Hz |
| | Grid Voltage Lower / Upper | 184 V / 287.5 V |
| | Over-Frequency Load Reduction | ✅ activé *(23/07/2026)* |
| | Point de réduction | 50.6 Hz *(23/07/2026)* |
| | Taux de réduction | 71 % |
| | Island Protection | ❌ désactivé — **volontaire** |
| | RISO | ⚠️ voir §7.3 — **anomalie sur le `.251`** |
| | Soft Start | ⚠️ transitoire, voir §7.1 |
| | Self-check time | 65 s |
| | Active Power Regulation | ✅ **fonctionnel, plage 1–100 %** |

### 2.3 Logique logicielle actuelle (à neutraliser)

`Daly-BMS-Rust`, crate `energymanager`, module `logic/deye_command/mod.rs`, `Config.toml` :

```toml
[energy_manager.deye]
freq_high_hz         = 51.0
freq_hard_hz         = 51.3
cut_delay_secs       = 3
reenable_delay_secs  = 45
relay_resync_secs    = 60
mppt_cut_enabled     = true
mppt_full_states     = [4, 5, 6]
input_max_age_secs   = 90
```

### 2.4 Infrastructure

| Hôte | Rôle actuel |
|---|---|
| Pi5 `192.168.1.141` | BMS Daly (CAN), RS485, reDB (Rust), Grafana, Mosquitto, `energymanager` |
| NanoPi `192.168.1.120` | Venus OS — GX master |
| Mac Mini M4 | HAOS en VM VMware Fusion — `192.168.1.10` |
| DEYE loggers | `.250` / `.251`, TCP-Server port 8889, **1 seule connexion TCP simultanée** |

> InfluxDB a été retiré du Pi5. Grafana lit reDB. Migration de Grafana vers le Mac Mini envisagée.

### 2.5 Intégration Solarman — vérifié le 23/07/2026

| Point | Constat |
|---|---|
| Composant | `davidrapan/ha-solarman` **v25.08.16** installé via HACS |
| Statut affiché | « Intégration personnalisée qui remplace un composant Core » |
| Résultat | 2 appareils × 55 entités = 110 entités |
| Socle technique | `pysolarmanv5` asynchrone, Modbus TCP |

**Entités de pilotage confirmées :**

| Entité | Type | Rôle |
|---|---|---|
| `number.micro_inverter_250_active_power_regulation` | `number` | Bridage 1–100 % |
| `number.micro_inverter_251_active_power_regulation` | `number` | Bridage 1–100 % |
| `switch.microinverter_250` | `switch` | Marche/arrêt Modbus |
| `switch.microinverter_251` | `switch` | Marche/arrêt Modbus |

**Emplacement des profils :** `/config/custom_components/solarman/inverter_definitions/deye_micro.yaml`, côté HA Core.

⚠️ L'add-on « Terminal & SSH » est **cloisonné** : son `/config` pointe vers son propre `/homeassistant`, qui ne contient que `hacs`. Pour lire ces fichiers, utiliser **File editor** ou **Studio Code Server**, ou télécharger les diagnostics de l'intégration.

**Historique :** l'ancien fork `StephanJoubert/home_assistant_solarman` était encore actif le 22/07/2026 à 19 h (chargement de `deye_4mppt.yaml`, boucle de `NoSocketAvailableError`). Remplacé depuis. Les logs antérieurs ne reflètent pas la configuration actuelle.

---

## 3. Cible

### 3.1 Principe

| Couche | Mécanisme | Rôle | Dépendance logicielle |
|---|---|---|---|
| **1 — Filet matériel** | Auto-trip DEYE 51.5 Hz + droop Victron | Protection ultime — **validé en production** | **aucune** |
| **2 — Régulation** | `number.*_active_power_regulation` écrit par HA | Écrêtage proportionnel 1–100 % | HA |
| **3 — Arrêt** | `switch.microinverter_*` (Modbus) | Arrêt propre en Storage | HA |
| **4 — Coupure physique** | Shelly Pro 2PM | Intervention / maintenance uniquement | manuel (HA ou VRM) |

La couche 1 fonctionne depuis février 2026 sans logiciel. C'est le socle, quel que soit l'état des couches supérieures.

**Le Shelly sort de la boucle de régulation.** Le switch Modbus le remplace : il éteint l'onduleur en respectant sa rampe interne, donc sans à-coup sur la MultiPlus.

### 3.2 Matrice de pilotage

| État MPPT | Code | Switch | Active Power Regulation | Puissance ≈ par onduleur |
|---|---|---|---|---|
| Bulk | 3 | ON | **100 %** | pleine puissance |
| Absorption | 4 | ON | **40 %** | ~745 W |
| Float | 5 | ON | **15 %** | ~280 W |
| Storage | 6 | **OFF** | — | 0 W |

Soit pour les deux DEYE : ~1490 W en Absorption, ~560 W en Float, 0 W en Storage.

### 3.3 Répartition des rôles

| Composant | Rôle cible |
|---|---|
| **Pi5 / `energymanager`** | BMS Daly, RS485, reDB, Grafana. Publication MQTT : fréquence AC, état MPPT, SOC. **Plus aucune décision DEYE.** |
| **Home Assistant** | Toute la logique. Seuils en `input_number` modifiables depuis l'UI. Écriture Modbus (number + switch). |
| **Shelly Pro 2PM** | Coupure physique avant intervention. Pilotable à distance via HA ou VRM Victron. **Hors boucle de régulation.** |
| **DEYE** | Auto-trip 51.5 Hz + Over-Frequency Load Reduction. Filet autonome. |
| **Victron** | Assistant PV Inverter Support inchangé. |

### 3.4 Justification du choix HA plutôt que Pi5

| Critère | Pi5 | HA | Retenu |
|---|---|---|---|
| Disponibilité constatée | arrêt ~1×/mois | watchdog LaunchAgent + auto-restart validés | HA |
| Modification d'un seuil | recompile + redéploiement | `input_number` dans l'UI | HA |
| Ajout d'un micro-onduleur | code + `Config.toml` + topic MQTT + rebuild | entrée d'intégration | HA |
| Périmètre du projet | `Daly-BMS-Rust` = batteries — dérive de périmètre | pilotage énergétique = rôle natif | HA |
| Remontée d'informations | à instrumenter | 110 entités déjà disponibles | HA |

### 3.5 Schéma cible

```
   Pi5 (energymanager)                    Home Assistant
   ├── BMS Daly / CAN                     ├── Intégration Solarman (110 entités)
   ├── RS485                              ├── Intégration Shelly (native)
   ├── reDB ──> Grafana                   ├── input_number (seuils)
   └── MQTT ──────────────────────────>   └── Automatisation
       freq AC / MPPT state / SOC                     │
                                            ┌─────────┴─────────┐
                                    number.set_value    switch on/off
                                            │                   │
                                  ┌─────────┴─────────┬─────────┴────────┐
                              DEYE .250          DEYE .251
                                  │                   │
                            auto-trip 51.5 Hz (indépendant)
```

---

## 4. Résultats du test — 24 juillet 2026

### 4.1 Verdict

**✅ Le registre `Active Power Regulation` est fonctionnel en écriture, avec effet réel mesuré sur la production.**

| Champ | Valeur |
|---|---|
| Date | 24/07/2026, 8 h 35 – 9 h 25 |
| Onduleur testé | `.251` (S/N 3867806531) |
| Production initiale | ~750 W |
| Consignes testées | 100 % → 22 % → 100 % → 1 % → 100 % |
| Écriture acceptée | ✅ |
| Effet réel | ✅ confirmé |
| Plancher atteignable | **1 %** — jamais 0 |
| Registre déduit | **40 (`0x0028`)** — signature du plancher à 1 % |
| Persistance au redémarrage | ✅ **testée et confirmée** |
| Switch Modbus | ✅ fonctionnel, extinction en 2 paliers |
| **Décision** | **Cible partielle validée** — bridage 1–100 % + switch pour l'arrêt total |

### 4.2 Séquence observée (`.251`)

| Heure | Consigne | Puissance | Observation |
|---|---|---|---|
| ~8h39 | 100 → **22 %** | 750 W | écriture acceptée |
| 8h39–8h50 | 22 % | 750 → 670 → 400 → 150 W | **descente par paliers** |
| ~8h50 | 22 → 100 → **1 %** | | deux écritures rapprochées |
| 8h51–8h58 | 1 % | ~150 W | plancher |
| ~8h58 | 1 → **100 %** | 400 → 860 → 930 W | remontée par paliers |

Chaque changement de puissance suit une écriture de consigne avec un décalage constant — la causalité est établie.

### 4.3 Comportement en paliers — contrainte structurante

L'onduleur **n'applique pas la consigne instantanément**. Il progresse par marches successives vers la cible.

| Mesure | Valeur observée |
|---|---|
| Durée d'un palier | **2,5 à 3 minutes** |
| Nombre de paliers (descente 100 → 22 %) | 4 |
| Durée totale d'une transition complète | **~10 à 12 minutes** |

**Conséquences pour l'implémentation :**

1. **Aucune rampe logicielle.** L'onduleur a la sienne ; en ajouter une serait contre-productif.
2. **Écrire directement la consigne cible.** Une seule écriture par changement d'état MPPT.
3. **Ne pas réécrire pendant une transition.** Prévoir une temporisation d'au moins 5 minutes entre deux écritures sur le même onduleur.
4. **Ne pas attendre d'effet immédiat** lors des tests ou du diagnostic.

### 4.4 Plancher à 1 % — le switch prend le relais

Le registre 40 ne descend pas sous 1 %, soit ~19 W par onduleur (~37 W au total). Insuffisant pour un arrêt réel en Storage.

**Solution retenue :** `switch.microinverter_*`, exposé par Solarman. Testé le 24/07 : extinction en **2 paliers**, donc en respectant la rampe interne. Pas d'à-coup sur la MultiPlus, pas de décrochage brutal, pas de coupure d'alimentation du logger.

C'est un actionneur strictement meilleur que le relais Shelly pour cet usage : le logger reste alimenté, HA garde sa connexion TCP, et l'état est cohérent au retour.

### 4.5 Défaut `DC Bus OverVoltage` — à surveiller

Le `.251` a remonté un `Device Fault: DC Bus OverVoltage` à **08:58:20**, précisément au retour de 1 % à 100 %.

**Mécanisme probable :** onduleur bridé à 1 %, le MPPT amont continue de produire, la tension du bus DC monte faute de débit côté AC.

**Règles à appliquer :**

- éviter les consignes très basses **prolongées** en pleine production ;
- pour un arrêt réel, préférer le **switch OFF** au bridage à 1 % ;
- si le défaut se répète en Float (15 %), remonter la consigne à 20–25 %.

### 4.6 Autres constats

**Échelle du registre :** l'UI affiche des pourcentages entiers (22 %, 1 %, 100 %) et l'écriture depuis `number.set_value` fonctionne avec ces mêmes valeurs. **Aucune conversion à faire côté HA** — l'intégration gère le `scale`.

**Valeurs intermédiaires observées :** l'activité HA du `.251` montre `22,2 %` et `22,1 %` — l'onduleur renvoie sa valeur appliquée avec une décimale, légèrement différente de la consigne. Normal, ne pas s'en inquiéter ; en tenir compte dans les comparaisons (utiliser `| round(0)` ou une tolérance).

---

## 5. Préalable à l'implémentation — neutraliser la logique Rust

> ⚠️ **À faire AVANT d'activer les automatisations HA.**

Faire tourner les deux systèmes en parallèle crée un conflit direct : l'`energymanager` coupe le relais Shelly, ce qui coupe l'alimentation du logger ; HA perd sa connexion TCP, ses écritures échouent, et l'état du switch devient incohérent avec ce que HA croit.

### 5.1 Neutralisation par configuration (réversible)

Dans `Config.toml` sur le Pi5 :

```toml
[energy_manager.deye]
mppt_cut_enabled = false      # supprime la coupure sur etat MPPT
freq_high_hz     = 99.0       # seuil hors plage : plus de coupure frequence
freq_hard_hz     = 99.0
```

Le code reste en place, le service tourne, **la publication MQTT continue**. Retour arrière par simple restauration du fichier.

### 5.2 Redémarrage et vérifications

Redémarrage complet du Pi5.

**Après le reboot, contrôler impérativement :**

| Point | Où | Attendu |
|---|---|---|
| État des 2 canaux Shelly | HA — intégration Shelly | **ON** — sinon HA piloterait un onduleur non alimenté |
| Publication MQTT | HA — `sensor.mppt_state` | valeur fraîche, non `unavailable` |
| Connexion Solarman | HA — les 110 entités | pas de `Timeout fetching` |
| Absence de coupure DEYE | historique de puissance | production continue |

Le filet reste assuré par l'**auto-trip DEYE à 51.5 Hz**, indépendant des deux systèmes.

---

## 6. Implémentation — Home Assistant

### 6.1 Seuils configurables

`configuration.yaml` :

```yaml
input_number:
  deye_power_bulk:
    name: "DEYE - puissance en Bulk"
    min: 1
    max: 100
    step: 5
    initial: 100
    unit_of_measurement: "%"
  deye_power_absorption:
    name: "DEYE - puissance en Absorption"
    min: 1
    max: 100
    step: 5
    initial: 40
    unit_of_measurement: "%"
  deye_power_float:
    name: "DEYE - puissance en Float"
    min: 1
    max: 100
    step: 5
    initial: 15
    unit_of_measurement: "%"

input_boolean:
  deye_regulation_enabled:
    name: "DEYE - regulation active"
    initial: on
```

> `min: 1` et non 0 — le registre 40 ne descend pas sous 1 % (§4.4). L'état Storage passe par le switch, pas par une consigne.

### 6.2 Watchdog de fraîcheur MQTT

Équivalent HA de `input_max_age_secs = 90` :

```yaml
template:
  - binary_sensor:
      - name: "Pi5 telemetrie perimee"
        unique_id: pi5_telemetrie_perimee
        device_class: problem
        state: >
          {{ (as_timestamp(now())
              - as_timestamp(states.sensor.mppt_state.last_changed, 0)) > 90 }}
```

### 6.3 Consigne cible

```yaml
template:
  - sensor:
      - name: "DEYE consigne cible"
        unique_id: deye_target_power
        unit_of_measurement: "%"
        state: >
          {% if not is_state('input_boolean.deye_regulation_enabled','on') %}
            100
          {% elif states('sensor.mppt_state') in ['unknown','unavailable'] %}
            100
          {% elif is_state('binary_sensor.pi5_telemetrie_perimee','on') %}
            100
          {% else %}
            {% set s = states('sensor.mppt_state') | int(3) %}
            {% if   s == 4 %}{{ states('input_number.deye_power_absorption') | int }}
            {% elif s == 5 %}{{ states('input_number.deye_power_float')      | int }}
            {% elif s == 6 %}1
            {% else %}       {{ states('input_number.deye_power_bulk')       | int }}
            {% endif %}
          {% endif %}

      - name: "DEYE switch cible"
        unique_id: deye_target_switch
        state: >
          {% if not is_state('input_boolean.deye_regulation_enabled','on') %}
            on
          {% elif states('sensor.mppt_state') in ['unknown','unavailable'] %}
            on
          {% elif is_state('binary_sensor.pi5_telemetrie_perimee','on') %}
            on
          {% elif states('sensor.mppt_state') | int(3) == 6 %}
            off
          {% else %}
            on
          {% endif %}
```

> **Repli sécurisé :** régulation désactivée, état MPPT indisponible, ou télémétrie Pi5 périmée → **100 % et switch ON**. Jamais de bridage ni de coupure sur une donnée douteuse.

### 6.4 Application de la consigne

**Une seule écriture par changement d'état.** Pas de rampe, pas de resync périodique (§4.3).

```yaml
automation:
  - alias: "DEYE - appliquer la consigne de puissance"
    id: deye_apply_power
    mode: single
    max_exceeded: silent
    trigger:
      - platform: state
        entity_id: sensor.deye_consigne_cible
      - platform: homeassistant
        event: start
    condition:
      - condition: template
        value_template: >
          {{ states('sensor.deye_consigne_cible') not in ['unknown','unavailable'] }}
      - condition: template
        value_template: >
          {{ (states('number.micro_inverter_250_active_power_regulation') | float(-1) | round(0))
             != (states('sensor.deye_consigne_cible') | int(100)) }}
    action:
      - service: number.set_value
        target:
          entity_id:
            - number.micro_inverter_250_active_power_regulation
            - number.micro_inverter_251_active_power_regulation
        data:
          value: "{{ states('sensor.deye_consigne_cible') | int(100) }}"
      - delay:
          minutes: 5          # laisse la rampe interne se terminer (§4.3)

  - alias: "DEYE - appliquer l'etat marche/arret"
    id: deye_apply_switch
    mode: single
    max_exceeded: silent
    trigger:
      - platform: state
        entity_id: sensor.deye_switch_cible
      - platform: homeassistant
        event: start
    condition:
      - condition: template
        value_template: >
          {{ states('sensor.deye_switch_cible') in ['on','off'] }}
      - condition: template
        value_template: >
          {{ states('switch.microinverter_250') != states('sensor.deye_switch_cible') }}
    action:
      - service: "switch.turn_{{ states('sensor.deye_switch_cible') }}"
        target:
          entity_id:
            - switch.microinverter_250
            - switch.microinverter_251
      - delay:
          minutes: 5          # extinction/allumage en 2 paliers (§4.4)
```

> - `mode: single` + `max_exceeded: silent` : un déclenchement pendant le `delay` est ignoré, ce qui protège contre les écritures rapprochées.
> - `| round(0)` sur la comparaison : l'onduleur renvoie une décimale (§4.6).
> - Le `delay` de 5 min couvre les 2,5–3 min de palier avec marge.

### 6.5 Ordre d'implémentation

1. Neutraliser la logique Rust (§5) et redémarrer le Pi5.
2. Vérifier les 4 points de contrôle §5.2.
3. Créer les `input_number` et `input_boolean` — recharger la configuration.
4. Créer les template sensors — vérifier leurs valeurs dans Outils de développement → États.
5. **Créer les automatisations en les laissant désactivées.**
6. Vérifier manuellement que `sensor.deye_consigne_cible` et `sensor.deye_switch_cible` suivent bien l'état MPPT réel pendant une journée.
7. Activer d'abord l'automatisation de puissance. Observer une journée complète.
8. Activer ensuite l'automatisation de switch.

### 6.6 Entités à confirmer

| Entité | État |
|---|---|
| `number.micro_inverter_250_active_power_regulation` | ⬜ à confirmer (le `_251_` est vérifié) |
| `number.micro_inverter_251_active_power_regulation` | ✅ vérifié |
| `switch.microinverter_250` | ⬜ à confirmer |
| `switch.microinverter_251` | ✅ vérifié |
| `sensor.mppt_state` | ⬜ **nom réel du topic MQTT publié par le Pi5 — à confirmer** |

---

## 7. Points de vigilance

### 7.1 Soft Start — réglage transitoire

Tant que la restauration passe par le relais, chaque reconnexion renvoie 3720 W instantanément sur la MultiPlus. Soft Start amortit cette montée.

**Une fois le switch Modbus en service, repasser Soft Start à OFF** : le switch respecte déjà la rampe interne ; empiler Soft Start rendrait le temps de montée imprévisible.

### 7.2 Island Protection — désactivé volontairement

Les DEYE sont sur AC Out 1, derrière la MultiPlus. Il n'y a pas de réseau au sens où l'entend le DEYE. Un anti-îlotage actif interpréterait la référence AC de la MultiPlus comme un réseau instable et provoquerait des décrochages intempestifs. **Configuration standard en AC-couplé derrière Victron — ne pas modifier.**

**Conséquence sécurité :** aucune protection active contre l'îlotage. Toute intervention sur l'AC Out 1 se fait après coupure **et** vérification d'absence de tension au multimètre. Ne jamais se fier au seul disjoncteur ouvert : les DEYE peuvent maintenir une tension résiduelle le temps de leur décrochage passif (sous-tension 184 V / sous-fréquence 47.5 Hz).

Le Shelly Pro 2PM, pilotable à distance via VRM Victron, est le moyen de coupure privilégié avant intervention.

### 7.3 RISO — ⚠️ anomalie sur le `.251`

**Constat du 24/07/2026 :**

| Onduleur | Comportement |
|---|---|
| `.250` | RISO activé, **reste activé** |
| `.251` | RISO activé, **se désactive automatiquement** |

**Interprétation.** Le seul mécanisme expliquant une auto-désactivation est une **mesure d'isolement échouée au démarrage** : l'onduleur teste, la résistance PV/terre est sous le seuil, et ce firmware bascule la protection sur OFF plutôt que de refuser de démarrer.

**Hypothèse : défaut d'isolement réel sur le string du `.251`** — humidité dans un MC4, câble blessé, connecteur mal serti, boîte de jonction infiltrée. Le `.250`, sur le même site et dans les mêmes conditions, ne présente pas le problème : cela **exclut une cause environnementale globale**.

Le `.251` est également celui qui a remonté le `DC Bus OverVoltage` (§4.5). Lien non établi, mais deux anomalies sur le même onduleur méritent d'être notées.

**Actions — sans urgence, mais à ne pas oublier :**

1. Mesure de la résistance d'isolement PV+/terre et PV−/terre au **mégohmmètre** sur le string du `.251`, hors production. Attendu : > 1 MΩ, idéalement bien au-delà.
2. Inspection visuelle des MC4 et de la boîte de jonction côté `.251`.
3. **Comparer avec la mesure du `.250`** — l'écart sera plus parlant que la valeur absolue.

Si la mesure est bonne, chercher ailleurs (version de firmware, bug). Si elle est mauvaise, **RISO fait son travail et ne doit surtout pas être forcé**.

En vallée ligure (humidité, écarts thermiques), c'est exactement le défaut attendu. Ne jamais désactiver RISO pour faire taire le symptôme.

### 7.4 Contrainte du slot TCP unique

**Un seul client TCP par logger DEYE.** HA est le client unique. Interdits pendant le fonctionnement normal :

- script `pysolarmanv5` sur le Pi5 ;
- application mobile Solarman en local ;
- `Remote Server A` (cloud Solarman) actif ;
- tests `nc` répétés.

`Remote Server B` (`192.168.1.10:502`, vestige de la configuration TCP-Client) : **à vider sur les deux loggers** s'il ne l'est pas déjà.

**Corollaire du choix du switch Modbus :** contrairement au relais Shelly, le switch ne coupe pas l'alimentation du logger. La session TCP de HA survit à l'extinction de l'onduleur — c'est un avantage structurel.

### 7.5 Bug de déchargement de l'intégration

Log du 22/07/2026 : `KeyError: 'solarman'` lors du déchargement des deux entrées.

**Conséquence :** ne pas désactiver une entrée d'intégration pour libérer le slot TCP — le déchargement peut échouer et laisser une session pendante. Préférer un **redémarrage complet de HA**.

### 7.6 Ajout futur de micro-onduleurs

Même modèle SUN-M200G4-EU-Q0, même AC Out 1, pas dans un avenir proche. À l'ajout :

1. Mettre à jour l'assistant *PV Inverter Support* : `Total installed PV inverter power` (actuellement 3720 W) et `Total installed PV panel power` (5580 W).
2. Vérifier la **règle du facteur 1.0** : la puissance PV AC-couplée ne doit pas dépasser la puissance nominale de la MultiPlus (5000 VA). Avec 2 DEYE on est à 3720 W ; un 3ᵉ porterait à 5580 W, **au-delà de la limite**. Un 3ᵉ micro-onduleur impose une réévaluation complète, pas un simple ajout.
3. Côté HA : une entrée d'intégration supplémentaire, ajout des entités dans les listes `target` de §6.4.

### 7.7 Demande faite à DEYE (52.00 / 52.80 Hz)

Demande ancienne (> 8 mois), jamais appliquée. **Incompatible avec la configuration actuelle** : la MultiPlus ne monte pas au-delà de 51.50 Hz avec l'assistant en place. Si ce firmware était appliqué, les DEYE ne décrocheraient jamais par fréquence et le filet matériel disparaîtrait.

**Action : confirmer auprès de DEYE que cette demande est annulée.**

### 7.8 Version de l'intégration

v25.08.16 (août 2025), installée via HACS. Le dépôt a une activité continue. Avant toute mise à jour, vérifier que le profil `deye_micro.yaml` n'a pas changé de registre.

**Piste d'amélioration :** la demande #3354 (avril 2026, non répondue) porte sur l'exposition du **registre 53 (`0x0035`)**, qui accepte le 0 % — contrairement au registre 40 utilisé actuellement. S'il devenait disponible, il pourrait remplacer le switch pour l'état Storage. Non prioritaire : le switch fait le travail.

---

## 8. Feuille de route

| # | Action | État | Dépend de |
|---|---|---|---|
| 1 | Activer Over-Frequency Load Reduction sur les 2 DEYE | ✅ 23/07/2026 | — |
| 2 | Point de réduction à 50.6 Hz | ✅ 23/07/2026 | — |
| 3 | Test `Active Power Regulation` | ✅ **validé 24/07/2026** | — |
| 4 | Test du switch Modbus | ✅ **validé 24/07/2026** | — |
| 5 | Test de persistance au redémarrage | ✅ **validé 24/07/2026** | — |
| 6 | Activer Soft Start sur les 2 DEYE (transitoire) | ⬜ à faire | — |
| 7 | Vider `Remote Server B` sur les 2 loggers | ⬜ à vérifier | — |
| 8 | Confirmer annulation de la demande DEYE 52.00/52.80 Hz | ⬜ à faire | — |
| 9 | Confirmer le nom du topic MQTT `mppt_state` | ⬜ **bloquant §6** | — |
| 10 | Neutraliser la logique Rust + reboot Pi5 (§5) | ⬜ **préalable** | — |
| 11 | Vérifier les 4 points de contrôle §5.2 | ⬜ | 10 |
| 12 | Créer `input_number` + `input_boolean` | ⬜ | 11 |
| 13 | Créer les template sensors | ⬜ | 12 |
| 14 | Créer les automatisations (désactivées) | ⬜ | 13 |
| 15 | Observation des consignes calculées — 1 journée | ⬜ | 14 |
| 16 | Activer l'automatisation de puissance | ⬜ | 15 |
| 17 | Activer l'automatisation de switch | ⬜ | 16 |
| 18 | Désactiver Soft Start | ⬜ | 17 |
| 19 | Supprimer le code DEYE du Rust — Claude Code + GitHub | ⬜ | 17 + 2 semaines |
| 20 | **Mesure d'isolement du string `.251`** (§7.3) | ⬜ | — |

---

## 9. Références

| Sujet | URL |
|---|---|
| Intégration Solarman utilisée | https://github.com/davidrapan/ha-solarman |
| Wiki — Custom Sensors | https://github.com/davidrapan/ha-solarman/wiki/Custom-Sensors |
| Wiki — Supported Devices | https://github.com/davidrapan/ha-solarman/wiki/Supported-Devices |
| Demande #3354 — registre 53 sur SUN-M200G4 | https://github.com/orgs/home-assistant/discussions/3354 |
| Écriture non persistée (ioBroker #88) | https://github.com/raschy/ioBroker.deyeidc/issues/88 |
| Implémentation de référence (AT + MQTT) | https://github.com/kbialek/deye-inverter-mqtt |
| Rampe interne lente (forum DIY Solar) | https://diysolarforum.com/threads/controlling-deye-micro-inverter-via-modbus-using-python-script.106237/ |
| Bibliothèque Python | https://pypi.org/project/pysolarmanv5/ |
| Dépôt energymanager | https://github.com/thieryus007-cloud/Daly-BMS-Rust |
| Dépôt HA | https://github.com/thieryus007-cloud/HA-Santuario |

---

*Document rédigé pour le projet Santuario — 24 juillet 2026.*
