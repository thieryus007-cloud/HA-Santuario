# Pilotage des micro-onduleurs DEYE en surproduction

> **Statut :** 🟢 En service depuis le 24 juillet 2026 — période d'observation
> **Date :** 24 juillet 2026
> **Installation :** Santuario, Badalucco (Liguria)
> **Documents liés :** `INTEGRATION-DEYE-SOLARMAN-HA.md`, `CAPTEUR-IRRADIANCE.md`

---

## 1. Problème traité

En surproduction (batteries pleines, MPPT en Absorption/Float), l'excédent PV des micro-onduleurs DEYE doit être écrêté.

**Mécanisme primaire, validé depuis février–mars 2026 :** lorsque le Victron monte en fréquence, les DEYE se coupent. Ce comportement est établi et fonctionne sans aucun logiciel.

**Sa limite, identifiée le 24/07/2026 :** le droop Victron réagit en **secondes**, la rampe interne du DEYE prend **2,5 à 3 minutes par palier**. Quand la fréquence monte rapidement vers 51 Hz, le DEYE n'a pas matériellement le temps de descendre — il atteint 51,5 Hz et décroche brutalement.

**Objectif :** anticiper. Brider les DEYE **avant** que le Victron n'ait besoin de monter en fréquence, sur une échelle de temps compatible avec leur rampe interne.

> ⚠️ **Cadrage.** Ce dispositif est un **second parachute**. Le filet fréquence reste le socle et fonctionne depuis cinq mois. L'anticipation vise à réduire les décrochages brutaux, pas à les remplacer.

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

> Les DEYE sont **AC-couplés** sur AC Out 1, chacun avec ses propres panneaux. Aucun lien avec le bus DC 48 V du Victron.

### 2.2 Configuration des MPPT

| Paramètre | Valeur |
|---|---|
| Tension batterie | 48 V |
| **Absorption voltage** | **55,50 V** |
| **Float voltage** | **54,50 V** |
| Equalization | Disabled |
| Temperature compensation | Disabled |
| Max charge current (250/100) | 95 A |
| Max charge current (150/35) | 35 A |

Ce sont ces deux seuils qui déterminent les bascules d'état des MPPT, et donc les seuils d'anticipation retenus en §3.3.

### 2.3 Réglages fréquence

| Élément | Paramètre | Valeur |
|---|---|---|
| Victron — Assistant *PV Inverter Support* | Début réduction | 50.30 Hz |
| | Puissance minimale atteinte à | 51.00 Hz |
| | Déconnexion au-dessus de | 51.50 Hz |
| | PV inverter installé | 3720 W |
| | PV panel installé | 5580 W |
| | PSMax / droop | 2400 W / 1.20 % |
| | PCMax / droop | 1250 W / 2.40 % |
| Victron — Grid / CEI | Over / Under frequency (trip réseau) | 55 Hz / 45 Hz |
| DEYE (Modbus) | Grid Frequency Upper Limit | **51.5 Hz** |
| | Grid Frequency Lower Limit | 47.5 Hz |
| | Grid Voltage Lower / Upper | 184 V / 287.5 V |
| | Over-Frequency Load Reduction | ✅ activé — 50.6 Hz, taux 71 % *(23/07/2026)* |
| | Island Protection | ❌ désactivé — **volontaire** (§7.2) |
| | RISO | ⚠️ `.250` = ON, `.251` = OFF — anomalie (§7.3) |
| | Soft Start | ✅ ON sur les deux — transitoire (§7.1) |
| | Self-check time | 65 s |
| | Active Power Regulation | ✅ **fonctionnel, plage 1–100 %** |

### 2.4 Infrastructure

| Hôte | Rôle |
|---|---|
| Pi5 `192.168.1.141` | BMS Daly (CAN), RS485, reDB (Rust), Grafana, Mosquitto |
| NanoPi `192.168.1.120` | Venus OS — GX master |
| Mac Mini M4 | HAOS en VM VMware Fusion — `192.168.1.10` |
| DEYE loggers | `.250` / `.251`, TCP-Server port 8889, **1 seule connexion TCP simultanée** |

