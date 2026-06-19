#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# commit-nextcloud-external.sh
#
# À exécuter à la racine du dépôt local devops_staging_prod_infra.
#
# Implémente la décision finale : Nextcloud reste un service externe pur
# (project_type: external_service), jamais déployé par Ansible, sans rôle
# nextcloud_stack, sans pattern stateful_bootstrap.
#
# IMPORTANT — avant de lancer ce script :
#   Le vault STAGING est chiffré : ce script ne le modifie PAS. Une fois le
#   commit appliqué, retirez manuellement les 4 clés devenues orphelines :
#
#     ansible-vault edit inventories/staging/group_vars/all/vault.yml
#
#   Retirer ces 4 lignes :
#     vault_nextcloud_admin_user
#     vault_nextcloud_admin_password
#     vault_nextcloud_db_user
#     vault_nextcloud_db_password
#
#   Le vault PRODUCTION est en clair : ce script retire ces clés directement.
#
# Ce script ne touche PAS à main : il committe sur la branche courante.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

echo "==> Vérification du dépôt..."

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERREUR : ce répertoire n'est pas un dépôt git."
  exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)
echo "    Branche actuelle : $CURRENT_BRANCH"

REQUIRED_FILES=(
  "inventories/staging/group_vars/all/main.yml"
  "inventories/production/group_vars/all/main.yml"
  "inventories/production/group_vars/all/vault.yml"
  "playbooks/site.yml"
  "playbooks/deploy-apps.yml"
  "playbooks/deploy-proxy.yml"
  "playbooks/deploy-nextcloud.yml"
  "roles/nextcloud_stack/tasks/main.yml"
  "roles/caddy_proxy/templates/Caddyfile.j2"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERREUR : '$f' introuvable. Vérifie que tu es à la racine du dépôt"
    echo "et que la structure correspond à l'état attendu (group_vars/all/ déjà en place)."
    exit 1
  fi
done

echo "    OK — fichiers attendus présents."

echo ""
echo "==> 1/9 — inventories/staging/group_vars/all/main.yml"
cat > inventories/staging/group_vars/all/main.yml << 'STAGINGMAIN_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Variables communes — Staging
# Les secrets sont dans vault.yml (chiffré Ansible Vault).
# ─────────────────────────────────────────────────────────────────────────────

environment_name: staging
lavallee_domain: lavallee.local
facturier_domain: facturier.local
grav_docs_domain: docs.lavallee.local

# Utilisateur de déploiement créé sur chaque VM
deploy_user: devops

# Répertoire racine des applications sur les VMs
apps_base_dir: /opt

# ── Caddy ────────────────────────────────────────────────────────────────────
# En staging : pas de Let's Encrypt, certificats auto-signés Caddy (tls internal)
caddy_tls_mode: internal   # "internal" | "acme"
caddy_email: ""            # inutile en staging

# ── Registre de projets ───────────────────────────────────────────────────────
# Chemin local des fichiers projets (relatif au dépôt)
projects_vars_dir: "{{ playbook_dir }}/../vars/projects"

# Liste des fichiers projets à charger (sans extension).
# Ajouter une nouvelle app = ajouter son nom ici + créer vars/projects/<app>.yml
#
# Note sur "nextcloud" : ce projet est de type external_service (voir
# vars/projects/nextcloud.yml et README.md, section "Services externes").
# Il n'est JAMAIS déployé par deploy-apps.yml — il sert uniquement à
# déclarer le routage Caddy vers la VM Nextcloud, administrée manuellement.
active_projects:
  - lavallee-website
  - facturier-landing
  - facturier-app
  - grav-docs
  - nextcloud

# ── Backends Caddy ────────────────────────────────────────────────────────────
# Adresse IP ou hostname de la VM qui héberge les apps.
# Caddy (sur vm-proxy) forward vers cette adresse + le host_port du projet.
backend_host: 192.168.1.58

# Adresse IP ou hostname de la VM Nextcloud (service externe, voir ci-dessus).
nextcloud_backend_host: 192.168.1.59

# ── Nextcloud (service externe — voir README.md) ──────────────────────────────
# Nextcloud n'est PAS déployé par ce dépôt. Ces deux variables ne servent
# qu'au routage Caddy (vars/projects/nextcloud.yml), pas à un déploiement.
# Toute variable de secret (admin, DB) a été retirée : ces secrets vivent
# uniquement dans le docker-compose.yml manuel sur vm-nextcloud-staging.
nextcloud_domain: cloud.lavallee.local
nextcloud_host_port: 8080

# ── Grav (grav-docs) ──────────────────────────────────────────────────────────
# Bootstrap admin optionnel (voir vars/projects/grav-docs.yml et le rôle
# grav_stack). Activé en staging : un compte admin est créé automatiquement
# au premier déploiement si aucun compte du même nom n'existe déjà.
# Secrets définis dans vault.yml (ansible-vault edit inventories/staging/group_vars/vault.yml)
grav_admin_user: "{{ vault_grav_admin_user }}"
grav_admin_password: "{{ vault_grav_admin_password }}"
grav_admin_email: "{{ vault_grav_admin_email }}"
STAGINGMAIN_EOF

echo ""
echo "==> 2/9 — inventories/production/group_vars/all/main.yml"
cat > inventories/production/group_vars/all/main.yml << 'PRODMAIN_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Variables communes — Production
# Les secrets sont dans vault.yml (chiffré Ansible Vault).
# ─────────────────────────────────────────────────────────────────────────────

environment_name: production
lavallee_domain: lavallee.tech
facturier_domain: facturier.lavallee.tech
grav_docs_domain: docs.lavallee.tech

deploy_user: deploy
apps_base_dir: /opt

# ── Caddy ────────────────────────────────────────────────────────────────────
# En production : Let's Encrypt via ACME
caddy_tls_mode: acme
caddy_email: admin@lavallee.tech

# ── Registre de projets ───────────────────────────────────────────────────────
projects_vars_dir: "{{ playbook_dir }}/../vars/projects"

# Note sur "nextcloud" : voir le commentaire équivalent dans
# inventories/staging/group_vars/all/main.yml — project_type: external_service,
# jamais déployé par deploy-apps.yml.
active_projects:
  - lavallee-website
  - facturier-landing
  - facturier-app
  - grav-docs
  - nextcloud

# ── Backends Caddy ────────────────────────────────────────────────────────────
backend_host: 10.20.1.11

# Adresse IP ou hostname de la VM Nextcloud (service externe, voir ci-dessus).
nextcloud_backend_host: 10.20.1.12

# ── Nextcloud (service externe — voir README.md) ──────────────────────────────
# Nextcloud n'est PAS déployé par ce dépôt. Ces deux variables ne servent
# qu'au routage Caddy (vars/projects/nextcloud.yml), pas à un déploiement.
nextcloud_domain: nextcloud.lavallee.tech
nextcloud_host_port: 8080

# ── Grav (grav-docs) ──────────────────────────────────────────────────────────
# Bootstrap admin optionnel (voir vars/projects/grav-docs.yml et le rôle
# grav_stack). Ces variables sont préparées par cohérence avec staging, mais
# ne sont PAS encore activées en production : les clés vault_grav_admin_*
# correspondantes n'ont pas encore été ajoutées à vault.yml. Tant qu'elles
# sont absentes, le bootstrap admin de l'image grav-docs reste désactivé
# (les trois variables GRAV_ADMIN_* seront vides côté conteneur).
grav_admin_user: "{{ vault_grav_admin_user | default('') }}"
grav_admin_password: "{{ vault_grav_admin_password | default('') }}"
grav_admin_email: "{{ vault_grav_admin_email | default('') }}"
PRODMAIN_EOF

echo ""
echo "==> 3/9 — inventories/production/group_vars/all/vault.yml (en clair, retrait direct)"
cat > inventories/production/group_vars/all/vault.yml << 'PRODVAULT_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# VAULT — Production
# Ce fichier doit être chiffré : ansible-vault encrypt inventories/production/group_vars/all/vault.yml
#
# Aucun secret Nextcloud ici : Nextcloud est un service externe
# (project_type: external_service), non déployé par ce dépôt. Ses secrets
# vivent uniquement dans le docker-compose.yml manuel de vm-nextcloud-prod.
# Voir README.md, section "Services externes".
# ─────────────────────────────────────────────────────────────────────────────

# (Aucune clé pour l'instant — les clés vault_grav_admin_* n'ont pas encore
# été ajoutées en production, voir inventories/production/group_vars/all/main.yml)
PRODVAULT_EOF

echo ""
echo "==> 4/9 — vars/projects/nextcloud.yml (nouveau)"
cat > vars/projects/nextcloud.yml << 'NEXTCLOUDPROJ_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Projet : nextcloud
# Service EXTERNE — non déployé par ce dépôt.
#
# Nextcloud, PostgreSQL et Redis sont installés et administrés manuellement
# sur vm-nextcloud-staging / vm-nextcloud-prod, via un docker-compose.yml et
# des secrets qui vivent UNIQUEMENT sur cette VM — jamais dans ce dépôt, ni
# dans Ansible Vault. Ce fichier ne sert qu'à déclarer le routage Caddy.
#
# project_type: external_service n'est JAMAIS inclus dans les boucles de
# déploiement de playbooks/deploy-apps.yml — voir le commentaire à cet
# endroit, et README.md, section "Services externes", pour la justification
# complète de cette décision d'architecture.
#
# Pourquoi pas un pattern "stateful_service" dédié ?
# Cette option a été explorée et explicitement écartée : introduire un
# nouveau pattern d'exploitation (génération de compose/.env, bootstrap
# conditionnel, garde anti-relance) pour un seul service ne se justifiait
# pas. Si plusieurs services stateful similaires (Keycloak, Gitea, ...)
# rejoignent l'infrastructure, ce pattern redeviendra pertinent — voir
# README.md, section "Services externes", pour le détail de cette décision.
# ─────────────────────────────────────────────────────────────────────────────
project_name: nextcloud
project_type: external_service
domain: "{{ nextcloud_domain }}"
route_path: /
host_port: "{{ nextcloud_host_port }}"
backend_host: "{{ nextcloud_backend_host }}"
NEXTCLOUDPROJ_EOF

echo ""
echo "==> 5/9 — playbooks/site.yml"
cat > playbooks/site.yml << 'SITEYML_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# site.yml — Déploiement complet de l'infrastructure
#
# Usage :
#   ansible-playbook -i inventories/staging/hosts.yml playbooks/site.yml --ask-vault-pass
#   ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml --ask-vault-pass
#
# Note : Nextcloud n'est pas déployé par ce dépôt (project_type:
# external_service). Il n'y a donc pas de "deploy-nextcloud.yml" ici — son
# routage est inclus dans "Deploy reverse proxy" comme tout autre projet.
# Voir README.md, section "Services externes".
# ─────────────────────────────────────────────────────────────────────────────
- name: Provision Docker hosts
  ansible.builtin.import_playbook: deploy-docker-host.yml
- name: Deploy applications
  ansible.builtin.import_playbook: deploy-apps.yml
- name: Deploy reverse proxy
  ansible.builtin.import_playbook: deploy-proxy.yml
SITEYML_EOF

echo ""
echo "==> 6/9 — playbooks/deploy-apps.yml"
cat > playbooks/deploy-apps.yml << 'DEPLOYAPPS_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# deploy-apps.yml
#
# Charge le registre de projets depuis vars/projects/*.yml,
# puis déploie chaque projet de type docker_app ou grav_stack.
#
# Pour ajouter une nouvelle application :
#   1. Créer vars/projects/<app>.yml
#   2. Ajouter le nom dans active_projects (inventories/*/group_vars/all/main.yml)
#   → Aucun rôle à modifier.
#
# IMPORTANT : project_type: external_service n'est JAMAIS inclus dans les
# boucles ci-dessous. Ces projets (ex: nextcloud) sont routés par caddy_proxy
# uniquement (voir playbooks/deploy-proxy.yml) — leur cycle de vie applicatif
# est géré manuellement, hors de ce dépôt. Voir README.md, section
# "Services externes", pour la justification complète.
# ─────────────────────────────────────────────────────────────────────────────
- name: Load project registry and deploy applications
  hosts: apps
  become: true

  pre_tasks:
    - name: Load project definitions from vars/projects/
      ansible.builtin.include_vars:
        file: "{{ projects_vars_dir }}/{{ item }}.yml"
        name: "_proj_{{ item | replace('-', '_') }}"
      loop: "{{ active_projects }}"
      tags: always

    - name: Build projects list
      ansible.builtin.set_fact:
        projects: >-
          {{
            active_projects
            | map('replace', '-', '_')
            | map('regex_replace', '^(.*)$', '_proj_\1')
            | map('extract', hostvars[inventory_hostname])
            | list
          }}
      tags: always

  tasks:
    - name: Deploy docker_app projects
      ansible.builtin.include_role:
        name: docker_app
      vars:
        project: "{{ item }}"
      loop: "{{ projects | selectattr('project_type', 'equalto', 'docker_app') | list }}"
      loop_control:
        label: "{{ item.project_name }}"

    - name: Deploy grav_stack projects
      ansible.builtin.include_role:
        name: grav_stack
      vars:
        project: "{{ item }}"
      loop: "{{ projects | selectattr('project_type', 'equalto', 'grav_stack') | list }}"
      loop_control:
        label: "{{ item.project_name }}"
DEPLOYAPPS_EOF

echo ""
echo "==> 7/9 — playbooks/deploy-proxy.yml"
cat > playbooks/deploy-proxy.yml << 'DEPLOYPROXY_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# deploy-proxy.yml
#
# Charge le registre de projets (vars/projects/*.yml), construit la liste
# complète des routes, puis génère et recharge le Caddyfile.
#
# Tous les types de projets sont routés ici, y compris project_type:
# external_service (ex: nextcloud) — caddy_proxy n'a aucune notion de qui
# déploie réellement le service derrière une route, il route uniquement
# vers project.backend_host / project.host_port.
# ─────────────────────────────────────────────────────────────────────────────
- name: Deploy Caddy reverse proxy
  hosts: proxy
  become: true

  pre_tasks:
    - name: Load project definitions from vars/projects/
      ansible.builtin.include_vars:
        file: "{{ projects_vars_dir }}/{{ item }}.yml"
        name: "_proj_{{ item | replace('-', '_') }}"
      loop: "{{ active_projects }}"
      tags: always

    - name: Build projects list
      ansible.builtin.set_fact:
        projects: >-
          {{
            active_projects
            | map('replace', '-', '_')
            | map('regex_replace', '^(.*)$', '_proj_\1')
            | map('extract', hostvars[inventory_hostname])
            | list
          }}
      tags: always

  roles:
    - role: caddy_proxy
DEPLOYPROXY_EOF

echo ""
echo "==> 8/9 — roles/caddy_proxy/templates/Caddyfile.j2"
cat > roles/caddy_proxy/templates/Caddyfile.j2 << 'CADDYFILE_EOF'
# ─────────────────────────────────────────────────────────────────────────────
# Caddyfile — Généré par Ansible
# Environnement : {{ environment_name }}
# Ne pas éditer manuellement.
# ─────────────────────────────────────────────────────────────────────────────

{
{% if caddy_tls_mode == "acme" %}
    email {{ caddy_email }}
{% endif %}
}

# ─────────────────────────────────────────────────────────────────────────────
# Projets applicatifs (générés depuis vars/projects/)
# ─────────────────────────────────────────────────────────────────────────────

{% set ns = namespace(domains_seen=[]) %}
{% for project in projects %}
{#  Regroupe par domaine : on n'ouvre un bloc de domaine qu'une seule fois  #}
{% if project.domain not in ns.domains_seen %}
{% set _ = ns.domains_seen.append(project.domain) %}

{{ project.domain }} {
{% if caddy_tls_mode == "internal" %}
    tls internal
{% endif %}

{% for p in projects if p.domain == project.domain %}
{% if p.route_path is defined and p.route_path != "/" %}
    # Route : {{ p.route_path }} → {{ p.project_name }}
    handle {{ p.route_path }} {
{% if p.strip_prefix is defined and p.strip_prefix %}
        uri strip_prefix {{ p.route_path | regex_replace('/\*$', '') }}
{% endif %}
        reverse_proxy {{ p.backend_host | default(backend_host) }}:{{ p.host_port }}
    }
{% for route in p.extra_routes | default([]) %}
    # Route : {{ route.route_path }} → {{ p.project_name }}
    handle {{ route.route_path }} {
{% if route.strip_prefix is defined and route.strip_prefix %}
        uri strip_prefix {{ route.route_path | regex_replace('/\*$', '') }}
{% endif %}
        reverse_proxy {{ p.backend_host | default(backend_host) }}:{{ p.host_port }}
    }
{% endfor %}
{% else %}
    # Route : / → {{ p.project_name }}
    handle /* {
        reverse_proxy {{ p.backend_host | default(backend_host) }}:{{ p.host_port }}
    }
{% endif %}
{% endfor %}
}
{% endif %}
{% endfor %}
CADDYFILE_EOF

echo ""
echo "==> 9/9 — README.md"
cat > README.md << 'README_EOF'
# devops_staging_prod_infra

Infrastructure Ansible pour le déploiement des applications web en staging et production sur VMs Proxmox Debian 12.

## Prérequis

- Ansible ≥ 2.14
- Accès SSH à toutes les VMs avec l'utilisateur de déploiement (`devops` en staging, `deploy` en production)
- Python 3 sur les VMs cibles

```bash
pip install ansible
ansible-galaxy install -r requirements.yml
```

## Structure

```
devops_staging_prod_infra/
├── ansible.cfg
├── requirements.yml
├── inventories/
│   ├── staging/
│   │   ├── hosts.yml                   # IPs des VMs staging
│   │   └── group_vars/
│   │       └── all/
│   │           ├── main.yml            # Variables staging (dont active_projects)
│   │           └── vault.yml           # Secrets chiffrés (Vault)
│   └── production/
│       ├── hosts.yml                   # IPs des VMs production
│       └── group_vars/
│           └── all/
│               ├── main.yml
│               └── vault.yml
├── playbooks/
│   ├── site.yml                        # Point d'entrée : déploiement complet
│   ├── deploy-docker-host.yml          # Docker Engine + Compose v2
│   ├── deploy-apps.yml                 # Applications (charge le registre projets)
│   └── deploy-proxy.yml                # Caddy (charge le registre projets)
├── roles/
│   ├── docker_host/                    # Installe Docker
│   ├── docker_app/                     # Déploie une app Docker générique
│   ├── caddy_proxy/                    # Reverse proxy Caddy
│   └── grav_stack/                     # Grav CMS avec volume persistant
└── vars/
    └── projects/                       # ← Registre de projets
        ├── lavallee-website.yml
        ├── facturier-landing.yml
        ├── facturier-app.yml
        ├── grav-docs.yml
        └── nextcloud.yml               # Service externe — voir section dédiée
```

## Vault et group_vars

Chaque environnement a un répertoire `group_vars/all/` contenant deux fichiers : `main.yml` (variables en clair) et `vault.yml` (secrets chiffrés).

**Cette structure en répertoire est obligatoire, pas une préférence de style.** Ansible n'associe un fichier de `group_vars/` à un groupe que si le **nom du fichier** correspond exactement au nom du groupe (`all.yml` → groupe `all`). Un fichier nommé `vault.yml` à plat dans `group_vars/` ne correspond à aucun groupe et est silencieusement ignoré. La solution consiste à utiliser un répertoire portant le nom du groupe (`group_vars/all/`), dans lequel tous les fichiers YAML qu'il contient sont chargés et fusionnés, quel que soit leur nom.

```bash
# Éditer un vault chiffré
ansible-vault edit inventories/staging/group_vars/all/vault.yml
ansible-vault edit inventories/production/group_vars/all/vault.yml
```

Les secrets ne sont jamais en clair dans le dépôt.

## Registre de projets

Chaque application est déclarée dans `vars/projects/<nom>.yml`.

**Pour ajouter une nouvelle application :**

1. Créer `vars/projects/mon-app.yml` :

```yaml
project_name: mon-app
project_type: docker_app
image: ghcr.io/sepp67/mon-app:latest
container_port: 8080
host_port: 18090
domain: mon-app.lavallee.tech
route_path: /
healthcheck_url: "http://{{ backend_host }}:18090/"
environment:
  APP_ENV: "{{ environment_name }}"
volumes: []
```

2. Ajouter `mon-app` à `active_projects` dans `inventories/<env>/group_vars/all/main.yml` :

```yaml
active_projects:
  - lavallee-website
  - facturier-landing
  - facturier-app
  - grav-docs
  - nextcloud
  - mon-app       # ← ajout
```

**Aucun rôle à modifier**, sauf si l'application nécessite un cycle de vie spécifique (voir `grav_stack` comme exemple) ou n'est pas déployée par ce dépôt du tout (voir section suivante).

## Services externes

Certains services routés par Caddy ne sont pas déployés par ce dépôt. C'est le cas de **Nextcloud**.

### Pourquoi Nextcloud est traité différemment

Nextcloud est un service fortement stateful (PostgreSQL + Redis + données utilisateur), avec un cycle de mise à jour applicative qui nécessite des étapes manuelles (`occ upgrade`, vérification de compatibilité de version, sauvegarde préalable de la base). Automatiser ce cycle de vie avec Ansible introduirait un risque de perte de données disproportionné par rapport au bénéfice, pour une infrastructure de cette taille.

**Décision** : Nextcloud est installé et administré manuellement sur sa VM dédiée (`vm-nextcloud-staging` / `vm-nextcloud-prod`), via un `docker-compose.yml` qui vit uniquement sur cette VM — jamais dans ce dépôt. Ce dépôt se limite à :

- déclarer la VM dans l'inventaire (documentation, supervision future) ;
- router vers elle via Caddy (`vars/projects/nextcloud.yml`, `project_type: external_service`).

Toute mise à jour, migration ou restauration de Nextcloud se fait directement sur la VM, hors de ce dépôt :

```bash
cd /opt/nextcloud
docker compose pull
docker compose up -d
docker exec -u www-data nextcloud php occ upgrade
```

Les secrets Nextcloud (admin, base de données) ne sont **pas** dans le Vault Ansible — ils vivent uniquement dans le `docker-compose.yml` manuel de la VM, pour éviter une double source de vérité.

### Pourquoi pas un pattern dédié aux services stateful ?

Une architecture plus poussée a été envisagée pour les services stateful en général (Nextcloud, Keycloak, OpenLDAP, Gitea, Wiki.js, GitLab) : Ansible générerait leur `docker-compose.yml` et `.env`, et exécuterait un `docker compose up -d` une seule fois au premier déploiement, tout en laissant les mises à jour et migrations strictement manuelles.

Cette approche a été écartée pour l'instant, non pas pour des raisons techniques, mais parce qu'introduire une nouvelle catégorie de déploiement pour un seul service (Nextcloud) ne se justifie pas. Si plusieurs services stateful réels rejoignent l'infrastructure, ce pattern (nommé `stateful_service` / rôle `stateful_bootstrap` dans les discussions de conception) devra être reconsidéré.

### Convention `project_type: external_service`

Ce type marque un projet qui n'est **jamais** déployé par `deploy-apps.yml` — il n'apparaît dans aucune boucle de déploiement de ce playbook, uniquement dans la génération du Caddyfile (`deploy-proxy.yml`), au même titre que tout autre projet.

Champs attendus dans `vars/projects/<nom>.yml` pour ce type :

```yaml
project_name: nextcloud
project_type: external_service
domain: "{{ nextcloud_domain }}"
route_path: /
host_port: "{{ nextcloud_host_port }}"
backend_host: "{{ nextcloud_backend_host }}"
```

`backend_host` est spécifique à ce type : les projets `docker_app`/`grav_stack` tournent tous sur la même VM (`backend_host` global), alors qu'un `external_service` peut vivre sur n'importe quelle VM. Le template Caddyfile lit `project.backend_host` avec un repli sur la variable globale `backend_host` si absente.

Si vous ajoutez un nouveau service externe à l'avenir, suivez ce même pattern plutôt que de forcer son intégration dans `docker_app`.

## Déploiement

### Déploiement complet

```bash
# Staging
ansible-playbook -i inventories/staging/hosts.yml playbooks/site.yml --ask-vault-pass

# Production
ansible-playbook -i inventories/production/hosts.yml playbooks/site.yml --ask-vault-pass
```

### Déploiements ciblés

```bash
# Docker uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-docker-host.yml --ask-vault-pass

# Applications uniquement (n'inclut jamais les services externes comme nextcloud)
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml --ask-vault-pass

# Proxy uniquement (inclut le routage vers tous les projets, y compris nextcloud)
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-proxy.yml --ask-vault-pass
```

### Vérification (dry-run)

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/site.yml --ask-vault-pass --check --diff
```

## Architecture réseau

```
Internet
    │
    ▼
[vm-proxy] ─── Caddy (80/443)
    │
    ├── lavallee.tech                  → backend_host:18082
    ├── facturier.lavallee.tech        → backend_host:18080  (landing, route /)
    ├── facturier.lavallee.tech/app/*  → backend_host:18081  (app, strip_prefix)
    ├── docs.lavallee.tech             → backend_host:18084
    └── nextcloud.lavallee.tech        → nextcloud_backend_host:8080  (service externe)
         │                                   │
         ▼                                   ▼
    [vm-apps]                          [vm-nextcloud]
    docker_app / grav_stack            Appliance autonome, administrée
    (déployés par ce dépôt)            manuellement, hors de ce dépôt
```

## Variables backend

Les backends Caddy utilisent des variables, jamais `localhost` :

| Variable | Description |
|---|---|
| `backend_host` | IP/hostname VM apps (défini dans `group_vars/all/main.yml`) |
| `nextcloud_backend_host` | IP/hostname VM Nextcloud (service externe) |

## TLS

| Environnement | Mode | Configuration |
|---|---|---|
| Staging | `internal` | Certificats auto-signés Caddy (`tls internal`) |
| Production | `acme` | Let's Encrypt automatique |
README_EOF

echo ""
echo "==> Suppression de playbooks/deploy-nextcloud.yml et roles/nextcloud_stack/"
git rm -f playbooks/deploy-nextcloud.yml
git rm -rf roles/nextcloud_stack

echo ""
echo "==> Ajout des fichiers modifiés/créés au staging git..."
git add \
  inventories/staging/group_vars/all/main.yml \
  inventories/production/group_vars/all/main.yml \
  inventories/production/group_vars/all/vault.yml \
  vars/projects/nextcloud.yml \
  playbooks/site.yml \
  playbooks/deploy-apps.yml \
  playbooks/deploy-proxy.yml \
  roles/caddy_proxy/templates/Caddyfile.j2 \
  README.md

git diff --cached --name-status | sed 's/^/      /'

UNSTAGED=$(git diff --name-only)
if [ -n "$UNSTAGED" ]; then
  echo ""
  echo "ATTENTION : des modifications non stagées existent ailleurs dans le dépôt :"
  echo "$UNSTAGED" | sed 's/^/      /'
  echo "Elles ne seront PAS incluses dans ce commit (comportement voulu)."
fi

echo ""
echo "==> Commit..."
git commit -m "refactor: Nextcloud devient un service externe pur (external_service)

Décision finale après analyse de plusieurs approches (déploiement complet
via nextcloud_stack, pattern stateful_bootstrap générique) : Nextcloud
reste une VM autonome administrée manuellement. Ansible ne génère ni
docker-compose.yml, ni .env, ne stocke aucun secret Nextcloud, et ne
pilote aucunement son cycle de vie.

1. Suppression du mensonge architectural actif :
   - playbooks/deploy-nextcloud.yml supprimé (importait un rôle stub)
   - roles/nextcloud_stack/ supprimé (jamais implémenté, jamais prévu de l'être)
   - playbooks/site.yml : retrait de l'import deploy-nextcloud.yml

2. vars/projects/nextcloud.yml (nouveau) :
   - project_type: external_service
   - Documente explicitement pourquoi ce n'est pas un stateful_service dédié

3. group_vars/all/main.yml (staging + production) :
   - nextcloud ajouté à active_projects (routage Caddy uniquement)
   - host_port corrigé : 18085 -> 8080 (valeur réelle du docker-compose.yml
     de la VM, jamais corrigée jusqu'ici)
   - 6 variables de secrets/config retirées (admin_user, admin_password,
     db_user, db_password, db_name, overwriteprotocol, trusted_proxies) :
     aucun consommateur Ansible, double source de vérité avec le
     docker-compose.yml manuel de la VM

4. group_vars/all/vault.yml :
   - production : 4 clés vault_nextcloud_* retirées directement (non chiffré)
   - staging : ACTION MANUELLE REQUISE — voir le rappel affiché par ce script

5. roles/caddy_proxy/templates/Caddyfile.j2 :
   - Bloc Nextcloud codé en dur supprimé (domaine, headers de sécurité)
   - reverse_proxy généralisé : {{ p.backend_host | default(backend_host) }}
     au lieu de {{ backend_host }}, pour que tout project_type (y compris
     external_service) soit routé par la même boucle générique

6. README.md :
   - Section 'Services externes' : justification complète de la décision,
     y compris pourquoi le pattern stateful_service/stateful_bootstrap
     envisagé a été écarté
   - Structure group_vars/all/ documentée
   - Architecture réseau et tableau de variables mis à jour"

echo "    OK"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " COMMIT CRÉÉ SUR LA BRANCHE : $CURRENT_BRANCH"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo " ACTION MANUELLE REQUISE — vault staging (chiffré, non modifié par ce script) :"
echo ""
echo "   ansible-vault edit inventories/staging/group_vars/all/vault.yml"
echo ""
echo " Retirer ces 4 lignes devenues orphelines :"
echo "   vault_nextcloud_admin_user"
echo "   vault_nextcloud_admin_password"
echo "   vault_nextcloud_db_user"
echo "   vault_nextcloud_db_password"
echo ""
echo " Prochaines étapes :"
echo "   1. git push (si tu veux pousser maintenant)"
echo "   2. Régénérer le Caddyfile en staging :"
echo "      ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-proxy.yml --ask-vault-pass"
echo "   3. Vérifier le routage : curl -k https://cloud.lavallee.local (ou via /etc/hosts)"
echo ""
echo "   4. Reconfigurer Nextcloud lui-même sur la VM (sinon il continuera de"
echo "      rediriger vers http://192.168.1.59:8080/) :"
echo "      docker exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value=\"cloud.lavallee.local\""
echo "      docker exec -u www-data nextcloud php occ config:system:set overwritehost --value=\"cloud.lavallee.local\""
echo ""
