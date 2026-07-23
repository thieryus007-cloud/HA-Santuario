# Pilotage des micro-onduleurs DEYE en surproduction

> **Statut :** 🟡 Décision d'architecture actée — implémentation conditionnée au test §4
> **Date :** 23 juillet 2026
> **Installation :** Santuario, Badalucco (Liguria)
> **Documents liés :** `INTEGRATION-DEYE-SOLARMAN-HA.md`

---

## 1. Problème traité

En surproduction (batteries pleines, MPPT en Float/Storage), l'excédent PV des micro-onduleurs DEYE doit être écrêté. Le mécanisme actuel est **binaire** : coupure du relais Shelly, soit 3720 W qui disparaissent instantanément, puis reviennent instantanément après le délai de restauration.

Conséquences :

- à-coups sur la MultiPlus-II à chaque transition ;
- overshoot de fréquence lors des reconnexions ;
- cycles de décrochage / resynchronisation des DEYE ;
- logique de régulation implantée dans un projet dont ce n'est pas le périmètre.

**Objectif :** passer d'une régulation tout-ou-rien à une régulation proportionnelle, avec la logique centralisée dans Home Assistant.

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
| | Over-Frequency Load Reduction | ✅ activé *(fait le 23/07/2026)* |
| | Point de réduction | 50.6 Hz *(fait le 23/07/2026)* |
| | Taux de réduction | 71 % |
| | Island Protection | ❌ désactivé — **volontaire** |
| | RISO | ✅ activé |
| | Soft Start | ⚠️ à activer — **transitoire**, voir §7.1 |
| | Self-check time | 65 s |
| | Active Power Regulation | 100 % — **à tester, voir §4** |

### 2.3 Logique logicielle actuelle

Implantée dans `Daly-BMS-Rust`, crate `energymanager`, module `logic/deye_command/mod.rs`, configurée par `Config.toml` :

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

---

## 3. Cible

### 3.1 Principe

Trois couches indépendantes, de la plus rapide à la plus lente :

| Couche | Mécanisme | Rôle | Dépendance logicielle |
|---|---|---|---|
| **1 — Filet matériel** | Auto-trip DEYE 51.5 Hz + droop Victron | Protection ultime | **aucune** |
| **2 — Régulation** | `Active Power Regulation` écrit par HA | Écrêtage proportionnel | HA |
| **3 — Coupure** | Shelly Pro 2PM | Intervention / maintenance à distance | manuel (HA ou VRM) |

La couche 1 est celle qui fonctionnait avant toute logique logicielle et qui continuera de fonctionner si tout le reste tombe. C'est le socle.

### 3.2 Répartition des rôles

| Composant | Rôle cible |
|---|---|
| **Pi5 / `energymanager`** | BMS Daly, RS485, reDB, Grafana. Publication MQTT : fréquence AC, état MPPT, SOC. **Plus aucune décision DEYE.** |
| **Home Assistant** | Toute la logique de régulation. Seuils en `input_number` modifiables depuis l'UI. Rampe. Écriture Modbus vers les DEYE via `davidrapan/ha-solarman`. |
| **Shelly Pro 2PM** | Coupure manuelle uniquement (HA ou VRM à distance). Retiré de la boucle de régulation. |
| **DEYE** | Auto-trip 51.5 Hz + Over-Frequency Load Reduction. Filet autonome. |
| **Victron** | Assistant PV Inverter Support inchangé. |

### 3.3 Justification du choix HA plutôt que Pi5

| Critère | Pi5 | HA | Retenu |
|---|---|---|---|
| Disponibilité constatée | arrêt ~1×/mois | watchdog LaunchAgent + auto-restart validés | HA |
| Modification d'un seuil | recompile + redéploiement | `input_number` dans l'UI | HA |
| Ajout d'un micro-onduleur | code + `Config.toml` + topic MQTT + rebuild | entrée d'intégration | HA |
| Périmètre du projet | `Daly-BMS-Rust` = batteries — dérive de périmètre | pilotage énergétique = rôle natif | HA |
| Remontée d'informations | à instrumenter | 110 entités déjà disponibles | HA |

