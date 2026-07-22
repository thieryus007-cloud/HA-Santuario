# Export automatique des entités Home Assistant vers CSV + GitHub — Santuario

> Export complet des entités HA au format CSV, exploitable dans Excel, avec push
> automatique vers le dépôt GitHub. Déclenchement quotidien et à la demande.

**Date :** 22 juillet 2026
**Instance :** Home Assistant OS 18.1 / Core 2026.7.2 — `192.168.1.10`
**Dépôt :** `thieryus007-cloud/HA-Santuario` — dossier `docs/`
**Fichier produit :** `docs/entities_export.csv`

---

## 1. Principe

Trois éléments s'enchaînent :

1. Un **script HA** génère le CSV via l'entité `notify.file` (intégration File).
2. Un **shell_command** nettoie le fichier, ajoute le BOM UTF-8, et pousse vers GitHub.
3. Une **automatisation** déclenche le tout chaque soir à 23h30.

## 2. Intégration File (notifier)

> La plateforme `notify.file` en YAML est **supprimée** depuis HA 2026.x
> (erreur `Invalid notify platform`). Elle doit être créée via l'interface.

Paramètres → Appareils et services → **Ajouter une intégration** → **File** → Notifier :

- Chemin du fichier : `/config/www/entities_export.csv`
- Horodatage : désactivé

L'entité créée est **`notify.file`** (vérifiable dans Paramètres → Entités).

> L'intégration File **ajoute** au fichier (append), elle ne l'écrase jamais.
> Le script shell se charge de le vider après chaque export.

## 3. Script d'export — `/config/scripts.yaml`

```yaml
export_entities_csv:
  alias: "Export entités CSV complet"
  sequence:
    - action: notify.send_message
      target:
        entity_id: notify.file
      data:
        message: |-
          entity_id;domain;friendly_name;state;unit;device_class;state_class;area;device;integration;last_changed
          {%- for s in states %}
          {{ s.entity_id }};{{ s.domain }};{{ s.name }};{{ s.state }};{{ s.attributes.unit_of_measurement | default('') }};{{ s.attributes.device_class | default('') }};{{ s.attributes.state_class | default('') }};{{ area_name(s.entity_id) | default('') }};{{ device_attr(s.entity_id, 'name') | default('') }};{{ device_attr(s.entity_id, 'manufacturer') | default('') }};{{ s.last_changed }}
          {%- endfor %}
    - delay: "00:00:05"
    - action: shell_command.push_entities_github
    - action: persistent_notification.create
      data:
        title: "Export entités terminé"
        message: >-
          {{ states | count }} entités exportées.
```

Points de syntaxe importants :

- `message: |-` (literal scalar) et non `>-` : le `>-` remplace les retours à la
  ligne par des espaces, ce qui produit un fichier d'une seule ligne géante.
