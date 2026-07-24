# Pilotage des micro-onduleurs DEYE en surproduction

> **Statut :** 🟢 Test validé 24/07/2026 — implémentation prête, mise en service à réaliser
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
| | Over-Frequency Load Reduction | ✅ activé — 50.6 Hz, taux 71 % *(23/07/2026)* |
| | Island Protection | ❌ désactivé — **volontaire** (§7.2) |
| | RISO | ⚠️ `.250` = ON, `.251` = **OFF** — anomalie (§7.3) |
| | Soft Start | ✅ ON sur les deux — transitoire (§7.1) |
| | GFDI | OFF sur les deux |
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

**Emplacement des profils :** `/config/custom_components/solarman/inverter_definitions/deye_micro.yaml`, côté HA Core.

⚠️ L'add-on « Terminal & SSH » est **cloisonné** : son `/config` pointe vers son propre `/homeassistant`, qui ne contient que `hacs`. Pour lire ces fichiers, utiliser **File editor** ou **Studio Code Server**, ou télécharger les diagnostics de l'intégration.

**Historique :** l'ancien fork `StephanJoubert/home_assistant_solarman` était encore actif le 22/07/2026 à 19 h (chargement de `deye_4mppt.yaml`, boucle de `NoSocketAvailableError`). Remplacé depuis. Les logs antérieurs ne reflètent pas la configuration actuelle.

### 2.6 Entités réelles — vérifiées par export du 24/07/2026

> ⚠️ Le préfixe est `micro_onduleurs_deye_microinverter_XXX_`, **pas** `micro_inverter_XXX_`.

**Pilotage DEYE :**

| Usage | Entité |
|---|---|
| Bridage `.250` | `number.micro_onduleurs_deye_microinverter_250_active_power_regulation` |
| Bridage `.251` | `number.micro_onduleurs_deye_microinverter_251_active_power_regulation` |
| Marche/arrêt `.250` | `switch.micro_onduleurs_deye_microinverter_250` |
| Marche/arrêt `.251` | `switch.micro_onduleurs_deye_microinverter_251` |

**Mesure et diagnostic :**

| Usage | Entité |
|---|---|
| Puissance AC `.250` | `sensor.micro_onduleurs_deye_microinverter_250_power` |
| Puissance AC `.251` | `sensor.micro_onduleurs_deye_microinverter_251_power` |
| Défaut `.250` | `sensor.micro_onduleurs_deye_microinverter_250_device_fault` |
| Défaut `.251` | `sensor.micro_onduleurs_deye_microinverter_251_device_fault` |
| RISO `.250` / `.251` | `switch.micro_onduleurs_deye_microinverter_2XX_riso` |
| Soft Start `.250` / `.251` | `switch.micro_onduleurs_deye_microinverter_2XX_soft_start` |

**État des MPPT — source de la décision :**

| MPPT | Entité |
|---|---|
| 250/100 | `sensor.smartsolar_mppt_ve_can_250_100_rev2_id_273_state` |
| 150/35 | `sensor.smartsolar_charger_mppt_150_35_id_289_state` |

> **Point important :** ces états sont des **chaînes** (`bulk`, `absorption`, `float`, `storage`), pas les codes numériques 3/4/5/6 du Rust.
>
> **Aucune entité MQTT publiée par le Pi5 n'existe dans HA.** La source est l'intégration Victron directement — ce qui supprime toute dépendance au Pi5 pour la décision.

---

## 3. Cible

### 3.1 Principe

| Couche | Mécanisme | Rôle | Dépendance logicielle |
|---|---|---|---|
| **1 — Filet matériel** | Auto-trip DEYE 51.5 Hz + droop Victron | Protection ultime — **validé en production** | **aucune** |
| **2 — Régulation** | `number.*_active_power_regulation` écrit par HA | Écrêtage proportionnel 1–100 % | HA |
| **3 — Arrêt** | `switch.micro_onduleurs_deye_microinverter_*` | Arrêt propre en Storage | HA |
| **4 — Coupure physique** | Shelly Pro 2PM | Intervention / maintenance uniquement | manuel (HA ou VRM) |

La couche 1 fonctionne depuis février 2026 sans logiciel. C'est le socle, quel que soit l'état des couches supérieures.