### 3.4 Schéma cible

```
   Pi5 (energymanager)                    Home Assistant
   ├── BMS Daly / CAN                     ├── Intégration Solarman (110 entités)
   ├── RS485                              ├── Intégration Shelly (native)
   ├── reDB ──> Grafana                   ├── input_number (seuils)
   └── MQTT ──────────────────────────>   └── Automatisation + script rampe
       freq AC / MPPT state / SOC                     │
                                                      ↓
                                          write Active Power Regulation
                                                      │
                                          ┌───────────┴───────────┐
                                       DEYE .250              DEYE .251
                                          │                       │
                                    auto-trip 51.5 Hz (indépendant)
```

---

## 4. Préalable bloquant — test d'écriture `Active Power Regulation`

> ⚠️ **Rien de la cible ne doit être implémenté avant ce test.** Si le registre refuse l'écriture ou n'a pas d'effet réel, l'architecture retombe sur la coupure relais et le présent document doit être révisé.

### 4.0 Conditions

- **Météo :** pleine production, 11 h – 14 h, DEYE > 1500 W. Le bridage à 50 % n'est pas mesurable à faible production.
- **Batteries :** ne pas tester à 99 % de SOC — la régulation Victron masquerait l'effet. Viser un SOC intermédiaire, en charge active.
- **Slot TCP :** un seul client. Séquence de libération obligatoire ci-dessous.

### 4.1 Libération du slot TCP

```bash
# 1. Désactiver l'intégration Solarman dans HA
#    Paramètres > Appareils et services > Solarman > ⋮ > Désactiver
#    (les DEUX entrées : .250 et .251)

# 2. Arrêter energymanager sur le Pi5
sudo systemctl stop energymanager

# 3. Fermer l'application mobile Solarman si ouverte

# 4. Attendre 60 s (TCP time out setting) pour libérer les sessions pendantes
sleep 60

# 5. Vérifier qu'aucun process ne parle aux loggers
ps aux | grep -i solarman
```

### 4.2 Étape 1 — Localiser le registre

L'offset d'`Active Power Regulation` varie selon le firmware. Balayage de la zone de configuration :

```bash
pip3 install pysolarmanv5 --break-system-packages

python3 - <<'EOF'
from pysolarmanv5 import PySolarmanV5
import time

m = PySolarmanV5('192.168.1.250', 3871081176, port=8889,
                 mb_slave_id=1, verbose=False, socket_timeout=10)

for addr in range(40, 130):
    try:
        v = m.read_holding_registers(register_addr=addr, quantity=1)[0]
        flag = "  <-- CANDIDAT" if v in (100, 1000) else ""
        print(f"reg {addr:3d} = {v}{flag}")
    except Exception:
        pass
    time.sleep(0.15)

m.disconnect()
EOF
```

Candidats : registres valant exactement **100** (échelle en %) ou **1000** (échelle en dixièmes).

Confirmation croisée avec le profil de l'intégration :

```bash
grep -n -i -A6 "active.*power\|power.*regul" \
  /config/custom_components/solarman/inverter_definitions/deye_micro.yaml
```

Si le registre est déclaré avec `platform: number` ou dans une section `configurable`, l'écriture est supportée par l'intégration — cas favorable, il permettra le pilotage direct par entité HA sans code.

### 4.3 Étape 2 — Écriture de test

Sur le `.250` uniquement. Relever au préalable la puissance instantanée de référence (Grafana ou VRM → PV Inverter).

```bash
python3 - <<'EOF'
from pysolarmanv5 import PySolarmanV5
import time

REG = 40          # <-- adresse trouvee a l'etape 1

m = PySolarmanV5('192.168.1.250', 3871081176, port=8889,
                 mb_slave_id=1, verbose=True, socket_timeout=10)

avant = m.read_holding_registers(register_addr=REG, quantity=1)[0]
print(f"AVANT       : {avant}")

m.write_holding_register(register_addr=REG, value=50)
time.sleep(3)

relu = m.read_holding_registers(register_addr=REG, quantity=1)[0]
print(f"APRES write : {relu}")
print("OK" if relu == 50 else "ECHEC")

m.disconnect()
EOF
```

