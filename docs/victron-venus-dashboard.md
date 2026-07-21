# Carte Victron Venus OS Dashboard — Santuario

> Mise en place, dans Home Assistant, d'une carte reproduisant le flux d'énergie
> du GUI Victron (Venus OS GUIv2), et inventaire des entités Victron disponibles.

**Date :** 21 juillet 2026
**Instance :** Home Assistant OS 18.1 (VM UTM, Mac Mini M4)
**Carte :** `custom:venus-os-dashboard` (skydarc / acdcnow, via HACS) — v0.7.0
**Dashboard HA :** « Victron »
**Statut :** ✅ Carte fonctionnelle, 6 blocs mappés

---

## 1. Installation (rappel)

1. **HACS** installé (`wget -O - https://get.hacs.xyz | bash -`, puis intégration HACS + appairage GitHub).
2. Dépôt personnalisé ajouté dans HACS : `https://github.com/acdcnow/Victron-Venus-Dashboard`, catégorie **Dashboard/Lovelace**.
3. Carte téléchargée → fichier dans `/config/www/community/Venus-OS-Dashboard/`.
4. Ressource Lovelace : `/hacsfiles/Venus-OS-Dashboard/Venus-OS-Dashboard.js` (Module JavaScript) — ajoutée automatiquement par HACS.
5. Dashboard « Victron » créé, carte ajoutée dans une section, configurée via l'éditeur de code.

> Piège rencontré : ne PAS coller le YAML de la carte dans « Modifier la
> configuration » du dashboard entier (erreur `views: expected an array`). Le YAML
> de la carte va dans **crayon de la carte → Afficher l'éditeur de code**.

## 2. Configuration YAML utilisée (fonctionnelle)

```yaml
type: custom:venus-os-dashboard
param:
  boxCol1: 2
  boxCol3: 2
theme: dark
styles:
  header: 10
  sensor: 16
devices:
  1-1:
    icon: mdi:transmission-tower
    name: Réseau
    entity: sensor.et112_reseau_id_31_power_on_l1
    anchors: R-1
    link:
      "1":
        start: R-1
        end: 2-1_L-1
  1-2:
    icon: mdi:battery-charging
    name: Batterie
    entity: sensor.smartshunt_300a_id_274_charge
    anchors: R-1
    gauge: "true"
    link:
      "1":
        start: R-1
        end: 2-1_L-2
        entity: sensor.gx_device_dc_battery_power
  2-1:
    icon: mdi:sync
    name: Inverter / Charger
    entity: sensor.multiplus_ii_48_5000_70_50_id_275_state
    anchors: L-2, R-2
  3-1:
    icon: mdi:home-lightning-bolt
    name: Maison
    entity: sensor.et112_maison_id_30_power_on_l1
    anchors: L-1
    link:
      "1":
        start: L-1
        end: 2-1_R-1
  3-2:
    icon: mdi:weather-sunny
    name: Solaire
    entity: sensor.gx_device_pv_power
    anchors: L-1
    link:
      "1":
        start: L-1
        end: 2-1_R-2
        entity: sensor.gx_device_pv_power
        inv: "true"
  3-3:
    icon: mdi:power-plug
    name: DC Loads
    entity: sensor.gx_device_dc_consumption
    anchors: L-1
```

## 3. Mapping des blocs (entités UTILISÉES)

| Bloc carte | Entité | Rôle | Valeur type |
|---|---|---|---|
| Réseau | `sensor.et112_reseau_id_31_power_on_l1` | Puissance réseau (ET112) | 0 W |
| Batterie (SOC + jauge) | `sensor.smartshunt_300a_id_274_charge` | État de charge % | 99,5 % |
| Batterie (lien/flux) | `sensor.gx_device_dc_battery_power` | Puissance DC batterie | variable |
| Inverter / Charger | `sensor.multiplus_ii_48_5000_70_50_id_275_state` | État VE.Bus (texte) | inverting |
| Maison | `sensor.et112_maison_id_30_power_on_l1` | Consommation maison (ET112) | ~1670 W |
| Solaire | `sensor.gx_device_pv_power` | Puissance PV totale | ~1860 W |
| DC Loads | `sensor.gx_device_dc_consumption` | Charges DC | ~-2 W |

## 4. Inventaire complet des entités Victron disponibles

Toutes les entités relevées, y compris celles **NON encore utilisées** dans la
carte. À exploiter pour enrichir la carte ou créer d'autres tableaux de bord.

### 4.1 GX Device (système agrégé)

| Entité | Description |
|---|---|
| `sensor.gx_device_pv_power` | Puissance PV totale ✅ utilisé |
| `sensor.gx_device_pv_energy` | Énergie PV |
| `sensor.gx_device_pv_current` | Courant PV |
| `sensor.gx_device_pv_on_output_power_l1` | PV sur sortie L1 |
| `sensor.gx_device_pv_on_output_phases` | PV sur sortie (phases) |
| `sensor.gx_device_dc_battery_power` | Puissance DC batterie ✅ utilisé |
| `sensor.gx_device_dc_battery_current` | Courant DC batterie |
| `sensor.gx_device_dc_battery_voltage` | Tension DC batterie |
| `sensor.gx_device_dc_battery_charge` | Charge DC batterie |
| `sensor.gx_device_dc_battery_charge_energy` | Énergie chargée |
| `sensor.gx_device_dc_battery_discharge_energy` | Énergie déchargée |
| `sensor.gx_device_dc_consumption` | Consommation DC (DC Loads) ✅ utilisé |
| `sensor.gx_device_consumption_power_l1` | Consommation AC L1 |
| `sensor.gx_device_consumption_current_l1` | Courant consommation L1 |
| `sensor.gx_device_critical_loads_on_l1` | Charges critiques L1 |
| `sensor.gx_device_grid_power_l1` | Puissance réseau L1 (GX) |
| `sensor.gx_device_grid_current_l1` | Courant réseau L1 |
| `sensor.gx_device_grid_phases` | Réseau (phases) |
| `sensor.gx_device_dc_battery_state` | État batterie DC |
| `sensor.gx_device_system_state` | État système |
| `sensor.gx_device_ess_batterylife_state` | État ESS BatteryLife |
| `sensor.gx_device_dynamic_ess_target_soc` | Cible SOC ESS dynamique |