**Le Shelly sort de la boucle de régulation.** Le switch Modbus le remplace : il éteint l'onduleur en respectant sa rampe interne, donc sans à-coup sur la MultiPlus, et sans couper l'alimentation du logger.

### 3.2 Matrice de pilotage

| État MPPT consolidé | Switch | Active Power Regulation | Puissance ≈ par onduleur |
|---|---|---|---|
| Bulk | ON | **100 %** | pleine puissance |
| Absorption | ON | **40 %** | ~745 W |
| Float | ON | **15 %** | ~280 W |
| Storage | **OFF** | (1 %) | 0 W |

Soit pour les deux DEYE : ~1490 W en Absorption, ~560 W en Float, 0 W en Storage.

### 3.3 Règle de consolidation des MPPT

**L'état retenu est le plus avancé parmi tous les MPPT** — hiérarchie `bulk < absorption < float < storage`.

Justification : les MPPT chargent le même bus DC et voient la même tension batterie ; ils basculent donc quasi simultanément. Une divergence signale qu'un MPPT est limité par autre chose (ombrage, courant max), auquel cas sa lecture d'état est moins fiable que celle de l'autre. Si un MPPT considère la batterie pleine, elle l'est.

Le template balaie toutes les entités `sensor.smartsolar*_state` : **l'ajout d'un troisième MPPT est pris en compte sans modification du code.**

### 3.4 Répartition des rôles

| Composant | Rôle cible |
|---|---|
| **Pi5 / `energymanager`** | BMS Daly, RS485, reDB, Grafana. **Plus aucune décision DEYE.** |
| **Home Assistant** | Toute la logique. Décision à partir des états MPPT lus via l'intégration Victron. Seuils en `input_number` modifiables depuis l'UI. |
| **Shelly Pro 2PM** | Coupure physique avant intervention. Pilotable à distance via HA ou VRM. **Hors boucle de régulation.** |
| **DEYE** | Auto-trip 51.5 Hz + Over-Frequency Load Reduction. Filet autonome. |
| **Victron** | Assistant PV Inverter Support inchangé. Fournit les états MPPT à HA. |

### 3.5 Justification du choix HA plutôt que Pi5

| Critère | Pi5 | HA | Retenu |
|---|---|---|---|
| Disponibilité constatée | arrêt ~1×/mois | watchdog LaunchAgent + auto-restart validés | HA |
| Modification d'un seuil | recompile + redéploiement | `input_number` dans l'UI | HA |
| Ajout d'un micro-onduleur | code + `Config.toml` + topic MQTT + rebuild | entrée d'intégration | HA |
| Périmètre du projet | `Daly-BMS-Rust` = batteries — dérive de périmètre | pilotage énergétique = rôle natif | HA |
| Source des états MPPT | via Venus OS puis MQTT à instrumenter | intégration Victron native, déjà en place | HA |

### 3.6 Schéma cible

