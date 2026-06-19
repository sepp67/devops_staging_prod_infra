#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# commit-webcam-target-group-fix.sh
#
# À exécuter à la racine du dépôt local devops_staging_prod_infra.
#
# Corrige un trou de conception découvert lors du premier déploiement de
# webcam : deploy-apps.yml ciblait "hosts: apps" en dur depuis toujours,
# ce qui a fait tourner la tâche de déploiement webcam sur vm-apps-staging
# au lieu de vm-camera-claude (groupe [webcam]).
#
# Erreur observée :
#   TASK [docker_app : Pull latest image for webcam]
#   fatal: [vm-apps-staging]: FAILED! => ... error from registry: denied
#
# Le "denied" est probablement un second problème distinct (accès GHCR
# depuis vm-camera-claude) — mais avant même de pouvoir le diagnostiquer,
# il fallait que le déploiement webcam tourne sur le bon hôte.
#
# Correction :
#   - playbooks/deploy-apps.yml cible désormais "apps:webcam" (et tout
#     futur groupe dédié), avec un filtre qui restreint la liste des
#     projets déployés sur CHAQUE hôte à ceux dont target_group correspond
#     à l'un de ses groupes (group_names).
#   - Chaque vars/projects/*.yml déclare désormais explicitement
#     target_group (apps pour les projets existants, webcam pour le nouveau).
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
  "playbooks/deploy-apps.yml"
  "vars/projects/lavallee-website.yml"
  "vars/projects/facturier-landing.yml"
  "vars/projects/facturier-app.yml"
  "vars/projects/grav-docs.yml"
  "vars/projects/webcam.yml"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERREUR : '$f' introuvable. Vérifie que tu es à la racine du dépôt"
    echo "et que l'intégration webcam précédente a bien été committée."
    exit 1
  fi
done

echo "    OK — fichiers attendus présents."

echo ""
echo "==> 1/6 — playbooks/deploy-apps.yml"
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
#   3. Définir target_group: <groupe d'inventaire qui doit héberger ce projet>
#      ("apps" pour la VM applicative générique, ou un groupe dédié comme
#      "webcam" pour un projet sur sa propre VM)
#   → Aucun rôle à modifier.
#
# IMPORTANT : ce playbook cible apps:webcam (et tout autre groupe dédié
# ajouté à l'avenir), PAS seulement apps. Chaque hôte ne déploie que les
# projets dont target_group correspond à l'un de ses propres groupes
# (group_names) — sans ce filtre, un projet à VM dédiée (ex: webcam) serait
# aussi déployé par erreur sur vm-apps-staging.
#
# project_type: external_service n'est JAMAIS inclus dans les boucles
# ci-dessous. Ces projets (ex: nextcloud) sont routés par caddy_proxy
# uniquement (voir playbooks/deploy-proxy.yml) — leur cycle de vie applicatif
# est géré manuellement, hors de ce dépôt. Voir README.md, section
# "Services externes", pour la justification complète.
# ─────────────────────────────────────────────────────────────────────────────
- name: Load project registry and deploy applications
  hosts: apps:webcam
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

    - name: Restrict projects list to this host's target_group
      ansible.builtin.set_fact:
        projects: "{{ projects | selectattr('target_group', 'in', group_names) | list }}"
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
echo "==> 2/6 — vars/projects/lavallee-website.yml"
cat > vars/projects/lavallee-website.yml << 'LAVALLEE_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Projet : lavallee-website
# Site portfolio/blog Hugo + Nginx
# ─────────────────────────────────────────────────────────────────────────────
project_name: lavallee-website
project_type: docker_app
target_group: apps
image: ghcr.io/sepp67/ansible-role-website-lavallee:latest
container_port: 80
host_port: 18082
domain: "{{ lavallee_domain }}"
route_path: /
healthcheck_url: "http://127.0.0.1:18082/"
docker_environment: {}
volumes: []
LAVALLEE_EOF

echo ""
echo "==> 3/6 — vars/projects/facturier-landing.yml"
cat > vars/projects/facturier-landing.yml << 'FACTLANDING_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Projet : facturier-landing
# Landing page publique de facturier.lavallee.tech
# ─────────────────────────────────────────────────────────────────────────────
project_name: facturier-landing
project_type: docker_app
target_group: apps
image: ghcr.io/sepp67/facturier-landing:latest
container_port: 80
host_port: 18080
domain: "{{ facturier_domain }}"
route_path: /
healthcheck_url: "http://{{ backend_host }}:18080/"
docker_environment: {}
volumes: []
FACTLANDING_EOF