> La logique DEYE de l'`energymanager` a été **neutralisée par configuration** le 24/07/2026 (§5).

### 2.5 Intégration Solarman

| Point | Constat |
|---|---|
| Composant | `davidrapan/ha-solarman` **v25.08.16** via HACS |
| Statut | « Intégration personnalisée qui remplace un composant Core » |
| Résultat | 2 appareils × 55 entités = 110 entités |
| Socle technique | `pysolarmanv5` asynchrone, Modbus TCP |

**Emplacement des profils :** `/config/custom_components/solarman/inverter_definitions/deye_micro.yaml`.

⚠️ L'add-on « Terminal & SSH » est **cloisonné** : son `/config` pointe vers son propre `/homeassistant`, qui ne contient que `hacs`. Utiliser **File editor** ou **Studio Code Server**.

### 2.6 Entités réelles — vérifiées le 24/07/2026

> ⚠️ Le préfixe DEYE est `micro_onduleurs_deye_microinverter_XXX_`, **pas** `micro_inverter_XXX_`.

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
| Puissance AC `.250` / `.251` | `sensor.micro_onduleurs_deye_microinverter_2XX_power` |
| Défaut `.250` / `.251` | `sensor.micro_onduleurs_deye_microinverter_2XX_device_fault` |
| État `.250` / `.251` | `sensor.micro_onduleurs_deye_microinverter_2XX_device_state` |
| RISO, Soft Start | `switch.micro_onduleurs_deye_microinverter_2XX_riso` / `_soft_start` |

**Sources de décision :**

| Donnée | Entité |
|---|---|
| État MPPT 250/100 | `sensor.smartsolar_mppt_ve_can_250_100_rev2_id_273_state` |
| État MPPT 150/35 | `sensor.smartsolar_charger_mppt_150_35_id_289_state` |
| Tension MPPT 250/100 | `sensor.smartsolar_mppt_ve_can_250_100_rev2_id_273_dc_battery_bus_voltage` |
| Tension MPPT 150/35 | `sensor.smartsolar_charger_mppt_150_35_id_289_dc_battery_bus_voltage` |
| **Courant batterie** | `sensor.smartshunt_300a_id_274_dc_bus_current` |

> Les états MPPT sont des **chaînes** (`bulk`, `absorption`, `float`, `storage`), pas les codes numériques 3/4/5/6 du Rust.
>
> **Aucune entité MQTT du Pi5 n'est utilisée** : la source est l'intégration Victron directement.

---

## 3. Architecture retenue

### 3.1 Quatre couches

| Couche | Mécanisme | Échelle de temps | Dépendance |
|---|---|---|---|
| **1 — Filet matériel** | Auto-trip DEYE 51.5 Hz + droop Victron | seconde | **aucune** |
| **2 — Anticipation** | `Active Power Regulation` écrit par HA | 10 min | HA |
| **3 — Arrêt** | `switch.micro_onduleurs_deye_microinverter_*` | 5 min | HA |
| **4 — Coupure physique** | Shelly Pro 2PM | manuel | HA ou VRM |

Les couches 1 et 2 ne sont **pas concurrentes mais complémentaires** : la première protège en urgence, la seconde évite d'y arriver.

**Le Shelly sort de la boucle de régulation.** Le switch Modbus le remplace : il éteint l'onduleur en respectant sa rampe interne, sans à-coup et sans couper l'alimentation du logger.

### 3.2 Sources de décision

| Grandeur | Source | Pourquoi celle-là |
|---|---|---|
| **Tension** | Maximum des MPPT | C'est la tension **vue par le MPPT** qui déclenche sa bascule, pas celle du shunt. Écart mesuré ~0,35 V sous 49 A (chute dans le câblage) |
| **Courant** | SmartShunt 300A | Mesure de référence, convention positive = charge (vérifié : +49,3 A / +2661,7 W en charge) |
| **État MPPT** | Maximum des états | Un MPPT signalant batterie pleine suffit |