### 4.2 SmartShunt 300A (ID: 274) — batterie principale

| Entité | Description |
|---|---|
| `sensor.smartshunt_300a_id_274_charge` | SOC % ✅ utilisé |
| `sensor.smartshunt_300a_id_274_power` | Puissance batterie |
| `sensor.smartshunt_300a_id_274_capacity` | Capacité |
| `sensor.smartshunt_300a_id_274_dc_bus_voltage` | Tension bus DC |
| `sensor.smartshunt_300a_id_274_dc_bus_current` | Courant bus DC |
| `sensor.smartshunt_300a_id_274_charged_energy` | Énergie chargée |
| `sensor.smartshunt_300a_id_274_discharged_energy` | Énergie déchargée |
| `sensor.smartshunt_300a_id_274_total_charge_cycles` | Cycles de charge |
| `sensor.smartshunt_300a_id_274_time_to_go` | Autonomie restante |

### 4.3 MultiPlus-II 48/5000/70-50 (ID: 275)

| Entité | Description |
|---|---|
| `sensor.multiplus_ii_48_5000_70_50_id_275_state` | État VE.Bus (inverting/charging) ✅ utilisé |
| `...id_275_state_of_ignore_ac_in_1` | État ignore AC-in-1 |
| `...id_275_grid_lost_alarm` | Alarme perte réseau |
| `...id_275_grid_lost_alarm_setting` | Réglage alarme perte réseau |

### 4.4 SmartSolar MPPT VE.Can 250/100 rev2 (ID: 273) — MPPT principal

| Entité | Description |
|---|---|
| `sensor.smartsolar_mppt_ve_can_250_100_rev2_id_273_pv_yield_power` | Puissance PV (~1751 W) |
| `sensor.smartsolar_mppt_ve_can_250_100_rev2_id_273_state` | État |
| `binary_sensor.smartsolar_mppt_ve_can_250_100_rev2_id_273_load_state` | État charge |
| `sensor.smartsolar_mppt_ve_can_250_100_rev2_id_273_pv_bus_voltage` | Tension bus PV |

### 4.5 SmartSolar Charger MPPT 150/35 (ID: 289) — MPPT secondaire

| Entité | Description |
|---|---|
| `sensor.smartsolar_charger_mppt_150_35_id_289_pv_yield_power` | Puissance PV (~5 W) |
| `sensor.smartsolar_charger_mppt_150_35_id_289_state` | État |
| `binary_sensor.smartsolar_charger_mppt_150_35_id_289_load_state` | État charge |
| `sensor.smartsolar_charger_mppt_150_35_id_289_pv_bus_voltage` | Tension bus PV |

### 4.6 Compteurs ET112

| Entité | Description |
|---|---|
| `sensor.et112_reseau_id_31_power_on_l1` | Puissance réseau (ID 31) ✅ utilisé |
| `sensor.et112_maison_id_30_power_on_l1` | Puissance maison (ID 30) ✅ utilisé |
| `sensor.et112_micro_onduleurs_power_l1` | Puissance micro-onduleurs (DEYE) |

### 4.7 Autres (relais, sorties)

Relais et sorties GX disponibles (`Output 1/2 ID:50`, `Relay 2/3 ID:50`) avec
entités `State` — non détaillés ici, à explorer si besoin d'automatisations.

## 5. Pistes d'enrichissement (à faire plus tard)

- **Détail par MPPT** : ajouter une carte complémentaire (jauges/entités) avec
  `...id_273_pv_yield_power` et `...id_289_pv_yield_power` pour voir chaque
  chargeur solaire séparément.
- **Micro-onduleurs DEYE** : exploiter `sensor.et112_micro_onduleurs_power_l1`.
- **Autonomie / cycles batterie** : afficher `time_to_go` et `total_charge_cycles`.
- **Énergies cumulées** : `charged_energy` / `discharged_energy` / `pv_energy`.
- **Tensions/températures cellules** : via les BMS Daly (packs 320/360 Ah).

## 6. Remarques

- La carte Venus reproduit le GUI Victron officiel, qui **n'affiche pas** le
  détail par MPPT (juste le total PV) — le bloc Solaire actuel est donc correct.
- Ce dashboard est stocké côté HA (préférences UI), non versionné dans le dépôt
  Git (`.storage` exclu). Ce fichier de suivi sert de référence pour reconstruire
  ou enrichir la carte.

---

## Récapitulatif

La carte Venus OS Dashboard reproduit le flux d'énergie Victron dans Home
Assistant, avec 6 blocs mappés sur les vraies entités (ET112 réseau/maison,
SmartShunt SOC, MultiPlus état, PV total, DC loads). L'inventaire complet des
entités Victron ci-dessus permet d'enrichir progressivement l'affichage.
