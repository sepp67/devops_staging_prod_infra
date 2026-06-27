# ansible-role-matrix-stack

Ansible role that deploys a **dual-homeserver Matrix Synapse infrastructure** on Debian 12, using Docker Compose.

Designed for environments where user accounts and bridge bots live on separate homeservers, with a shared PostgreSQL backend and a reverse proxy (Caddy, nginx, …) in front.

---

## Architecture

```
Internet
    │
    ▼
Reverse Proxy (Caddy / nginx)
    │
    ├── matrix-users.example.com  ──►  Synapse Users  (port 8008)
    │                                       │
    └── matrix-bridges.example.com ──►  Synapse Bridges (port 8009)
                                             │
                              ┌──────────────┘
                              ▼
                         PostgreSQL 16
                    ┌────────────────────┐
                    │  synapse_users DB  │
                    │  synapse_bridges DB│
                    └────────────────────┘

VM layout (3 dedicated VMs):
  vm-matrix-db       →  PostgreSQL
  vm-matrix-users    →  Synapse Users
  vm-matrix-bridges  →  Synapse Bridges
```

---

## Requirements

| Requirement | Version |
|---|---|
| Ansible | ≥ 2.14 |
| Target OS | Debian 12 (Bookworm) |
| Python (control node) | ≥ 3.10 |
| community.docker collection | ≥ 3.0.0 |

Docker Engine and Docker Compose v2 are **installed automatically** by the role on each target VM. Set `matrix_install_docker: false` to skip this step if Docker is already managed separately.

---

## Installation

```bash
# Clone the role into your roles directory
git clone https://github.com/sepp67/ansible-role-matrix-stack.git roles/matrix_stack

# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml
```

---

## Quick start

### 1. Create your inventory

Copy and adapt the examples:
```bash
cp -r examples/inventories/staging inventories/staging
# Edit inventories/staging/hosts.yml with your VM IPs
```

### 2. Configure secrets

```bash
# Copy the vault template and fill in real values
cp examples/inventories/staging/group_vars/all/vault.yml.example \
   inventories/staging/group_vars/all/vault.yml

# Edit with real secrets, then encrypt
ansible-vault encrypt inventories/staging/group_vars/all/vault.yml
```

Generate strong secrets:
```bash
openssl rand -hex 32   # PostgreSQL passwords
openssl rand -hex 64   # Synapse keys (registration_shared_secret, etc.)
```

### 3. Run the playbook

```bash
ansible-playbook -i inventories/staging examples/deploy-matrix-stack.yml --ask-vault-pass
```

---

## Role variables

### Docker

| Variable | Default | Description |
|---|---|---|
| `matrix_install_docker` | `true` | Install Docker Engine + Compose v2 automatically |
| `docker_bind_address` | `0.0.0.0` | Docker port binding address |
| `deploy_user` | `devops` | OS user for Docker Compose operations (must be in `docker` group) |

### Images

| Variable | Default | Description |
|---|---|---|
| `matrix_synapse_image` | `matrixdotorg/synapse` | Synapse Docker image |
| `matrix_synapse_version` | `latest` | Synapse image tag |
| `matrix_postgres_version` | `16` | PostgreSQL image tag |

### Directories

| Variable | Default | Description |
|---|---|---|
| `matrix_base_dir` | `/opt/matrix` | Root data directory on target VMs |

### PostgreSQL

| Variable | Default | Description |
|---|---|---|
| `matrix_postgres_host` | `127.0.0.1` | PostgreSQL host (reachable from Synapse VMs) |
| `matrix_postgres_port` | `5432` | PostgreSQL port |
| `matrix_postgres_cp_min` | `5` | psycopg2 connection pool minimum |
| `matrix_postgres_cp_max` | `10` | psycopg2 connection pool maximum |

### Synapse Users

| Variable | Default | Description |
|---|---|---|
| `matrix_users_server_name` | `matrix-users.example.com` | Matrix server_name (federation identity) |
| `matrix_users_public_baseurl` | `https://matrix-users.example.com/` | Public HTTPS URL |
| `matrix_users_container_name` | `synapse-users` | Docker container name |
| `matrix_users_http_port` | `8008` | Host port exposed by Docker |

### Synapse Bridges

| Variable | Default | Description |
|---|---|---|
| `matrix_bridges_server_name` | `matrix-bridges.example.com` | Matrix server_name |
| `matrix_bridges_public_baseurl` | `https://matrix-bridges.example.com/` | Public HTTPS URL |
| `matrix_bridges_container_name` | `synapse-bridges` | Docker container name |
| `matrix_bridges_http_port` | `8009` | Host port exposed by Docker |

### Federation & OIDC

| Variable | Default | Description |
|---|---|---|
| `matrix_federation_enabled` | `true` | Enable Matrix federation |
| `matrix_oidc_enabled` | `false` | Enable OIDC / Keycloak integration |
| `matrix_oidc_issuer` | `""` | OIDC issuer URL (e.g. Keycloak realm) |
| `matrix_oidc_client_id` | `""` | OIDC client ID |
| `matrix_oidc_client_secret` | `""` | OIDC client secret (set via vault) |

### Secrets (via Ansible Vault — never set in clear text)