```
   Victron (intégration native)              Home Assistant
   ├── MPPT 250/100 state ──────────────>    ├── template : etat consolide
   ├── MPPT 150/35 state ───────────────>    ├── input_number (seuils)
   └── (MPPT futurs : automatique)           └── 2 automatisations
                                                       │
                                             ┌─────────┴─────────┐
                                     number.set_value    switch on/off
                                             │                   │
                                   ┌─────────┴─────────┬─────────┴────────┐
                               DEYE .250          DEYE .251
                                   │                   │
                             auto-trip 51.5 Hz (indépendant)

   Pi5 : BMS Daly, RS485, reDB, Grafana — hors boucle DEYE
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
3. **Ne pas réécrire pendant une transition.** D'où le `delay: minutes: 5` dans les automatisations.
4. **Ne pas attendre d'effet immédiat** lors des tests ou du diagnostic.

### 4.4 Plancher à 1 % — le switch prend le relais

Le registre 40 ne descend pas sous 1 %, soit ~19 W par onduleur (~37 W au total). Insuffisant pour un arrêt réel en Storage.

**Solution retenue :** `switch.micro_onduleurs_deye_microinverter_*`, exposé par Solarman. Testé le 24/07 : extinction en **2 paliers**, donc en respectant la rampe interne. Pas d'à-coup sur la MultiPlus, pas de décrochage brutal, pas de coupure d'alimentation du logger.

C'est un actionneur strictement meilleur que le relais Shelly pour cet usage : le logger reste alimenté, HA garde sa connexion TCP, et l'état est cohérent au retour.

### 4.5 Défaut `DC Bus OverVoltage`

Remonté par le `.251` à 08:58:20, au retour de 1 % à 100 %. **L'export du 24/07 montre que les deux onduleurs portent ce défaut** — ce n'est donc pas spécifique au `.251`.

**Mécanisme probable :** onduleur bridé bas, le MPPT amont continue de produire, la tension du bus DC monte faute de débit côté AC.

**Règles à appliquer :**

- éviter les consignes très basses **prolongées** en pleine production ;
- pour un arrêt réel, préférer le **switch OFF** au bridage à 1 % ;
- si le défaut se répète en Float (15 %), remonter la consigne à 20–25 % via l'`input_number`.

### 4.6 Échelle et valeurs renvoyées

**Échelle :** l'UI affiche des pourcentages entiers et l'écriture via `number.set_value` fonctionne avec ces mêmes valeurs. **Aucune conversion à faire côté HA** — l'intégration gère le `scale`.

**Décimales :** l'activité HA du `.251` montre `22,2 %` et `22,1 %` — l'onduleur renvoie sa valeur appliquée avec une décimale, légèrement différente de la consigne. D'où le `| round(0)` dans les conditions de comparaison.

---

## 5. Préalable à la mise en service — neutraliser la logique Rust

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

Le code reste en place, le service tourne. Retour arrière par simple restauration du fichier.

### 5.2 Redémarrage et vérifications

**Redémarrage complet du Pi5.**

Après le reboot, contrôler impérativement :

| Point | Où | Attendu |
|---|---|---|
| État des 2 canaux Shelly | HA — intégration Shelly | **ON** — sinon HA piloterait un onduleur non alimenté |
| Connexion Solarman | HA — les 110 entités | pas de `Timeout fetching` |
| États MPPT | `sensor.smartsolar*_state` | valeurs fraîches, non `unavailable` |
| Absence de coupure DEYE | historique de puissance | production continue |

Le filet reste assuré par l'**auto-trip DEYE à 51.5 Hz**, indépendant des deux systèmes.

---

## 6. Implémentation — architecture packages

### 6.1 Principe retenu

Structure **par règle** (packages HA) plutôt que par domaine : un fichier = une règle, tous domaines confondus. La racine de `/config` reste stable quel que soit le nombre de règles ; supprimer une règle revient à supprimer un fichier.

```
/config
├── configuration.yaml
├── automations.yaml          # conservé pour les automatisations créées via l'UI
├── scripts.yaml
├── scenes.yaml
├── secrets.yaml
├── docs/
│   ├── PILOTAGE-DEYE-SURPRODUCTION.md
│   ├── INTEGRATION-DEYE-SOLARMAN-HA.md
│   └── push_entities.sh
└── packages/
    ├── deye_surproduction.yaml
    └── ...                    # une regle = un fichier
```

**Points à connaître :**

- Les automatisations d'un package **ne sont pas éditables dans l'UI** — visibles en lecture seule, activables/désactivables, mais modifiables uniquement dans le fichier. C'est le prix de la structure, et l'intérêt : le fichier est versionné dans Git.
- Les `id` d'automatisation doivent rester **uniques globalement**.
- Rechargement via « Recharger toutes les configurations YAML » ; si les entités n'apparaissent pas, redémarrer HA.

### 6.2 `configuration.yaml`

Une seule ligne ajoutée — toute règle future ne demandera plus aucune modification de ce fichier.

```yaml
# Loads default set of integrations. Do not remove.
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes
  extra_module_url:
    - /local/community/custom-brand-icons/custom-brand-icons.js

shell_command:
  push_entities_github: bash /config/docs/push_entities.sh

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml

homeassistant:
  packages: !include_dir_named packages
```

### 6.3 `packages/deye_surproduction.yaml`

```yaml
# =============================================================================
# Pilotage des micro-onduleurs DEYE en surproduction
# Doc : docs/PILOTAGE-DEYE-SURPRODUCTION.md
# Regle : etat MPPT le plus avance -> bridage Active Power Regulation
#         Storage -> switch OFF
# =============================================================================