### 3.3 Matrice de décision

Ordre d'évaluation — **le garde-fou prime sur tout** :

| # | Condition | Consigne | Switch |
|---|---|---|---|
| 1 | Régulation désactivée | 100 % | ON |
| 2 | Données indisponibles | 100 % | ON |
| 3 | **Courant < 2 A** (décharge ou charge terminée) | **100 %** | **ON** |
| 4 | État MPPT `float` ou `storage` | 15 % | ON / **OFF** si storage |
| 5 | Absorption **et** tension ≥ 54,20 V | 15 % | ON |
| 6 | Tension ≥ 55,20 V (anticipation) | 40 % | ON |
| 7 | État MPPT `absorption` | 40 % | ON |
| 8 | Sinon (Bulk) | 100 % | ON |

**Seuils de tension**, dérivés de la configuration MPPT (§2.2) :

| Seuil | Valeur | Calcul |
|---|---|---|
| Anticipation Absorption | **55,20 V** | Absorption 55,50 − 0,30 |
| Anticipation Float | **54,20 V** | Float 54,50 − 0,30 |

**Puissances**, par onduleur (nominal 1860 W) :

| État | Consigne | Puissance ≈ |
|---|---|---|
| Bulk | 100 % | pleine puissance |
| Absorption | 40 % | ~745 W |
| Float | 15 % | ~280 W |
| Storage | switch OFF | 0 W |

### 3.4 Le garde-fou courant — pourquoi il est indispensable

54,20 V est **inférieur** à 55,20 V. Une batterie qui se décharge de 55,5 V vers 54 V traverse le seuil « Float » **en descendant**. Sans garde-fou, l'automatisation briderait les DEYE au moment précis où toute leur puissance est nécessaire.

Le courant lève l'ambiguïté : un seuil de tension n'a pas de sens sans le sens de variation.

```
Courant ≥ 2 A  → charge en cours, tension pertinente, bridage possible
Courant < 2 A  → décharge ou charge terminée → 100 %, sans condition
```

**Validé en conditions réelles le 24/07/2026 à 14h59 :** batteries pleines, courant 0,0 A, consigne ramenée à 100 % avec la raison « décharge ou charge terminée (0.0 A) ».

### 3.5 Répartition des rôles

| Composant | Rôle |
|---|---|
| **Pi5 / `energymanager`** | BMS Daly, RS485, reDB, Grafana. **Plus aucune décision DEYE.** |
| **Home Assistant** | Toute la logique. Seuils en `input_number` modifiables depuis l'UI. |
| **Shelly Pro 2PM** | Coupure physique avant intervention (HA ou VRM). **Hors boucle.** |
| **DEYE** | Auto-trip 51.5 Hz + Over-Frequency Load Reduction. Filet autonome. |
| **Victron** | Assistant PV Inverter Support inchangé. Fournit états, tensions et courant. |

### 3.6 Justification du choix HA plutôt que Pi5

| Critère | Pi5 | HA | Retenu |
|---|---|---|---|
| Disponibilité constatée | arrêt ~1×/mois | watchdog LaunchAgent + auto-restart validés | HA |
| Modification d'un seuil | recompile + redéploiement | `input_number` dans l'UI | HA |
| Ajout d'un micro-onduleur | code + `Config.toml` + rebuild | entrée d'intégration | HA |
| Périmètre du projet | `Daly-BMS-Rust` = batteries — dérive | pilotage énergétique = rôle natif | HA |
| Sources de décision | à instrumenter en MQTT | intégration Victron native | HA |

### 3.7 Schéma