| Vault variable | Description |
|---|---|
| `vault_matrix_postgres_superuser_password` | PostgreSQL superuser password |
| `vault_matrix_postgres_password_users` | Password for `synapse_users` DB user |
| `vault_matrix_postgres_password_bridges` | Password for `synapse_bridges` DB user |
| `vault_matrix_users_registration_shared_secret` | Synapse Users registration secret |
| `vault_matrix_users_macaroon_secret_key` | Synapse Users macaroon key |
| `vault_matrix_users_form_secret` | Synapse Users form secret |
| `vault_matrix_bridges_registration_shared_secret` | Synapse Bridges registration secret |
| `vault_matrix_bridges_macaroon_secret_key` | Synapse Bridges macaroon key |
| `vault_matrix_bridges_form_secret` | Synapse Bridges form secret |

---

## Deployment

The role uses a single `matrix_component` variable to select what to deploy on each host:

| Value | Deploys |
|---|---|
| `postgres` | PostgreSQL 16 with two databases and two users |
| `synapse_users` | Synapse homeserver for user accounts |
| `synapse_bridges` | Synapse homeserver for Mautrix bridges |

### Full stack

```bash
ansible-playbook -i inventories/staging examples/deploy-matrix-stack.yml --ask-vault-pass
```

### Single component

```bash
# PostgreSQL only
ansible-playbook -i inventories/staging examples/deploy-matrix-stack.yml \
  --ask-vault-pass --limit matrix_db

# Synapse Users only
ansible-playbook -i inventories/staging examples/deploy-matrix-stack.yml \
  --ask-vault-pass --limit matrix_users
```

---

## Data layout on each VM

```
/opt/matrix/
  postgres/
    docker-compose.yml
    data/              ← PostgreSQL data (persistent)
    init/
      01-init-matrix.sql  ← creates users + databases (run once)

  users/
    docker-compose.yml
    data/              ← Synapse data dir (mounted as /data in container)
      homeserver.yaml  ← generated by Ansible
      log.config       ← generated by Ansible
      <server_name>.signing.key  ← auto-generated by Synapse (persistent)
      media_store/     ← media files (persistent)
      homeserver.log   ← rotated daily, kept 7 days

  bridges/             ← same structure as users/
```

---

## Validation

### Container status

```bash
ssh devops@<matrix_db_ip>      "docker compose -f /opt/matrix/postgres/docker-compose.yml ps"
ssh devops@<matrix_users_ip>   "docker compose -f /opt/matrix/users/docker-compose.yml ps"
ssh devops@<matrix_bridges_ip> "docker compose -f /opt/matrix/bridges/docker-compose.yml ps"
```

### Matrix Client API

```bash
curl -k https://matrix-users.staging.local/_matrix/client/versions
# Expected: {"versions":["r0.0.1","r0.1.0",...],"unstable_features":{...}}

curl -k https://matrix-bridges.staging.local/_matrix/client/versions
```

### Well-known endpoints

```bash
curl -k https://matrix-users.staging.local/.well-known/matrix/server
# Expected: {"m.server":"matrix-users.staging.local:443"}

curl -k https://matrix-users.staging.local/.well-known/matrix/client
# Expected: {"m.homeserver":{"base_url":"https://matrix-users.staging.local/"},...}
```

### Create an admin user

```bash
# On vm-matrix-users
ssh devops@<matrix_users_ip> \
  "docker exec -it synapse-users register_new_matrix_user \
    -u admin -p '<strong_password>' -a \
    -c /data/homeserver.yaml http://localhost:8008"

# On vm-matrix-bridges
ssh devops@<matrix_bridges_ip> \
  "docker exec -it synapse-bridges register_new_matrix_user \
    -u admin -p '<strong_password>' -a \
    -c /data/homeserver.yaml http://localhost:8008"
```

### Federation test between the two homeservers

```bash
# From Synapse Users, reach Synapse Bridges federation endpoint
curl -k "https://matrix-bridges.staging.local/_matrix/federation/v1/version"
# Expected: {"server":{"name":"Synapse","version":"..."}}
```

---

## Reverse proxy integration (Caddy example)

Add to your Caddyfile:

```caddy
matrix-users.example.com {
    reverse_proxy 192.168.1.78:8008
}

matrix-bridges.example.com {
    reverse_proxy 192.168.1.77:8009
}
```

If your infra repo uses a project registry pattern (like `devops_staging_prod_infra`), declare Matrix as `external_service` entries — no changes to the proxy role needed.

---

## Idempotence

- **PostgreSQL init SQL** runs only on first container start (Docker `initdb` mechanism) — safe to re-run.
- **Synapse signing key** is auto-generated on first start and persists in the data volume — never regenerated.
- **homeserver.yaml** is re-templated on every run; a change triggers a container restart via the `Restart synapse` handler.
- All tasks are idempotent — re-running the playbook on an already-deployed stack is safe and has no side effects.

---

## Roadmap

### OIDC / Keycloak integration

1. Deploy Keycloak behind your reverse proxy
2. Create an OIDC client in Keycloak for each Synapse
3. Set in `group_vars`:
   ```yaml
   matrix_oidc_enabled: true
   matrix_oidc_issuer: "https://keycloak.example.com/realms/master"
   matrix_oidc_client_id: "synapse-users"
   ```
4. Add `vault_matrix_oidc_client_secret` to vault
5. Re-run the playbook — the OIDC section in `homeserver.yaml.j2` activates automatically

### Mautrix bridges

For each bridge (WhatsApp, Signal, Telegram, …):
1. Add the bridge container to the Synapse Bridges VM
2. Generate a `registration.yaml` from the bridge and mount it in Synapse's data dir
3. Reference it in `homeserver.yaml` via `app_service_config_files`

---

## License

MIT — see [LICENSE](LICENSE).

## Author

[sepp67](https://github.com/sepp67)
