# caddy_ca

Rôle Ansible local — distribue le certificat CA interne Caddy sur les VMs cibles.

---

## Pourquoi ce rôle existe

En staging, Caddy utilise `tls internal` : il génère une CA locale et signe lui-même tous les certificats. Cette CA n'est reconnue par aucun système par défaut.

Les services Docker qui établissent des connexions HTTPS vers d'autres services derrière Caddy (fédération Matrix, appels inter-services) voient l'erreur suivante sans ce rôle :

```
SSL certificate problem: unable to get local issuer certificate
```

Ce rôle distribue le certificat CA depuis `vm-proxy` vers toutes les VMs qui en ont besoin.

---

## Pourquoi pas une image Docker personnalisée

Construire une image Docker avec la CA intégrée est une anti-pattern pour une CA locale :

- La CA Caddy change à chaque réinstallation du proxy
- Reconstruire et pousser une image à chaque rotation de CA est fragile
- La CA est un artefact d'infrastructure, pas un composant applicatif

La solution correcte est de distribuer le certificat via Ansible et de le monter dans le conteneur. La CA reste dans le système de fichiers hôte, versionnée implicitement par Ansible.

---

## Pourquoi pas un `update-ca-certificates` dans le playbook

Installer la CA dans le trust store du système hôte (`/usr/local/share/ca-certificates/`) n'affecte pas les conteneurs Docker. Chaque conteneur a son propre trust store.

La CA doit être montée dans le conteneur et installée via `update-ca-certificates` au démarrage du conteneur. C'est pourquoi chaque service Docker qui a besoin de faire confiance à cette CA doit avoir un entrypoint dédié.

---

## Responsabilités

Ce rôle fait **uniquement** :

1. Crée le répertoire `caddy_ca_cert_dir` sur la VM cible
2. Écrit le certificat CA (contenu PEM fourni en variable)

Ce rôle ne connaît rien de :

- Matrix / Synapse
- Docker
- Les conteneurs qui utiliseront ce certificat

L'installation de la CA dans les conteneurs Docker est la responsabilité de chaque rôle applicatif (via un entrypoint dédié).

---

## Variables

| Variable | Défaut | Description |
|---|---|---|
| `caddy_ca_enabled` | `true` | Désactiver le rôle sans le retirer du playbook |
| `caddy_ca_cert_content` | `""` | Contenu PEM du certificat (vide = no-op) |
| `caddy_ca_cert_dir` | `/opt/caddy-ca` | Répertoire cible sur la VM |
| `caddy_ca_cert_filename` | `caddy-root.crt` | Nom du fichier certificat |

---

## Utilisation dans le playbook

Le contenu du certificat est récupéré depuis `vm-proxy` via `slurp` puis distribué :

```yaml
# Play A : Fetch CA depuis vm-proxy (no-op si caddy_tls_mode != "internal")
- name: Fetch Caddy local CA certificate
  hosts: proxy
  gather_facts: false
  tasks:
    - name: Read Caddy root CA certificate
      ansible.builtin.slurp:
        src: /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
      register: _caddy_ca
      when: caddy_tls_mode == "internal"

# Play B : Distribuer la CA sur les VMs cibles
- name: Distribute Caddy CA to internal service hosts
  hosts: matrix_users:matrix_bridges
  become: true
  roles:
    - role: caddy_ca
      vars:
        caddy_ca_cert_content: >-
          {{
            hostvars[groups['proxy'][0]]['_caddy_ca']['content'] | b64decode
            if (groups['proxy'] | length > 0
                and '_caddy_ca' in hostvars[groups['proxy'][0]]
                and 'content' in hostvars[groups['proxy'][0]]['_caddy_ca'])
            else ''
          }}
```

---

## Compatibilité et déploiements partiels

Si `caddy_ca_cert_content` est vide (production ACME, `--limit` sans le groupe proxy), toutes les tâches sont des no-ops. Le rôle ne provoque aucune erreur.

---

## Réutilisation par d'autres services

Ce rôle est conçu pour être réutilisé par n'importe quel service interne nécessitant de faire confiance à la CA Caddy :

- Keycloak
- OpenLDAP / privacyIDEA
- Gitea
- Grafana / Loki / Prometheus
- MinIO

Ajouter le groupe de VMs concerné dans le play de distribution et le chemin du cert dans la variable correspondante du rôle applicatif.
