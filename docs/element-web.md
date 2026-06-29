# Element Web

Ce document décrit comment déployer le client web Matrix Element en staging.

La logique applicative (installation, génération du `config.json`, gestion du service) est entièrement contenue dans le rôle externe **[ansible-role-element-web](https://github.com/sepp67/ansible-role-element-web)**. Ce dépôt d'infrastructure fournit uniquement :

- le groupe d'inventaire (`element_web`) ;
- les variables du rôle dans `inventories/<env>/group_vars/all/main.yml` ;
- le routage Caddy (`vars/projects/element-web.yml`).

## Architecture

```
[vm-element-web-staging]  192.168.1.80   → element_web   Client web Element

[vm-proxy-staging]        192.168.1.56   → Caddy
  └── element.lavallee.local → 192.168.1.80:8080
```

## Prérequis

Installer le rôle externe avant le premier déploiement :

```bash
ansible-galaxy install -r requirements.yml
```

## Déploiement

Le déploiement Element Web passe par le playbook d'orchestration unique `deploy-apps.yml`.

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

### Ciblé uniquement

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml \
  --ask-vault-pass --limit element_web
```

## Validation

### Validation locale (accès direct à la VM)

```bash
curl http://<IP_VM_ELEMENT>:8080/config.json
```

### Validation via le proxy Caddy

```bash
curl https://element.staging.lavallee.tech/config.json
```

## Routage Caddy

Le routage proxy est déclaré dans :

- [`vars/projects/element-web.yml`](../vars/projects/element-web.yml) — `project_type: external_service`

Ce fichier est chargé automatiquement par `playbooks/deploy-proxy.yml` via le registre `active_projects`. Le routage est appliqué indépendamment du déploiement Element.

```bash
# Mettre à jour le Caddyfile uniquement
ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-proxy.yml --ask-vault-pass
```

## Variables du rôle

Les variables sont définies dans `inventories/staging/group_vars/all/main.yml`.

| Variable | Description |
|---|---|
| `element_default_homeserver_url` | URL du homeserver Matrix par défaut |
| `element_default_homeserver_name` | Nom affiché du homeserver |
| `element_disable_custom_urls` | Désactive la saisie d'un homeserver personnalisé |
| `element_disable_guests` | Désactive les connexions invités |
| `element_brand` | Marque affichée dans l'interface |
| `element_http_port` | Port HTTP sur lequel Element écoute |

## Mise à jour du rôle

```bash
ansible-galaxy install -r requirements.yml --force
```