| Relecture | Interprétation |
|---|---|
| `50` | Write accepté → étape 3 |
| `100` | Write ignoré silencieusement — registre read-only sur ce firmware |
| Exception Modbus | Registre inexistant ou protégé → retour étape 1 |

### 4.4 Étape 3 — Vérification de l'effet réel *(étape décisive)*

Un registre peut accepter l'écriture sans que l'onduleur en tienne compte.

1. Attendre **60 à 90 s** — la consigne s'applique sur un cycle de régulation, pas instantanément.
2. Relever la puissance AC du `.250`.
3. Vérifier que le `.251` n'a **pas** bougé — contrôle négatif prouvant que la baisse ne vient pas d'un passage nuageux.

**Critère de réussite :** puissance du `.250` divisée par ~2, `.251` inchangé, confirmé sur deux relevés espacés d'une minute.

### 4.5 Étape 4 — Persistance au redémarrage

1. Laisser le `.250` à 50 %.
2. Couper l'alimentation AC du `.250` quelques secondes, puis rétablir.
3. Attendre le redémarrage complet (~2 min, self-check 65 s inclus).
4. Relire le registre.

| Résultat | Conséquence |
|---|---|
| `50` conservé | EEPROM persistante → limiter la fréquence d'écriture (usure) |
| Retour à `100` | Consigne volatile → resync périodique nécessaire dans HA |

Le second cas est **préférable** : pas d'usure EEPROM, et une panne de HA laisse les DEYE à pleine puissance plutôt que bridés indéfiniment.

### 4.6 Étape 5 — Restauration

```bash
python3 - <<'EOF'
from pysolarmanv5 import PySolarmanV5
REG = 40
m = PySolarmanV5('192.168.1.250', 3871081176, port=8889,
                 mb_slave_id=1, socket_timeout=10)
m.write_holding_register(register_addr=REG, value=100)
print("Restaure :", m.read_holding_registers(register_addr=REG, quantity=1)[0])
m.disconnect()
EOF
```

Puis :

```bash
ps aux | grep -i solarman        # verifier qu'aucun process ne subsiste
sleep 60                          # liberation du slot TCP
sudo systemctl start energymanager
# Reactiver l'integration Solarman dans HA
ha core logs | grep -i solarman | tail -20
```

### 4.7 Grille de décision

| Étapes 1–3 | Étape 4 | Décision |
|---|---|---|
| ✅ write + effet | volatile | **Cible validée** — implémenter §5 avec resync périodique |
| ✅ write + effet | persistant | Cible validée, rampe à pas espacés (≥ 30 s) |
| ✅ write, ❌ pas d'effet | — | **Cible abandonnée** — relais Shelly conservé, Soft Start permanent |
| ❌ write refusé | — | Idem |

### 4.8 Résultat du test

*(à compléter après exécution)*

| Champ | Valeur |
|---|---|
| Date d'exécution | |
| Registre identifié | |
| Échelle (% ou ‰) | |
| Write accepté | |
| Effet mesuré (W avant / après) | |
| Persistance | |
| Exposé comme entité HA | |
| **Décision** | |

---

## 5. Implémentation cible — Home Assistant

> À réaliser **uniquement** si §4.7 conclut « Cible validée ».

### 5.1 Seuils configurables

`configuration.yaml` :