```
   Victron (intégration native)              Home Assistant
   ├── MPPT 250/100 : state + voltage ──>    ├── template : etat consolide
   ├── MPPT 150/35  : state + voltage ──>    ├── template : tension max
   ├── SmartShunt   : courant ──────────>    ├── template : consigne + switch
   └── (MPPT futurs : automatique)           ├── input_number (seuils)
                                             └── 2 automatisations
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

## 4. Résultats des tests — 24 juillet 2026

### 4.1 Écriture `Active Power Regulation` — ✅ validée

| Champ | Valeur |
|---|---|
| Onduleur testé | `.251`, 8h35 – 9h25 |
| Consignes | 100 % → 22 % → 100 % → 1 % → 100 % |
| Écriture acceptée | ✅ |
| Effet réel | ✅ confirmé |
| Plancher | **1 %** — jamais 0 |
| Registre déduit | **40 (`0x0028`)** — signature du plancher à 1 % |
| Persistance au redémarrage | ✅ confirmée |
| Switch Modbus | ✅ fonctionnel, extinction en 2 paliers |

**Séquence observée :**

| Heure | Consigne | Puissance |
|---|---|---|
| ~8h39 | 100 → 22 % | 750 → 670 → 400 → 150 W (4 paliers) |
| ~8h50 | 22 → 100 → 1 % | |
| ~8h58 | 1 → 100 % | 400 → 860 → 930 W (3 paliers) |

### 4.2 Comportement en paliers — contrainte structurante

L'onduleur **n'applique pas la consigne instantanément**. Il progresse par marches.

| Mesure | Valeur |
|---|---|
| Durée d'un palier | **2,5 à 3 minutes** |
| Transition complète | **~10 à 12 minutes** |

**Conséquences :**

1. **Aucune rampe logicielle** — l'onduleur a la sienne.
2. **Écrire directement la consigne cible**, une seule fois par changement.
3. **Ne pas réécrire pendant une transition** → `delay: minutes: 5`.
4. **Le bridage ne peut pas être réactif.** Il travaille sur la dizaine de minutes, la fréquence sur la seconde. D'où l'anticipation par tension.

### 4.3 Incident de 11h14 — analyse

**Observé :** consigne appliquée à 40 % à 11h14, puis chute de la production à 0 W vers 11h30, `Device State: Fault` sur les deux onduleurs.

**Cause identifiée :** la fréquence en sortie du Victron est montée rapidement à 51 Hz. Le DEYE, qui procède par paliers de 2,5–3 min, n'a pas eu le temps de réduire sa puissance et a décroché sur l'auto-trip 51,5 Hz.

**Le bridage n'est pas en cause** — il n'a simplement pas eu le temps d'agir. Le filet fréquence, plus rapide, est arrivé le premier.

> **Sur le `Fault` :** c'est l'état normal d'un DEYE arrêté, quelle qu'en soit la cause. Il apparaissait déjà lors des coupures par fréquence antérieures. Ce n'est **pas** un défaut matériel provoqué par le bridage.

C'est cet incident qui a motivé le passage à l'anticipation par tension (§3.3) : agir avant que la fréquence ne monte, pas pendant.

### 4.4 Défaut `DC Bus OverVoltage`

Remonté par les **deux** onduleurs. Le `DC Bus` en question est **interne au micro-onduleur** — l'étage continu entre ses entrées PV et son onduleur — et n'a aucun rapport avec le bus DC 48 V du Victron.

**Mécanisme :** brider la sortie AC alors que les panneaux produisent à pleine puissance fait monter la tension de ce bus interne.

**Règles :** éviter les consignes très basses prolongées en pleine production ; préférer le switch OFF au bridage à 1 % pour un arrêt réel.

### 4.5 Validation de la chaîne complète — 14h18

Passage en Float détecté (confirmé par VRM), consigne calculée à 15 %, écriture effective sur les deux onduleurs (`Regulation 250 : 15`, `Regulation 251 : 15`). **La chaîne détection → calcul → écriture Modbus fonctionne.**

### 4.6 Validation du garde-fou — 14h59

| Élément | Valeur |
|---|---|
| Tension max | 54,61 V |
| Détail | 250/100 = 54,50 V \| 150/35 = 54,61 V — **les deux détectés** |
| Courant | 0,0 A |
| Consigne | **100** |
| Raison | décharge ou charge terminée (0.0 A) |

Batteries pleines, plus de courant de charge : la consigne repasse à 100 % au lieu de rester à 15 %. **Comportement voulu** — ne pas limiter les DEYE quand la batterie n'absorbe plus et que la production doit aller aux charges.

### 4.7 Échelle et valeurs renvoyées

**Échelle :** l'écriture via `number.set_value` fonctionne avec des pourcentages entiers. Aucune conversion à faire — l'intégration gère le `scale`.

**Décimales :** l'onduleur renvoie sa valeur appliquée avec une décimale (`22,2 %` pour une consigne de 22). D'où le `| round(0)` dans les conditions de comparaison.

---

## 5. Neutralisation de la logique Rust

Réalisée le 24/07/2026, **par configuration uniquement** — réversible.

`Config.toml` sur le Pi5 :

```toml
[energy_manager.deye]
mppt_cut_enabled = false      # supprime la coupure sur etat MPPT
freq_high_hz     = 99.0       # seuil hors plage : plus de coupure frequence
freq_hard_hz     = 99.0
```

Suivi d'un **redémarrage complet du Pi5**.

**Pourquoi c'était indispensable :** faire tourner les deux systèmes en parallèle crée un conflit direct. L'`energymanager` coupe le relais Shelly, ce qui coupe l'alimentation du logger ; HA perd sa connexion TCP, ses écritures échouent, et l'état du switch devient incohérent.

**Contrôles après reboot :**

| Point | Attendu |
|---|---|
| État des 2 canaux Shelly | **ON** |
| Connexion Solarman | pas de `Timeout fetching` |
| États et tensions MPPT | valeurs fraîches |
| Production DEYE | continue |

Le filet reste assuré par l'**auto-trip DEYE à 51.5 Hz**, indépendant des deux systèmes.

---

## 6. Implémentation — `packages/deye_surproduction.yaml`

### 6.1 Architecture packages

Structure **par règle** : un fichier = une règle, tous domaines confondus.

```
/config
├── configuration.yaml
├── automations.yaml          # automatisations créées via l'UI
├── scripts.yaml
├── scenes.yaml
├── docs/
│   ├── PILOTAGE-DEYE-SURPRODUCTION.md
│   ├── INTEGRATION-DEYE-SOLARMAN-HA.md
│   └── CAPTEUR-IRRADIANCE.md
└── packages/
    ├── deye_surproduction.yaml
    ├── irradiance.yaml
    └── ...                    # une regle = un fichier
