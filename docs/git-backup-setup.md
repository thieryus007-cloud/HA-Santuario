# Configuration de la sauvegarde Git — HA-Santuario

> Documentation de la mise en place et de la validation du versionnement de la
> configuration Home Assistant vers le dépôt GitHub `thieryus007-cloud/HA-Santuario`.

**Date :** 21 juillet 2026
**Instance :** Home Assistant OS 18.1 / Core 2026.7.2 — Mac Mini M4
**IP HA :** 192.168.1.10
**Dépôt :** https://github.com/thieryus007-cloud/HA-Santuario
**Branche :** `main`
**Statut :** ✅ Opérationnel et validé

---

## 1. Objectif

Versionner et sauvegarder la configuration de Home Assistant (`/config`) vers un
dépôt GitHub privé, avec un flux de **push** fiable depuis le terminal HA.

## 2. Architecture retenue

Le pilotage de Git se fait **directement depuis le terminal** (add-on *Advanced SSH
& Web Terminal*), et non via l'add-on *Git pull*.

Raison : l'add-on *Git pull* échouait systématiquement avec l'erreur
`fatal: refusing to work with credential missing host field` (bug de parsing d'URL
de l'add-on). Le terminal contourne ce problème et permet en plus le **push**
(HA → GitHub), que l'add-on *Git pull* ne sait pas faire (sens unique GitHub → HA).

| Flux | Outil | Rôle |
|---|---|---|
| HA → GitHub (push / sauvegarde) | Terminal SSH + Git | Retenu |
| GitHub → HA (pull / déploiement) | Add-on Git pull | Écarté (bug + non nécessaire) |

## 3. Authentification

Méthode **HTTPS avec Personal Access Token** GitHub, injecté dans l'URL du remote.

Validation de l'accès effectuée avant toute opération :

```bash
git ls-remote https://thieryus007-cloud:<TOKEN>@github.com/thieryus007-cloud/HA-Santuario
```

Résultat obtenu (succès) :

```
741fc43352b266a32e0cdf4207161f2d1bedab06    HEAD
741fc43352b266a32e0cdf4207161f2d1bedab06    refs/heads/main
```

→ Token valide, URL correcte, branche `main` présente.

> **Note de sécurité :** le token est stocké en clair dans `/config/.git/config`.
> Acceptable en usage personnel. Pour l'éviter, basculer sur une clé SSH de
> déploiement. Vérifier la date d'expiration du token sur
> https://github.com/settings/tokens

## 4. Protection des secrets — `.gitignore`

Fichier `/config/.gitignore` créé **avant** tout commit pour exclure les données
sensibles et volumineuses :

```gitignore
secrets.yaml
*.log
*.db
*.db-*
home-assistant_v2.db*
.storage/
.cloud/
*.pid
.uuid
tts/
deps/
tmp/
*.log.*
```

✅ Vérifié : `secrets.yaml` **n'a pas** été poussé sur GitHub
(`git rm --cached secrets.yaml` a renvoyé `did not match any files`).

## 5. Procédure de mise en place (réalisée)

### 5.1 Création du `.gitignore`

```bash
cat > /config/.gitignore << 'EOF'
secrets.yaml
*.log
*.db
*.db-*
home-assistant_v2.db*
.storage/
.cloud/
*.pid
.uuid
tts/
deps/
tmp/
*.log.*
EOF
```

### 5.2 Initialisation du dépôt local

```bash
cd /config
git init
git branch -M main
git config user.name "thieryus007-cloud"
git config user.email "Thieryus007@icloud.com"
git remote add origin https://thieryus007-cloud:<TOKEN>@github.com/thieryus007-cloud/HA-Santuario
```

### 5.3 Réconciliation avec le dépôt distant

Le dépôt distant contenait déjà un commit (README initial). Fusion des historiques
non liés :

```bash
cd /config
git config pull.rebase false
git add .
git commit -m "Initial Home Assistant config"
git pull origin main --allow-unrelated-histories --no-edit
```

Résultat : `Merge made by the 'ort' strategy.` (`readme.md` intégré).

### 5.4 Push initial

```bash
git push -u origin main
```

Résultat (succès) :

```
Enumerating objects: 1953, done.
Writing objects: 100% (1952/1952), 10.22 MiB | 694.00 KiB/s, done.
To https://github.com/thieryus007-cloud/HA-Santuario
   741fc43..105aaf6  main -> main
branch 'main' set up to track 'origin/main'.
```

→ 1952 objets poussés, branche `main` suivie.

## 6. Validation

| Contrôle | Résultat |
|---|---|
| Authentification GitHub (`git ls-remote`) | ✅ OK |
| Branche `main` présente sur le distant | ✅ OK |
| `.gitignore` actif | ✅ OK |
| `secrets.yaml` exclu du dépôt | ✅ OK (absent) |
| Push initial | ✅ OK (`741fc43..105aaf6`) |
| Suivi `origin/main` | ✅ OK |
| Fichiers visibles sur GitHub | ✅ OK |

## 7. Utilisation courante — sauvegardes futures

À chaque sauvegarde de la configuration :

```bash
cd /config
git add .
git commit -m "Update config $(date +%F)"
git push
```

## 8. Maintenance du token

En cas d'expiration ou de rotation du token :

```bash
cd /config
git remote set-url origin https://thieryus007-cloud:<NOUVEAU_TOKEN>@github.com/thieryus007-cloud/HA-Santuario
```

---

## Récapitulatif

La configuration Home Assistant de **Santuario** est désormais versionnée et
sauvegardée sur GitHub (`HA-Santuario`, branche `main`), avec un flux de push
fiable depuis le terminal HA et une exclusion vérifiée des données sensibles.
