# Stack Matrix

Ce document décrit comment déployer la stack Matrix (PostgreSQL + Synapse) en staging et production.

La logique applicative (installation Synapse, configuration PostgreSQL, gestion des services systemd/Docker) est entièrement contenue dans le rôle externe **[ansible-role-matrix-stack](https://github.com/sepp67/ansible-role-matrix-stack)**. Ce dépôt d'infrastructure fournit uniquement :

- les groupes d'inventaire (`matrix_db`, `matrix_users`, `matrix_bridges`) ;
- les variables d'environnement non-secrètes (`matrix_users_domain`, `matrix_bridges_domain`, etc.) ;
- les secrets dans Vault (`vault_matrix_*`) ;
- le routage Caddy (`vars/projects/matrix-users.yml`, `vars/projects/matrix-bridges.yml`).

## Architecture

```
[vm-matrix-db-staging]       192.168.1.79   → matrix_db      PostgreSQL partagé
[vm-matrix-users-staging]    192.168.1.78   → matrix_users   Synapse (utilisateurs)
[vm-matrix-bridges-staging]  192.168.1.77   → matrix_bridges Synapse (bridges Mautrix)

[vm-proxy-staging]           192.168.1.56   → Caddy
  ├── matrix-users.staging.local   → 192.168.1.78:8008
  └── matrix-bridges.staging.local → 192.168.1.77:8009
```

## Prérequis

Installer le rôle externe avant le premier déploiement :

```bash
ansible-galaxy install -r requirements.yml
```

## Secrets Vault

Les secrets suivants doivent être définis dans `inventories/<env>/group_vars/all/vault.yml`.

```bash
ansible-vault edit inventories/staging/group_vars/all/vault.yml
```

Variables attendues :

```yaml
# PostgreSQL
vault_matrix_postgres_superuser_password: "..."
vault_matrix_postgres_password_users:     "..."
vault_matrix_postgres_password_bridges:   "..."

# Synapse – homeserver utilisateurs
vault_matrix_users_registration_shared_secret: "..."
vault_matrix_users_macaroon_secret_key:         "..."
vault_matrix_users_form_secret:                 "..."

# Synapse – homeserver bridges
vault_matrix_bridges_registration_shared_secret: "..."
vault_matrix_bridges_macaroon_secret_key:         "..."
vault_matrix_bridges_form_secret:                 "..."
```

Générer des valeurs aléatoires sécurisées pour chaque secret :

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

## Déploiement

### Staging

```bash
ansible-playbook -i inventories/staging playbooks/deploy-matrix-stack.yml --ask-vault-pass
```

### Production

```bash
ansible-playbook -i inventories/production playbooks/deploy-matrix-stack.yml --ask-vault-pass
```

### Composant ciblé uniquement

```bash
# PostgreSQL uniquement
ansible-playbook -i inventories/staging playbooks/deploy-matrix-stack.yml \
  --ask-vault-pass --limit matrix_db

# Synapse utilisateurs uniquement
ansible-playbook -i inventories/staging playbooks/deploy-matrix-stack.yml \
  --ask-vault-pass --limit matrix_users

# Synapse bridges uniquement
ansible-playbook -i inventories/staging playbooks/deploy-matrix-stack.yml \
  --ask-vault-pass --limit matrix_bridges
```

## Routage Caddy

Le routage proxy est déclaré dans :

- [`vars/projects/matrix-users.yml`](../vars/projects/matrix-users.yml) — `project_type: external_service`
- [`vars/projects/matrix-bridges.yml`](../vars/projects/matrix-bridges.yml) — `project_type: external_service`

Ces fichiers sont chargés automatiquement par `playbooks/deploy-proxy.yml` via le registre `active_projects`. Le routage est appliqué indépendamment du déploiement Synapse.

```bash
# Mettre à jour le Caddyfile uniquement
ansible-playbook -i inventories/staging playbooks/deploy-proxy.yml --ask-vault-pass
```

## Mise à jour du rôle

```bash
ansible-galaxy install -r requirements.yml --force
```