```yaml
input_number:
  deye_power_bulk:
    name: "DEYE - puissance en Bulk"
    min: 0
    max: 100
    step: 5
    initial: 100
    unit_of_measurement: "%"
  deye_power_absorption:
    name: "DEYE - puissance en Absorption"
    min: 0
    max: 100
    step: 5
    initial: 60
    unit_of_measurement: "%"
  deye_power_float:
    name: "DEYE - puissance en Float"
    min: 0
    max: 100
    step: 5
    initial: 25
    unit_of_measurement: "%"
  deye_power_storage:
    name: "DEYE - puissance en Storage"
    min: 0
    max: 100
    step: 5
    initial: 0
    unit_of_measurement: "%"
  deye_ramp_step:
    name: "DEYE - pas de rampe"
    min: 5
    max: 50
    step: 5
    initial: 10
    unit_of_measurement: "%"
  deye_ramp_delay:
    name: "DEYE - delai entre pas"
    min: 5
    max: 60
    step: 5
    initial: 5
    unit_of_measurement: "s"

input_boolean:
  deye_regulation_enabled:
    name: "DEYE - regulation active"
    initial: on
```

### 5.2 Consigne cible

Template sensor calculant la consigne à partir de l'état MPPT publié par le Pi5 :

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
          {% else %}
            {% set s = states('sensor.mppt_state') | int(3) %}
            {% if   s == 4 %}{{ states('input_number.deye_power_absorption') | int }}
            {% elif s == 5 %}{{ states('input_number.deye_power_float')      | int }}
            {% elif s == 6 %}{{ states('input_number.deye_power_storage')    | int }}
            {% else %}       {{ states('input_number.deye_power_bulk')       | int }}
            {% endif %}
          {% endif %}
```

> **Repli sécurisé :** régulation désactivée ou état MPPT indisponible → 100 %. Jamais de bridage sur une donnée périmée.

### 5.3 Watchdog de fraîcheur MQTT

Équivalent HA de `input_max_age_secs = 90` :

```yaml
template:
  - binary_sensor:
      - name: "Pi5 telemetrie perimee"
        unique_id: pi5_telemetry_stale
        device_class: problem
        state: >
          {{ (as_timestamp(now())
              - as_timestamp(states.sensor.mppt_state.last_changed, 0)) > 90 }}
```

Si ce capteur passe à `on`, la télémétrie Pi5 est périmée : la consigne doit retomber à 100 % (condition à ajouter dans le template §5.2 une fois le nom d'entité confirmé).

### 5.4 Script de rampe

```yaml
script:
  deye_apply_power:
    alias: "DEYE - application progressive de la consigne"
    mode: restart
    sequence:
      - repeat:
          while:
            - condition: template
              value_template: >
                {{ (states('number.micro_inverter_250_active_power_regulation') | int(100))
                   != (states('sensor.deye_consigne_cible') | int(100)) }}
            - condition: template
              value_template: "{{ repeat.index <= 25 }}"
          sequence:
            - variables:
                courant: "{{ states('number.micro_inverter_250_active_power_regulation') | int(100) }}"
                cible: "{{ states('sensor.deye_consigne_cible') | int(100) }}"
                pas: "{{ states('input_number.deye_ramp_step') | int(10) }}"
            - variables:
                suivant: >
                  {% if cible > courant %}
                    {{ [courant + pas, cible] | min }}
                  {% else %}
                    {{ [courant - pas, cible] | max }}
                  {% endif %}
            - service: number.set_value
              target:
                entity_id:
                  - number.micro_inverter_250_active_power_regulation
                  - number.micro_inverter_251_active_power_regulation
              data:
                value: "{{ suivant }}"
            - delay:
                seconds: "{{ states('input_number.deye_ramp_delay') | int(5) }}"
```

> `mode: restart` — un changement de consigne pendant une rampe annule la rampe en cours et repart de l'état courant. Le garde `repeat.index <= 25` empêche toute boucle infinie.

### 5.5 Déclenchement

```yaml
automation:
  - alias: "DEYE - suivre la consigne"
    id: deye_follow_target
    mode: single
    trigger:
      - platform: state
        entity_id: sensor.deye_consigne_cible
      - platform: homeassistant
        event: start
      - platform: time_pattern
        minutes: "/5"          # resync periodique si consigne volatile (§4.5)
    condition:
      - condition: template
        value_template: "{{ states('sensor.deye_consigne_cible') not in ['unknown','unavailable'] }}"
    action:
      - service: script.turn_on
        target:
          entity_id: script.deye_apply_power
