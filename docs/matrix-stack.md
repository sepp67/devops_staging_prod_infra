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

Le déploiement Matrix passe par le playbook d'orchestration unique `deploy-apps.yml`.

> Les playbooks d'exemple propres aux rôles existent uniquement dans les dépôts des rôles
> pour les tests locaux. Dans `devops_staging_prod_infra`, le déploiement passe par
> `deploy-apps.yml`.

### Staging

```bash
ansible-galaxy install -r requirements.yml

ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml \
  --ask-vault-pass
```

### Production

```bash
ansible-galaxy install -r requirements.yml

ansible-playbook -i inventories/production/hosts.yml playbooks/deploy-apps.yml \
  --ask-vault-pass
```

### Composant ciblé uniquement

```bash
# PostgreSQL uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml \
  --ask-vault-pass --limit matrix_db

# Synapse utilisateurs uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml \
  --ask-vault-pass --limit matrix_users

# Synapse bridges uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml \
  --ask-vault-pass --limit matrix_bridges
```

## Routage Caddy

Le routage proxy est déclaré dans :

| Fichier | Port | Cible |
|---|---|---|
| [`vars/projects/matrix-users.yml`](../vars/projects/matrix-users.yml) | 443 | `192.168.1.78:8008` |
| [`vars/projects/matrix-bridges.yml`](../vars/projects/matrix-bridges.yml) | 443 | `192.168.1.77:8009` |
| [`vars/projects/matrix-users-federation.yml`](../vars/projects/matrix-users-federation.yml) | 8448 | `192.168.1.78:8008` |
| [`vars/projects/matrix-bridges-federation.yml`](../vars/projects/matrix-bridges-federation.yml) | 8448 | `192.168.1.77:8009` |

Tous ces fichiers sont de type `external_service` : ils déclarent uniquement du routage Caddy, sans aucun déploiement applicatif.

```bash
# Mettre à jour le Caddyfile uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-proxy.yml --ask-vault-pass
```

## Fédération Matrix — explication et correctifs

La fédération Matrix permet à des homeservers distincts d'échanger des messages. En staging, quatre contraintes doivent être levées simultanément :

### 1. DNS dans les conteneurs Synapse

Quand `synapse-users` contacte `matrix-bridges.local` en fédération, il résout ce nom. Sans correctif, la résolution pointe vers la VM Synapse elle-même (qui ne sait pas répondre à ce domaine). Il faut que ce nom resolve vers le **proxy Caddy** (192.168.1.56), seul autorisé à répondre avec le bon certificat TLS.

Solution : `extra_hosts` dans le `docker-compose.yml` Synapse, fourni par `matrix_extra_hosts` dans `inventories/staging/group_vars/all/main.yml`.

### 2. Port fédération 8448

Le protocole Matrix Server-Server utilise le port 8448 par défaut. Caddy doit exposer :

- `matrix-users.local:8448` → `192.168.1.78:8008`
- `matrix-bridges.local:8448` → `192.168.1.77:8009`

Solution : deux fichiers `vars/projects/*-federation.yml` avec `listen_port: 8448`. Le `Caddyfile.j2` génère un bloc distinct pour chaque `(domain, listen_port)`.

### 3. CA Caddy en staging

Caddy utilise `tls internal` en staging : il signe les certificats avec sa propre CA locale (non reconnue par défaut). Les conteneurs Synapse refusent donc les connexions TLS vers Caddy avec :

```
SSL certificate problem: unable to get local issuer certificate
```

Solution : le play 2 de `deploy-apps.yml` lit le certificat CA Caddy depuis `vm-proxy-staging` (`/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`) et le passe aux plays Synapse via `matrix_custom_ca_cert_content`. Le rôle écrit le certificat sur l'hôte puis le monte dans le conteneur. L'entrypoint wrapper exécute `update-ca-certificates` avant de lancer Synapse.

### 4. `ip_range_whitelist`

Synapse refuse de contacter des IPs privées RFC1918 en fédération. En staging, tout le trafic fédération passe par `192.168.1.56`. Il faut débloquer ce sous-réseau.

Solution : `matrix_synapse_ip_range_whitelist: ["192.168.1.0/24"]` dans les group_vars staging. En production (ACME, fédération publique), cette variable reste à `[]`.

## Commandes de validation

### Vérifier le DNS interne dans les conteneurs

```bash
# Sur vm-matrix-users-staging
docker exec synapse-users getent hosts matrix-bridges.local
# Doit retourner 192.168.1.56

# Sur vm-matrix-bridges-staging
docker exec synapse-bridges getent hosts matrix-users.local
# Doit retourner 192.168.1.56
```

### Vérifier la fédération TLS

```bash
# Sur vm-matrix-users-staging
docker exec synapse-users curl -s https://matrix-bridges.local:8448/_matrix/federation/v1/version
# Doit retourner {"server": {"name": "Synapse", ...}}

# Sur vm-matrix-bridges-staging
docker exec synapse-bridges curl -s https://matrix-users.local:8448/_matrix/federation/v1/version
# Doit retourner {"server": {"name": "Synapse", ...}}
```

### Vérifier le CA cert dans les conteneurs

```bash
docker exec synapse-users openssl s_client \
  -connect matrix-bridges.local:8448 \
  -showcerts 2>/dev/null | openssl x509 -noout -issuer
# Doit afficher : issuer=CN=Caddy Local Authority
```

### Test fédération Element

1. Se connecter sur `https://element.lavallee.local`
2. Compte A sur `matrix-users.local` envoie une invitation à `@utilisateur:matrix-bridges.local`
3. Se connecter sur un client différent avec le compte B sur `matrix-bridges.local`
4. L'invitation doit être reçue et les messages échangés dans les deux sens.

## Mise à jour du rôle

```bash
ansible-galaxy install -r requirements.yml --force
```