- `{%- for %}` / `{%- endfor %}` : supprime les lignes vides parasites.
- Séparateur **`;`** : reconnu nativement par Excel. Les tabulations ne survivent
  pas au collage YAML, et la virgule casse le CSV (les noms d'entités en contiennent).
- La colonne `attributes` a été retirée : ses virgules éclataient le fichier en
  colonnes parasites dans Excel.
- Dans `scripts.yaml`, **pas de préfixe `script:`** (il n'existe que dans
  `configuration.yaml`), sinon erreur `extra keys not allowed`.

## 4. Shell command — `/config/configuration.yaml`

```yaml
shell_command:
  push_entities_github: bash /config/docs/push_entities.sh
```

> `shell_command` ne se recharge pas à chaud : **redémarrage complet de HA requis**
> après ajout.

## 5. Script de nettoyage et push — `/config/docs/push_entities.sh`

```bash
cat > /config/docs/push_entities.sh << 'EOF'
#!/bin/bash
cd /config
printf '\xEF\xBB\xBF' > docs/entities_export.csv
grep -v "^Home Assistant notifications" www/entities_export.csv | grep -v "^-----" | grep -v "^$" | sed 's/^[0-9-]*T[0-9:.]*+[0-9:]* //' >> docs/entities_export.csv
> www/entities_export.csv
git add docs/entities_export.csv
git commit -m "Update entities export $(date +%Y-%m-%d_%H:%M)" || exit 0
git push
EOF
chmod +x /config/docs/push_entities.sh
```

Rôle de chaque ligne :

| Ligne | Rôle |
|---|---|
| `printf '\xEF\xBB\xBF'` | Écrit le **BOM UTF-8** : Excel détecte l'encodage seul, les accents s'affichent correctement (`Extérieur` et non `Extÿ©rieur`) |
| `grep -v "^Home Assistant notifications"` | Retire la ligne d'en-tête ajoutée par l'intégration File |
| `grep -v "^-----"` | Retire la ligne de séparation |
| `grep -v "^$"` | Retire les lignes vides |
| `sed 's/^[0-9-]*T[0-9:.]*+[0-9:]* //'` | Retire l'horodatage préfixé par l'intégration File |
| `> www/entities_export.csv` | **Vide** le fichier source (sinon accumulation à chaque export) |
| `git add / commit / push` | Publie vers GitHub. Le `\|\| exit 0` évite l'erreur si rien n'a changé |

## 6. Automatisation quotidienne — `/config/automations.yaml`

```yaml
- alias: "Export entités quotidien"
  trigger:
    - platform: time
      at: "23:30:00"
  action:
    - action: script.export_entities_csv
```

## 7. Lancement à la demande

**Depuis les Outils de développement :**
Outils de développement → onglet **Actions** → `script.export_entities_csv` →
**Effectuer une action**.

**Depuis un tableau de bord** (carte à ajouter) :

```yaml
type: button
name: Export entités CSV
icon: mdi:file-export
tap_action:
  action: call-service
  service: script.export_entities_csv
```

## 8. Colonnes produites

| Colonne | Usage |
|---|---|
| `entity_id` | Chemin exact pour automatisations et cards |
| `domain` | sensor, switch, binary_sensor… — filtrage par type |
| `friendly_name` | Nom affiché |
| `state` | Valeur courante (repérer les `unavailable`) |
| `unit` | Unité de mesure |
| `device_class` | Classe d'appareil |
| `state_class` | Classe d'état (tableau Énergie) |
| `area` | Pièce assignée |
| `device` | Appareil parent |
| `integration` | Fabricant / intégration d'origine |
| `last_changed` | Dernier changement d'état |

## 9. Mise à jour manuelle vers GitHub

Depuis SSH/Tabby sur HA :

```bash
cd /config
bash docs/push_entities.sh
```

Ou pour un document quelconque :

```bash
cd /config
git add docs/<fichier>
git commit -m "Description"
git push
```

## 10. Vérifications

```bash
# Format du fichier produit
head -3 /config/docs/entities_export.csv

# Nombre de lignes (doit correspondre au nombre d'entités + 1)
wc -l /config/docs/entities_export.csv

# Dernier commit
cd /config && git log -1 --oneline
```

Résultat attendu en première ligne :
`entity_id;domain;friendly_name;state;unit;device_class;state_class;area;device;integration;last_changed`

## 11. Dépannage

| Symptôme | Cause | Correction |
|---|---|---|
| `Invalid notify platform` | `notify.file` en YAML déprécié | Créer l'intégration File via l'interface |
| `Action notify.entities_export not found` | Ancien nom de service | Utiliser `notify.send_message` + `target: notify.file` |
| `extra keys not allowed` | Préfixe `script:` dans `scripts.yaml` | Retirer le préfixe |
| Fichier sur une seule ligne | `message: >-` au lieu de `\|-` | Utiliser `\|-` |
| Contenu qui s'accumule | L'intégration File fait de l'append | Vider le fichier dans le script shell |
| Accents illisibles dans Excel | Pas de BOM UTF-8 | `printf '\xEF\xBB\xBF'` en début de fichier |
| Colonnes parasites | Colonne `attributes` contenant des virgules | Retirer cette colonne du template |

---

## Récapitulatif

L'export des entités se déclenche chaque soir à 23h30 et à la demande. Il produit
un CSV à 11 colonnes séparées par `;`, encodé UTF-8 avec BOM pour Excel, nettoyé
des artefacts de l'intégration File, puis poussé automatiquement dans `docs/` du
dépôt GitHub. Le fichier sert de référence pour retrouver les `entity_id` lors de
la création d'automatisations et de cards.