```

### 5.6 Noms d'entités à confirmer

Les identifiants ci-dessous sont des hypothèses tant que §4 n'est pas exécuté :

| Entité supposée | À vérifier |
|---|---|
| `number.micro_inverter_250_active_power_regulation` | présence dans les 55 entités du `.250` |
| `number.micro_inverter_251_active_power_regulation` | idem `.251` |
| `sensor.mppt_state` | nom réel du topic MQTT publié par le Pi5 |

---

## 6. Retrait de la logique côté Pi5

> À réaliser **après** validation de §5 en conditions réelles, jamais avant.

Travail à mener avec **Claude Code** connecté au dépôt `thieryus007-cloud/Daly-BMS-Rust`.

### 6.1 À supprimer

| Élément | Emplacement |
|---|---|
| Module de décision DEYE | `crates/energymanager/src/logic/deye_command/mod.rs` |
| Section `[energy_manager.deye]` complète | `Config.toml` |
| Pilotage du Shelly Pro 2PM | `energymanager` |

Y compris `freq_high_hz`, `freq_hard_hz`, `cut_delay_secs`, `reenable_delay_secs`, `relay_resync_secs`, `mppt_cut_enabled`, `mppt_full_states`, `input_max_age_secs`.

**Justification du retrait total :** la coupure par fréquence fonctionnait correctement avant l'introduction de ces règles, par le seul jeu du droop Victron et de l'auto-trip DEYE à 51.5 Hz. Ce filet matériel est indépendant de tout logiciel et suffit. Conserver une couche Rust intermédiaire ajouterait une dépendance sans bénéfice.

### 6.2 À conserver

| Élément | Rôle |
|---|---|
| BMS Daly / CAN | inchangé |
| RS485 | inchangé |
| reDB | inchangé — source Grafana |
| Publication MQTT `mppt_state`, fréquence AC, SOC | **devient l'unique interface vers HA** |

### 6.3 Ordre des opérations

1. Valider §5 en fonctionnement réel sur plusieurs journées de surproduction.
2. Désactiver la logique Rust par configuration (`mppt_cut_enabled = false`, seuils fréquence hors plage) — réversible.
3. Observer 1 à 2 semaines.
4. Supprimer le code, mettre à jour `Config.toml`, commit sur GitHub.
5. Vérifier que la publication MQTT reste intacte après suppression.

---

## 7. Points de vigilance

### 7.1 Soft Start — réglage transitoire

**À activer maintenant, à retirer après §5.**

Tant que la restauration se fait par relais, chaque reconnexion renvoie 3720 W instantanément sur la MultiPlus. Soft Start amortit cette montée.

Une fois la rampe HA opérationnelle, **repasser Soft Start à OFF** : deux rampes en série donnent un temps de montée mal défini, et la boucle HA verrait une réponse ne correspondant pas à sa consigne.

### 7.2 Island Protection — désactivé volontairement

Les DEYE sont sur AC Out 1, derrière la MultiPlus. Il n'y a pas de réseau au sens où l'entend le DEYE. Un anti-îlotage actif interpréterait la référence AC de la MultiPlus comme un réseau instable et provoquerait des décrochages intempestifs. **Configuration standard en AC-couplé derrière Victron — ne pas modifier.**

**Conséquence sécurité :** aucune protection active contre l'îlotage. Toute intervention sur l'AC Out 1 se fait après coupure **et** vérification d'absence de tension au multimètre. Ne jamais se fier au seul disjoncteur ouvert : les DEYE peuvent maintenir une tension résiduelle le temps de leur décrochage passif (sous-tension 184 V / sous-fréquence 47.5 Hz).

### 7.3 RISO — activé

Mesure d'isolement PV/terre avant chaque démarrage. Aucune interaction avec la régulation de fréquence ni avec le pilotage. En vallée ligure (humidité, écarts thermiques), c'est la protection qui détecte les MC4 infiltrés et les câbles blessés. **Ne pas désactiver.**

Si des non-démarrages matinaux apparaissent et se résolvent seuls dans la journée : condensation, pas faux positif. Ajuster le `Self-check time` (actuellement 65 s) plutôt que de couper RISO.

### 7.4 Contrainte du slot TCP unique

**Un seul client TCP par logger DEYE.** C'est la contrainte structurante de toute l'architecture.

Dans la cible, HA est le client unique. Interdits pendant le fonctionnement normal :

- script `pysolarmanv5` sur le Pi5 ;
- application mobile Solarman en local ;
- `Remote Server A` (cloud Solarman) actif ;
- tests `nc` répétés.

`Remote Server B` (`192.168.1.10:502`, vestige de la configuration TCP-Client) : **à vider sur les deux loggers** s'il ne l'est pas déjà.

### 7.5 Ajout futur de micro-onduleurs

Même modèle SUN-M200G4-EU-Q0, même AC Out 1, pas dans un avenir proche. À l'ajout :

1. Mettre à jour l'assistant *PV Inverter Support* : `Total installed PV inverter power` (actuellement 3720 W) et `Total installed PV panel power` (5580 W).
2. Vérifier la **règle du facteur 1.0** : la puissance PV AC-couplée ne doit pas dépasser la puissance nominale de la MultiPlus (5000 VA). Avec 2 DEYE on est à 3720 W ; un 3ᵉ porterait à 5580 W, **au-delà de la limite**. Un 3ᵉ micro-onduleur impose donc une réévaluation complète, pas un simple ajout.
3. Côté HA : une entrée d'intégration Solarman supplémentaire, ajout de l'entité dans la liste `target` du script §5.4.

### 7.6 Demande faite à DEYE (52.00 / 52.80 Hz)

Demande ancienne (> 8 mois), jamais appliquée. **Elle est incompatible avec la configuration actuelle** : la MultiPlus ne monte pas au-delà de 51.50 Hz avec l'assistant en place. Si ce firmware était appliqué, les DEYE ne décrocheraient jamais par fréquence et le filet matériel disparaîtrait.

**Action : confirmer auprès de DEYE que cette demande est annulée.**

### 7.7 Migration Grafana

Grafana lit reDB sur le Pi5. En cas de migration vers le Mac Mini, l'accès à reDB devra se faire par le réseau — à traiter dans un document dédié, sans impact sur le présent pilotage.

---

## 8. Feuille de route

| # | Action | État | Dépend de |
|---|---|---|---|
| 1 | Activer Over-Frequency Load Reduction sur les 2 DEYE | ✅ fait 23/07/2026 | — |
| 2 | Point de réduction à 50.6 Hz | ✅ fait 23/07/2026 | — |
| 3 | Activer Soft Start sur les 2 DEYE (transitoire) | ⬜ à faire | — |
| 4 | Vider `Remote Server B` sur les 2 loggers | ⬜ à vérifier | — |
| 5 | Confirmer annulation de la demande DEYE 52.00/52.80 Hz | ⬜ à faire | — |
| 6 | **Test `Active Power Regulation`** (§4) | ⬜ **bloquant** | météo + SOC intermédiaire |
| 7 | Compléter §4.8 avec les résultats | ⬜ | 6 |
| 8 | Implémenter §5 dans HA | ⬜ | 7 = validé |
| 9 | Observation en conditions réelles (plusieurs jours) | ⬜ | 8 |
| 10 | Désactiver Soft Start | ⬜ | 9 |
| 11 | Neutraliser la logique Rust par config (réversible) | ⬜ | 9 |
| 12 | Supprimer le code Rust — Claude Code + GitHub | ⬜ | 11 + 2 semaines |

---

## 9. Références

| Sujet | URL |
|---|---|
| Intégration Solarman | https://github.com/davidrapan/ha-solarman |
| Bibliothèque Python | https://pypi.org/project/pysolarmanv5/ |
| Dépôt energymanager | https://github.com/thieryus007-cloud/Daly-BMS-Rust |
| Dépôt HA | https://github.com/thieryus007-cloud/HA-Santuario |

---

*Document rédigé pour le projet Santuario — 23 juillet 2026.*
