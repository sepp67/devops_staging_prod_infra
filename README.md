# devops_staging_prod_infra

Infrastructure Ansible pour le déploiement des applications web en staging et production sur VMs Proxmox Debian 12.

## Prérequis

- Ansible ≥ 2.14
- Accès SSH à toutes les VMs avec l'utilisateur `deploy`
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
│   │       ├── all.yml                 # Variables staging (dont active_projects)
│   │       └── vault.yml               # Secrets chiffrés (Vault)
│   └── production/
│       ├── hosts.yml                   # IPs des VMs production
│       └── group_vars/
│           ├── all.yml
│           └── vault.yml
├── playbooks/
│   ├── site.yml                        # Point d'entrée : déploiement complet
│   ├── deploy-docker-host.yml          # Docker Engine + Compose v2
│   ├── deploy-apps.yml                 # Applications (charge le registre projets)
│   ├── deploy-nextcloud.yml            # Stack Nextcloud dédiée
│   └── deploy-proxy.yml                # Caddy (charge le registre projets)
├── roles/
│   ├── docker_host/                    # Installe Docker
│   ├── docker_app/                     # Déploie une app Docker générique
│   ├── caddy_proxy/                    # Reverse proxy Caddy
│   ├── nextcloud_stack/                # Nextcloud + PostgreSQL + Redis (à venir)
│   └── grav_stack/                     # Grav CMS avec volume persistant (à venir)
└── vars/
    ├── projects/                       # ← Registre de projets
    │   ├── lavallee-website.yml
    │   ├── facturier-landing.yml
    │   ├── facturier-app.yml
    │   └── grav-docs.yml
    └── environments/
        ├── staging.yml
        └── production.yml
```

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

2. Ajouter `mon-app` à `active_projects` dans `inventories/<env>/group_vars/all.yml` :

```yaml
active_projects:
  - lavallee-website
  - facturier-landing
  - facturier-app
  - grav-docs
  - mon-app       # ← ajout
```

**Aucun rôle à modifier.**

## Secrets (Ansible Vault)

Les secrets ne sont jamais en clair dans le dépôt.

```bash
# Chiffrer le vault
ansible-vault encrypt inventories/staging/group_vars/vault.yml
ansible-vault encrypt inventories/production/group_vars/vault.yml

# Éditer un vault chiffré
ansible-vault edit inventories/staging/group_vars/vault.yml
```

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

# Applications uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml --ask-vault-pass

# Proxy uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-proxy.yml --ask-vault-pass

# Nextcloud uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-nextcloud.yml --ask-vault-pass
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
    ├── lavallee.tech           → backend_host:18082
    ├── facturier.lavallee.tech → backend_host:18080  (landing, route /)
    ├── facturier.lavallee.tech/app/* → backend_host:18081  (app, strip_prefix)
    ├── docs.lavallee.tech      → backend_host:18084
    └── nextcloud.lavallee.tech → nextcloud_backend_host:18085
         │
         ▼
    [vm-apps]                   [vm-nextcloud]
    docker_app containers       Nextcloud + PostgreSQL + Redis
```

## Variables backend

Les backends Caddy utilisent des variables, jamais `localhost` :

| Variable | Description |
|---|---|
| `backend_host` | IP/hostname VM apps (défini dans `group_vars/all.yml`) |
| `nextcloud_backend_host` | IP/hostname VM Nextcloud |

## TLS

| Environnement | Mode | Configuration |
|---|---|---|
| Staging | `internal` | Certificats auto-signés Caddy (`tls internal`) |
| Production | `acme` | Let's Encrypt automatique |