input_number:
  deye_power_bulk:
    name: "DEYE - puissance en Bulk"
    min: 1
    max: 100
    step: 5
    initial: 100
    unit_of_measurement: "%"
    icon: mdi:solar-power-variant

  deye_power_absorption:
    name: "DEYE - puissance en Absorption"
    min: 1
    max: 100
    step: 5
    initial: 40
    unit_of_measurement: "%"
    icon: mdi:solar-power-variant

  deye_power_float:
    name: "DEYE - puissance en Float"
    min: 1
    max: 100
    step: 5
    initial: 15
    unit_of_measurement: "%"
    icon: mdi:solar-power-variant

input_boolean:
  deye_regulation_enabled:
    name: "DEYE - regulation active"
    initial: on
    icon: mdi:tune-variant

template:
  - sensor:
      # Etat MPPT le plus avance parmi tous les SmartSolar
      # Extensible : un nouveau MPPT est pris en compte automatiquement
      - name: "MPPT etat consolide"
        unique_id: mppt_etat_consolide
        icon: mdi:solar-panel
        state: >
          {% set ns = namespace(rang = 0) %}
          {% set hierarchie = {'off':0, 'fault':0, 'bulk':1, 'external_control':1,
                               'absorption':2, 'equalize':2, 'float':3, 'storage':4} %}
          {% for e in states.sensor
             if e.entity_id.startswith('sensor.smartsolar')
             and e.entity_id.endswith('_state')
             and 'load_state' not in e.entity_id %}
            {% set r = hierarchie.get(e.state | lower, 0) %}
            {% if r > ns.rang %}{% set ns.rang = r %}{% endif %}
          {% endfor %}
          {{ ['inconnu','bulk','absorption','float','storage'][ns.rang] }}
        attributes:
          mppt_detail: >
            {% set ns = namespace(l = []) %}
            {% for e in states.sensor
               if e.entity_id.startswith('sensor.smartsolar')
               and e.entity_id.endswith('_state')
               and 'load_state' not in e.entity_id %}
              {% set ns.l = ns.l + [e.name ~ ' = ' ~ e.state] %}
            {% endfor %}
            {{ ns.l | join(' | ') }}

      # Consigne de puissance a appliquer aux DEYE
      - name: "DEYE consigne cible"
        unique_id: deye_consigne_cible
        unit_of_measurement: "%"
        icon: mdi:speedometer
        state: >
          {% set etat = states('sensor.mppt_etat_consolide') %}
          {% if not is_state('input_boolean.deye_regulation_enabled','on') %}
            100
          {% elif etat in ['inconnu','unknown','unavailable'] %}
            100
          {% elif etat == 'absorption' %}
            {{ states('input_number.deye_power_absorption') | int(40) }}
          {% elif etat == 'float' %}
            {{ states('input_number.deye_power_float') | int(15) }}
          {% elif etat == 'storage' %}
            1
          {% else %}
            {{ states('input_number.deye_power_bulk') | int(100) }}
          {% endif %}

      # Etat marche/arret a appliquer aux DEYE
      - name: "DEYE switch cible"
        unique_id: deye_switch_cible
        icon: mdi:power
        state: >
          {% set etat = states('sensor.mppt_etat_consolide') %}
          {% if not is_state('input_boolean.deye_regulation_enabled','on') %}
            on
          {% elif etat == 'storage' %}
            off
          {% else %}
            on
          {% endif %}

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
          {{ (states('number.micro_onduleurs_deye_microinverter_250_active_power_regulation')
              | float(-1) | round(0))
             != (states('sensor.deye_consigne_cible') | int(100)) }}
    action:
      - service: number.set_value
        target:
          entity_id:
            - number.micro_onduleurs_deye_microinverter_250_active_power_regulation
            - number.micro_onduleurs_deye_microinverter_251_active_power_regulation
        data:
          value: "{{ states('sensor.deye_consigne_cible') | int(100) }}"
      - delay:
          minutes: 5

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
        value_template: "{{ states('sensor.deye_switch_cible') in ['on','off'] }}"
      - condition: template
        value_template: >
          {{ states('switch.micro_onduleurs_deye_microinverter_250')
             != states('sensor.deye_switch_cible') }}
    action:
      - service: "switch.turn_{{ states('sensor.deye_switch_cible') }}"
        target:
          entity_id:
            - switch.micro_onduleurs_deye_microinverter_250
            - switch.micro_onduleurs_deye_microinverter_251
      - delay:
          minutes: 5
