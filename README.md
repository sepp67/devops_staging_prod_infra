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