```

Dans `configuration.yaml`, une seule ligne :

```yaml
homeassistant:
  packages: !include_dir_named packages
```

**Points à connaître :**

- Les automatisations d'un package **ne sont pas éditables dans l'UI** — visibles en lecture seule, activables/désactivables, modifiables uniquement dans le fichier. C'est le prix de la structure, et l'intérêt : le fichier est versionné dans Git.
- Les `id` d'automatisation doivent rester **uniques globalement**.

### 6.2 Le package

Voir le fichier `packages/deye_surproduction.yaml`. Structure :

| Bloc | Contenu |
|---|---|
| `input_number` | 3 puissances (Bulk/Absorption/Float), 2 seuils de tension, 1 courant mini |
| `input_boolean` | `deye_regulation_enabled` — interrupteur général |
| `template` | 4 capteurs : état consolidé, tension max, consigne cible, switch cible |
| `automation` | 2 automatisations : puissance, marche/arrêt |

### 6.3 Sécurités intégrées

| Mécanisme | Effet |
|---|---|
| Garde-fou courant | Priorité absolue : < 2 A → 100 % (§3.4) |
| Repli à 100 % | Régulation off, données `unknown`/`unavailable`, ou tension nulle |
| Repli switch ON | Même logique pour la marche/arrêt |
| `mode: single` + `max_exceeded: silent` | Déclenchement pendant le `delay` ignoré |
| `delay: minutes: 5` | Laisse la rampe interne se terminer (§4.2) |
| Condition d'écart | Aucune écriture si la consigne est déjà appliquée — usure EEPROM |
| `\| round(0)` | Absorbe les décimales renvoyées par l'onduleur (§4.7) |

### 6.4 Extensibilité

| Ajout | Modification requise |
|---|---|
| **Un MPPT supplémentaire** | **Aucune** — les templates balaient `sensor.smartsolar*` |
| Un micro-onduleur | Entrée d'intégration + entités dans les listes `entity_id` |
| Ajuster un seuil | Aucune — `input_number` dans l'UI |

### 6.5 Attribut `raison` — diagnostic

`sensor.deye_consigne_cible` porte un attribut `raison` en clair :

```
decharge ou charge terminee (0.0 A)
anticipation : tension 55.3 V >= seuil absorption
absorption + tension 54.4 V >= seuil float
etat MPPT float
```

Indispensable pour comprendre une décision sans reconstituer la logique.

### 6.6 Vérification

Outils de développement → Modèle :

```jinja
Etat consolide : {{ states('sensor.mppt_etat_consolide') }}
Detail etats   : {{ state_attr('sensor.mppt_etat_consolide','mppt_detail') }}
Tension max    : {{ states('sensor.mppt_tension_max') }}
Detail tension : {{ state_attr('sensor.mppt_tension_max','tension_detail') }}
Courant        : {{ states('sensor.smartshunt_300a_id_274_dc_bus_current') }}
Consigne       : {{ states('sensor.deye_consigne_cible') }}
Raison         : {{ state_attr('sensor.deye_consigne_cible','raison') }}
Switch cible   : {{ states('sensor.deye_switch_cible') }}