```

### 6.4 Sécurités intégrées

| Mécanisme | Effet |
|---|---|
| Repli à 100 % | Si `input_boolean` off, état MPPT `inconnu`/`unknown`/`unavailable` → pleine puissance. **Jamais de bridage sur une donnée douteuse.** |
| Repli switch ON | Même logique pour la marche/arrêt |
| `mode: single` + `max_exceeded: silent` | Un déclenchement pendant le `delay` est ignoré — protège contre les écritures rapprochées |
| `delay: minutes: 5` | Laisse la rampe interne se terminer (§4.3) |
| Condition d'écart | Aucune écriture si la consigne est déjà appliquée — limite l'usure EEPROM |
| `\| round(0)` | Absorbe les décimales renvoyées par l'onduleur (§4.6) |

### 6.5 Procédure de mise en service

1. **Pi5 d'abord** (§5) : `mppt_cut_enabled = false`, `freq_high_hz = 99.0`, `freq_hard_hz = 99.0`, reboot complet.
2. Vérifier les 4 points de contrôle §5.2 — en particulier les deux canaux Shelly à **ON**.
3. Créer le répertoire `packages/` et le fichier `deye_surproduction.yaml`.
4. Ajouter les deux lignes `homeassistant: / packages:` dans `configuration.yaml`.
5. Outils de développement → YAML → **Vérifier la configuration**. Ne pas continuer si erreur.
6. Recharger toutes les configurations YAML, ou redémarrer HA.
7. **Contrôle bloquant :** Outils de développement → États → `sensor.mppt_etat_consolide`.
   - état affiché cohérent (`bulk` en charge normale) ;
   - attribut `mppt_detail` listant **les deux** MPPT.
   - Si `mppt_detail` est vide ou incomplet, **arrêter** : le filtre est à corriger.
8. **Désactiver immédiatement les deux automatisations** dans Paramètres → Automatisations.
9. Observer une journée complète : `sensor.deye_consigne_cible` doit passer de 100 à 40 puis 15 au fil de la charge, **sans qu'aucune écriture ne parte**.
10. Activer l'automatisation de puissance. Observer une journée.
11. Activer l'automatisation de switch.

---

## 7. Points de vigilance

### 7.1 Soft Start — réglage transitoire

Actuellement **ON sur les deux onduleurs**. Tant que la restauration passe par le relais, chaque reconnexion renvoie 3720 W instantanément sur la MultiPlus ; Soft Start amortit cette montée.

**Une fois le switch Modbus en service, repasser Soft Start à OFF** : le switch respecte déjà la rampe interne ; empiler Soft Start rendrait le temps de montée imprévisible.

Entités : `switch.micro_onduleurs_deye_microinverter_250_soft_start` et `_251_soft_start`.

### 7.2 Island Protection — désactivé volontairement

Les DEYE sont sur AC Out 1, derrière la MultiPlus. Il n'y a pas de réseau au sens où l'entend le DEYE. Un anti-îlotage actif interpréterait la référence AC de la MultiPlus comme un réseau instable et provoquerait des décrochages intempestifs. **Configuration standard en AC-couplé derrière Victron — ne pas modifier.**

**Conséquence sécurité :** aucune protection active contre l'îlotage. Toute intervention sur l'AC Out 1 se fait après coupure **et** vérification d'absence de tension au multimètre. Ne jamais se fier au seul disjoncteur ouvert : les DEYE peuvent maintenir une tension résiduelle le temps de leur décrochage passif (sous-tension 184 V / sous-fréquence 47.5 Hz).

Le Shelly Pro 2PM, pilotable à distance via VRM Victron, est le moyen de coupure privilégié avant intervention.

### 7.3 RISO — ⚠️ anomalie confirmée sur le `.251`

**Constat, export du 24/07/2026 :**

| Onduleur | État RISO |
|---|---|
| `.250` | **on** |
| `.251` | **off** — s'est désactivé automatiquement après activation |

**Interprétation.** Le seul mécanisme expliquant une auto-désactivation est une **mesure d'isolement échouée au démarrage** : l'onduleur teste, la résistance PV/terre est sous le seuil, et ce firmware bascule la protection sur OFF plutôt que de refuser de démarrer.

**Hypothèse : défaut d'isolement réel sur le string du `.251`** — humidité dans un MC4, câble blessé, connecteur mal serti, boîte de jonction infiltrée. Le `.250`, sur le même site et dans les mêmes conditions, ne présente pas le problème : cela **exclut une cause environnementale globale**.

> Note : le `DC Bus OverVoltage` étant présent sur les **deux** onduleurs, il n'y a pas de lien établi avec l'anomalie RISO.

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

**Corollaire du choix du switch Modbus :** contrairement au relais Shelly, le switch ne coupe pas l'alimentation du logger. La session TCP de HA survit à l'extinction de l'onduleur — avantage structurel.

### 7.5 Bug de déchargement de l'intégration

Log du 22/07/2026 : `KeyError: 'solarman'` lors du déchargement des deux entrées.

**Conséquence :** ne pas désactiver une entrée d'intégration pour libérer le slot TCP — le déchargement peut échouer et laisser une session pendante. Préférer un **redémarrage complet de HA**.

### 7.6 Ajout futur de micro-onduleurs

Même modèle SUN-M200G4-EU-Q0, même AC Out 1, pas dans un avenir proche. À l'ajout :

1. Mettre à jour l'assistant *PV Inverter Support* : `Total installed PV inverter power` (actuellement 3720 W) et `Total installed PV panel power` (5580 W).
2. Vérifier la **règle du facteur 1.0** : la puissance PV AC-couplée ne doit pas dépasser la puissance nominale de la MultiPlus (5000 VA). Avec 2 DEYE on est à 3720 W ; un 3ᵉ porterait à 5580 W, **au-delà de la limite**. Un 3ᵉ micro-onduleur impose une réévaluation complète, pas un simple ajout.
3. Côté HA : une entrée d'intégration supplémentaire, puis ajout des entités dans les listes `entity_id` des deux automatisations du package.

> **Un MPPT supplémentaire, en revanche, ne demande aucune modification** — le template `mppt_etat_consolide` le prend en compte automatiquement (§3.3).

### 7.7 Demande faite à DEYE (52.00 / 52.80 Hz)

Demande ancienne (> 8 mois), jamais appliquée. **Incompatible avec la configuration actuelle** : la MultiPlus ne monte pas au-delà de 51.50 Hz avec l'assistant en place. Si ce firmware était appliqué, les DEYE ne décrocheraient jamais par fréquence et le filet matériel disparaîtrait.

**Action : confirmer auprès de DEYE que cette demande est annulée.**

### 7.8 Version de l'intégration

v25.08.16 (août 2025), installée via HACS. Le dépôt a une activité continue. Avant toute mise à jour, vérifier que le profil `deye_micro.yaml` n'a pas changé de registre.

**Piste d'amélioration :** la demande #3354 (avril 2026, non répondue) porte sur l'exposition du **registre 53 (`0x0035`)**, qui accepte le 0 % — contrairement au registre 40 utilisé actuellement. S'il devenait disponible, il pourrait remplacer le switch pour l'état Storage. Non prioritaire : le switch fait le travail.

---

## 8. Retrait de la logique côté Pi5

> À réaliser **après** validation de §6 en conditions réelles, jamais avant.

Travail à mener avec **Claude Code** connecté au dépôt `thieryus007-cloud/Daly-BMS-Rust`.

### 8.1 À supprimer

| Élément | Emplacement |
|---|---|
| Module de décision DEYE | `crates/energymanager/src/logic/deye_command/mod.rs` |
| Section `[energy_manager.deye]` complète | `Config.toml` |
| Pilotage du Shelly Pro 2PM | `energymanager` |

**Justification du retrait total :** la coupure par fréquence fonctionnait correctement avant l'introduction de ces règles, par le seul jeu du droop Victron et de l'auto-trip DEYE à 51.5 Hz — comportement validé en février-mars 2026. Ce filet matériel est indépendant de tout logiciel. Conserver une couche Rust intermédiaire ajouterait une dépendance sans bénéfice.

### 8.2 À conserver

| Élément | Rôle |
|---|---|
| BMS Daly / CAN | inchangé |
| RS485 | inchangé |
| reDB | inchangé — source Grafana |

> HA lisant les états MPPT directement via l'intégration Victron, **aucune publication MQTT n'est nécessaire** pour le pilotage DEYE.

### 8.3 Ordre des opérations

1. Valider §6 en fonctionnement réel sur plusieurs journées de surproduction.
2. Logique déjà neutralisée par configuration (§5) — observer 1 à 2 semaines.
3. Supprimer le code, mettre à jour `Config.toml`, commit sur GitHub.
4. Vérifier que le reste du service (BMS, reDB) est intact après suppression.

---

## 9. Feuille de route

| # | Action | État | Dépend de |
|---|---|---|---|
| 1 | Activer Over-Frequency Load Reduction sur les 2 DEYE | ✅ 23/07/2026 | — |
| 2 | Point de réduction à 50.6 Hz | ✅ 23/07/2026 | — |
| 3 | Test `Active Power Regulation` | ✅ **validé 24/07/2026** | — |
| 4 | Test du switch Modbus | ✅ **validé 24/07/2026** | — |
| 5 | Test de persistance au redémarrage | ✅ **validé 24/07/2026** | — |
| 6 | Relevé des entités réelles (export CSV) | ✅ 24/07/2026 | — |
| 7 | Choix de l'architecture packages | ✅ 24/07/2026 | — |
| 8 | Vider `Remote Server B` sur les 2 loggers | ⬜ à vérifier | — |
| 9 | Confirmer annulation de la demande DEYE 52.00/52.80 Hz | ⬜ à faire | — |
| 10 | Neutraliser la logique Rust + reboot Pi5 (§5) | ⬜ **préalable** | — |
| 11 | Vérifier les 4 points de contrôle §5.2 | ⬜ | 10 |
| 12 | Créer `packages/deye_surproduction.yaml` | ⬜ | 11 |
| 13 | Modifier `configuration.yaml` | ⬜ | 12 |
| 14 | Vérifier la configuration + recharger | ⬜ | 13 |
| 15 | **Contrôle `mppt_etat_consolide` + `mppt_detail`** | ⬜ **bloquant** | 14 |
| 16 | Observation consignes calculées — 1 journée, automatisations OFF | ⬜ | 15 |
| 17 | Activer l'automatisation de puissance | ⬜ | 16 |
| 18 | Activer l'automatisation de switch | ⬜ | 17 |
| 19 | Désactiver Soft Start sur les 2 DEYE | ⬜ | 18 |
| 20 | Supprimer le code DEYE du Rust — Claude Code + GitHub | ⬜ | 18 + 2 semaines |
| 21 | **Mesure d'isolement du string `.251`** (§7.3) | ⬜ | — |

---

## 10. Références

| Sujet | URL |
|---|---|
| Intégration Solarman utilisée | https://github.com/davidrapan/ha-solarman |
| Wiki — Custom Sensors | https://github.com/davidrapan/ha-solarman/wiki/Custom-Sensors |
| Wiki — Supported Devices | https://github.com/davidrapan/ha-solarman/wiki/Supported-Devices |
| Demande #3354 — registre 53 sur SUN-M200G4 | https://github.com/orgs/home-assistant/discussions/3354 |
| Écriture non persistée (ioBroker #88) | https://github.com/raschy/ioBroker.deyeidc/issues/88 |
| Implémentation de référence (AT + MQTT) | https://github.com/kbialek/deye-inverter-mqtt |
| Rampe interne lente (forum DIY Solar) | https://diysolarforum.com/threads/controlling-deye-micro-inverter-via-modbus-using-python-script.106237/ |
| Packages Home Assistant | https://www.home-assistant.io/docs/configuration/packages/ |
| Bibliothèque Python | https://pypi.org/project/pysolarmanv5/ |
| Dépôt energymanager | https://github.com/thieryus007-cloud/Daly-BMS-Rust |
| Dépôt HA | https://github.com/thieryus007-cloud/HA-Santuario |

---

*Document rédigé pour le projet Santuario — 24 juillet 2026.*