echo ""
echo "==> 4/6 — vars/projects/facturier-app.yml"
cat > vars/projects/facturier-app.yml << 'FACTAPP_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Projet : facturier-app
# Application démo Factur-X, exposée sur /app via Caddy
# strip_prefix: true → Caddy retire /app avant de forwarder au conteneur
# ─────────────────────────────────────────────────────────────────────────────
project_name: facturier-app
project_type: docker_app
target_group: apps
image: ghcr.io/sepp67/facturier-app:latest
container_port: 8000
host_port: 18081
domain: "{{ facturier_domain }}"
route_path: /app/*
strip_prefix: true
extra_routes:
  - route_path: /api/*
    strip_prefix: false
healthcheck_url: "http://{{ backend_host }}:18081/health"
healthcheck_path: /health
command:
  - uvicorn
  - api:app
  - --host
  - 0.0.0.0
  - --port
  - "8000"
  - --root-path
  - /app
docker_environment:
  APP_ENV: "{{ environment_name }}"
volumes: []
FACTAPP_EOF

echo ""
echo "==> 5/6 — vars/projects/grav-docs.yml"
cat > vars/projects/grav-docs.yml << 'GRAVDOCS_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Projet : grav-docs
# Documentation interne Grav — volume persistant requis
# project_type: grav_stack → déployé par le rôle grav_stack, pas docker_app
#
# Bootstrap admin optionnel : grav_admin_user/password/email sont définis
# dans inventories/<env>/group_vars/all.yml (eux-mêmes référençant le Vault).
# Si l'une des trois variables est absente ou vide, l'image grav-docs
# n'effectue aucun bootstrap (comportement par défaut, voir docker/bootstrap-admin.sh
# dans le dépôt grav-docs).
# ─────────────────────────────────────────────────────────────────────────────
project_name: grav-docs
project_type: grav_stack
target_group: apps
image: ghcr.io/sepp67/grav-docs:latest
container_port: 80
host_port: 18084
domain: "{{ grav_docs_domain }}"
route_path: /
healthcheck_url: "http://{{ backend_host }}:18084/"
docker_environment:
  GRAV_ADMIN_USER: "{{ grav_admin_user | default('') }}"
  GRAV_ADMIN_PASSWORD: "{{ grav_admin_password | default('') }}"
  GRAV_ADMIN_EMAIL: "{{ grav_admin_email | default('') }}"
volumes:
  - /opt/grav-docs/data:/var/www/html/user
GRAVDOCS_EOF

echo ""
echo "==> 6/6 — vars/projects/webcam.yml"
cat > vars/projects/webcam.yml << 'WEBCAM_EOF'
---
# ─────────────────────────────────────────────────────────────────────────────
# Projet : webcam
# Flux webcam RTSP→HLS + galerie de snapshots (lever/coucher du soleil)
# project_type: docker_app — pas de rôle dédié, voir README.md pour la
# justification (app simple, complexité réseau gérée au niveau VM, pas rôle)
#
# VM dédiée (vm-camera-claude), distincte du groupe [apps] générique, car
# contrainte réseau spécifique : la VM a une seconde interface sur le réseau
# caméra (192.168.8.0/24) pour atteindre la caméra physique en RTSP. Caddy
# route vers webcam_backend_host (IP LAN de cette VM), pas vers le backend_host
# global de vm-apps-staging. Voir README.md, section "Services à VM dédiée".
#
# target_group indique à deploy-apps.yml SUR QUEL groupe d'inventaire ce
# projet doit être déployé (pas seulement routé). Sans ce champ, deploy-apps.yml
# déploierait ce projet sur tous les hôtes visés par le playbook, y compris
# vm-apps-staging — ce qui échoue (image jamais buildée pour cette VM, ou
# tentative de pull sur le mauvais réseau).
#
# Volumes — analyse du code source (entrypoint.sh, snapshot_runner.py) :
#   - /var/www/html/gallery : PERSISTANT. snapshot_runner.py y écrit des
#     .jpg horodatés et applique une rétention de 31 jours basée sur leur
#     date de modification (cleanup()). Sans volume, l'historique serait
#     perdu à chaque redéploiement.
#   - /var/www/html/stream : PAS de volume. Tampon HLS glissant de ~8
#     secondes (hls_time 2 × hls_list_size 4), purgé par ffmpeg lui-même
#     (-hls_flags delete_segments) ET réinitialisé explicitement par
#     entrypoint.sh (rm -f *.ts *.m3u8) à chaque démarrage. Aucune donnée
#     à préserver.
# ─────────────────────────────────────────────────────────────────────────────
project_name: webcam
project_type: docker_app
image: ghcr.io/sepp67/webcam-stream:latest
container_port: 80
host_port: 18086
domain: "{{ webcam_domain }}"
route_path: /
healthcheck_url: "http://{{ webcam_backend_host }}:18086/"
backend_host: "{{ webcam_backend_host }}"
target_group: webcam

docker_environment:
  RTSP_URL: "{{ vault_webcam_rtsp_url }}"
  WEBCAM_LATITUDE: "48.4636"
  WEBCAM_LONGITUDE: "7.4811"
  WEBCAM_TIMEZONE: "Europe/Paris"
  SNAPSHOT_RETENTION_DAYS: "31"

volumes:
  - /opt/webcam/gallery:/var/www/html/gallery
WEBCAM_EOF

echo ""
echo "==> Ajout des fichiers modifiés au staging git..."
git add \
  playbooks/deploy-apps.yml \
  vars/projects/lavallee-website.yml \
  vars/projects/facturier-landing.yml \
  vars/projects/facturier-app.yml \
  vars/projects/grav-docs.yml \
  vars/projects/webcam.yml

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
git commit -m "fix: deploy-apps.yml ciblait hosts: apps en dur, webcam ne pouvait jamais se déployer sur sa propre VM

Bug découvert au premier déploiement réel de webcam :

  TASK [docker_app : Pull latest image for webcam]
  fatal: [vm-apps-staging]: FAILED! => ... error from registry: denied

webcam est sur le groupe d'inventaire [webcam] (vm-camera-claude), mais
deploy-apps.yml ciblait 'hosts: apps' depuis son tout premier commit —
jamais remis en question parce que tous les projets docker_app
précédents tournaient effectivement sur vm-apps-staging. Ansible a donc
exécuté la tâche de déploiement webcam sur vm-apps-staging (le seul hôte
du groupe apps), pas sur la VM caméra dédiée.

Correction :
  - Introduction d'un champ target_group dans chaque vars/projects/*.yml,
    indiquant explicitement quel groupe d'inventaire doit héberger ce
    projet ('apps' pour les 4 projets existants, 'webcam' pour le nouveau).
  - playbooks/deploy-apps.yml cible désormais 'apps:webcam' (extensible à
    tout futur groupe dédié), avec une nouvelle tâche de filtrage :
      projects | selectattr('target_group', 'in', group_names) | list
    Chaque hôte ne déploie plus que les projets qui lui sont destinés.
  - Validé : un groupe vide dans une expression composite (ex: apps:webcam
    en production, où [webcam] est vide) ne lève ni erreur ni avertissement
    Ansible — seul le groupe apps contribue des hôtes dans ce cas.

Note : l'erreur 'denied' du registre GHCR elle-même est un second problème
distinct (accès à ghcr.io/sepp67/webcam-stream depuis vm-camera-claude),
à diagnostiquer séparément une fois ce ciblage corrigé."

echo "    OK"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " COMMIT CRÉÉ SUR LA BRANCHE : $CURRENT_BRANCH"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo " Prochaines étapes :"
echo "   1. git push (si tu veux pousser maintenant)"
echo "   2. Relancer le déploiement :"
echo "      ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml --ask-vault-pass"
echo "   3. Vérifier que la tâche tourne bien sur vm-camera-claude, pas vm-apps-staging."
echo "   4. Si l'erreur 'denied' persiste, diagnostiquer l'accès GHCR DEPUIS"
echo "      vm-camera-claude (pas depuis votre poste) :"
echo "      docker login ghcr.io -u <votre-user-github>"
echo "      docker pull ghcr.io/sepp67/webcam-stream:latest"
echo ""