--- Etat reel ---
Regulation 250 : {{ states('number.micro_onduleurs_deye_microinverter_250_active_power_regulation') }}
Regulation 251 : {{ states('number.micro_onduleurs_deye_microinverter_251_active_power_regulation') }}
Switch 250     : {{ states('switch.micro_onduleurs_deye_microinverter_250') }}
Switch 251     : {{ states('switch.micro_onduleurs_deye_microinverter_251') }}
Puissance 250  : {{ states('sensor.micro_onduleurs_deye_microinverter_250_power') }}
Puissance 251  : {{ states('sensor.micro_onduleurs_deye_microinverter_251_power') }}
```

**Contrôle bloquant :** `mppt_detail` et `tension_detail` doivent lister **les deux** MPPT.

---

## 7. Points de vigilance

### 7.1 Soft Start — réglage transitoire

Actuellement **ON sur les deux**. Tant que la restauration passe par le relais, chaque reconnexion renvoie 3720 W instantanément sur la MultiPlus.

**Une fois le switch Modbus éprouvé, repasser à OFF** : le switch respecte déjà la rampe interne ; empiler Soft Start rendrait le temps de montée imprévisible.

### 7.2 Island Protection — désactivé volontairement

Les DEYE sont sur AC Out 1, derrière la MultiPlus. Il n'y a pas de réseau au sens où l'entend le DEYE. Un anti-îlotage actif interpréterait la référence AC de la MultiPlus comme un réseau instable et provoquerait des décrochages intempestifs. **Configuration standard en AC-couplé derrière Victron — ne pas modifier.**

**Conséquence sécurité :** aucune protection active contre l'îlotage. Toute intervention sur l'AC Out 1 se fait après coupure **et** vérification d'absence de tension au multimètre. Ne jamais se fier au seul disjoncteur ouvert : les DEYE peuvent maintenir une tension résiduelle le temps de leur décrochage passif (184 V / 47.5 Hz).

Le Shelly Pro 2PM, pilotable à distance via VRM, est le moyen de coupure privilégié avant intervention.

### 7.3 RISO — ⚠️ anomalie sur le `.251`

| Onduleur | État RISO |
|---|---|
| `.250` | **on** |
| `.251` | **off** — s'est désactivé automatiquement après activation |

**Interprétation.** Une auto-désactivation signale une **mesure d'isolement échouée au démarrage** : la résistance PV/terre est sous le seuil, et ce firmware bascule la protection sur OFF plutôt que de refuser de démarrer.

**Hypothèse : défaut d'isolement réel sur le string du `.251`** — humidité dans un MC4, câble blessé, boîte de jonction infiltrée. Le `.250`, sur le même site, ne présente pas le problème : cela **exclut une cause environnementale globale**.

**Actions :**

1. Mesure d'isolement PV+/terre et PV−/terre au **mégohmmètre** sur le string du `.251`, hors production. Attendu : > 1 MΩ.
2. Inspection visuelle des MC4 et de la boîte de jonction.
3. **Comparer avec le `.250`** — l'écart sera plus parlant que la valeur absolue.

En vallée ligure (humidité, écarts thermiques), c'est le défaut attendu. **Ne jamais désactiver RISO pour faire taire le symptôme.**

### 7.4 Contrainte du slot TCP unique

**Un seul client TCP par logger DEYE.** HA est le client unique. Interdits en fonctionnement normal : script `pysolarmanv5` sur le Pi5, application mobile Solarman en local, `Remote Server A` (cloud) actif, tests `nc` répétés.

`Remote Server B` (`192.168.1.10:502`, vestige de la configuration TCP-Client) : **à vider sur les deux loggers**.

**Avantage du switch Modbus :** contrairement au relais Shelly, il ne coupe pas l'alimentation du logger. La session TCP survit à l'extinction de l'onduleur.

### 7.5 Bug de déchargement de l'intégration

Log du 22/07/2026 : `KeyError: 'solarman'` lors du déchargement.

**Conséquence :** ne pas désactiver une entrée d'intégration pour libérer le slot TCP — le déchargement peut échouer et laisser une session pendante. Préférer un **redémarrage complet de HA**.

### 7.6 Ajout futur de micro-onduleurs

Même modèle SUN-M200G4-EU-Q0, même AC Out 1, pas dans un avenir proche. À l'ajout :

1. Mettre à jour l'assistant *PV Inverter Support* : `Total installed PV inverter power` (3720 W) et `Total installed PV panel power` (5580 W).
2. Vérifier la **règle du facteur 1.0** : la puissance PV AC-couplée ne doit pas dépasser la puissance nominale de la MultiPlus (5000 VA). Avec 2 DEYE : 3720 W. Un 3ᵉ porterait à 5580 W — **au-delà de la limite**. Réévaluation complète nécessaire, pas un simple ajout.
3. Côté HA : entrée d'intégration + entités dans les listes `entity_id` des deux automatisations.

### 7.7 Demande faite à DEYE (52.00 / 52.80 Hz)

Demande ancienne (> 8 mois), jamais appliquée. **Incompatible avec la configuration actuelle** : la MultiPlus ne monte pas au-delà de 51.50 Hz. Si ce firmware était appliqué, les DEYE ne décrocheraient jamais par fréquence et le filet matériel disparaîtrait.

**Action : confirmer auprès de DEYE que cette demande est annulée.**

### 7.8 Version de l'intégration

v25.08.16 (août 2025) via HACS. Avant toute mise à jour, vérifier que `deye_micro.yaml` n'a pas changé de registre.

**Piste :** la demande #3354 (avril 2026, non répondue) porte sur l'exposition du **registre 53 (`0x0035`)**, qui accepte le 0 %. Non prioritaire — le switch fait le travail.

---

## 8. Retrait définitif de la logique Rust

> À réaliser après plusieurs semaines d'observation concluante.

Travail avec **Claude Code** sur `thieryus007-cloud/Daly-BMS-Rust`.

### 8.1 À supprimer

| Élément | Emplacement |
|---|---|
| Module de décision DEYE | `crates/energymanager/src/logic/deye_command/mod.rs` |
| Section `[energy_manager.deye]` | `Config.toml` |
| Pilotage du Shelly Pro 2PM | `energymanager` |

**Justification :** la coupure par fréquence fonctionne par le seul jeu du droop Victron et de l'auto-trip DEYE — validé en février-mars 2026, indépendant de tout logiciel. Une couche Rust intermédiaire ajouterait une dépendance sans bénéfice.

### 8.2 À conserver

BMS Daly / CAN, RS485, reDB (source Grafana).

> HA lisant les MPPT et le SmartShunt via l'intégration Victron, **aucune publication MQTT n'est nécessaire** pour le pilotage DEYE.

---

## 9. Feuille de route

| # | Action | État |
|---|---|---|
| 1 | Over-Frequency Load Reduction activé, point à 50.6 Hz | ✅ 23/07 |
| 2 | Test `Active Power Regulation` | ✅ 24/07 |
| 3 | Test du switch Modbus | ✅ 24/07 |
| 4 | Test de persistance au redémarrage | ✅ 24/07 |
| 5 | Relevé des entités réelles | ✅ 24/07 |
| 6 | Architecture packages | ✅ 24/07 |
| 7 | Neutralisation logique Rust + reboot Pi5 | ✅ 24/07 |
| 8 | Package déployé, automatisations actives | ✅ 24/07 |
| 9 | Anticipation par tension + garde-fou courant | ✅ 24/07 |
| 10 | **Observation sur plusieurs jours** | ⬜ **en cours** |
| 11 | Vérifier que l'anticipation évite la montée en fréquence | ⬜ |
| 12 | Ajuster les seuils si nécessaire (`input_number`) | ⬜ |
| 13 | Vider `Remote Server B` sur les 2 loggers | ⬜ |
| 14 | Confirmer annulation demande DEYE 52.00/52.80 Hz | ⬜ |
| 15 | Désactiver Soft Start | ⬜ |
| 16 | Supprimer le code DEYE du Rust | ⬜ |
| 17 | **Mesure d'isolement du string `.251`** (§7.3) | ⬜ |

### 9.1 Ce qu'il faut observer

**Le passage matinal** est le moment clé : montée en tension, franchissement de 55,20 V, bridage à 40 % **avant** que le Victron ne monte en fréquence.

| Signal | Interprétation |
|---|---|
| Consigne à 40 % puis production stable | ✅ anticipation efficace |
| Consigne à 40 % puis décrochage sur fréquence | ⚠️ trop tard ou insuffisant → descendre à 25–30 % en Absorption |
| Bridage en pleine charge batterie | ⚠️ seuil trop bas → remonter `deye_seuil_absorption` |
| Consigne oscillante | ⚠️ hystérésis à ajouter |

Tous ces ajustements se font par `input_number`, sans modification de fichier.

---

## 10. Références

| Sujet | URL |
|---|---|
| Intégration Solarman | https://github.com/davidrapan/ha-solarman |
| Wiki — Custom Sensors | https://github.com/davidrapan/ha-solarman/wiki/Custom-Sensors |
| Demande #3354 — registre 53 | https://github.com/orgs/home-assistant/discussions/3354 |
| Écriture non persistée (ioBroker #88) | https://github.com/raschy/ioBroker.deyeidc/issues/88 |
| Implémentation de référence (AT + MQTT) | https://github.com/kbialek/deye-inverter-mqtt |
| Rampe interne lente (forum DIY Solar) | https://diysolarforum.com/threads/controlling-deye-micro-inverter-via-modbus-using-python-script.106237/ |
| Packages Home Assistant | https://www.home-assistant.io/docs/configuration/packages/ |
| Dépôt energymanager | https://github.com/thieryus007-cloud/Daly-BMS-Rust |
| Dépôt HA | https://github.com/thieryus007-cloud/HA-Santuario |

---

*Document rédigé pour le projet Santuario — 24 juillet 2026.*
