#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# commit-staging-fixes.sh
#
# À exécuter à la racine du dépôt local devops_staging_prod_infra
# (celui que tu as déjà cloné et modifié au fil des sessions précédentes).
#
# Ce script vérifie que les 3 corrections suivantes sont bien présentes,
# puis crée UN SEUL commit contenant uniquement ces 3 corrections :
#
#   1. docker_bind_address (binding réseau docker_app)
#   2. caddy_log_dir (création explicite du répertoire de logs)
#   3. séparation des domaines staging/production (facturier_domain,
#      grav_docs_domain, nextcloud_domain, lavallee_domain)
#
# Le firewall n'est PAS traité ici — tâche séparée à venir après
# validation du routage staging.
#
# Le script ne touche PAS à main : il committe sur la branche courante.
# Si tu veux une branche dédiée, fais le checkout avant de lancer ce script.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── 0. Vérifications préliminaires ───────────────────────────────────────────

echo "==> Vérification du dépôt..."

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERREUR : ce répertoire n'est pas un dépôt git."
  echo "Lance ce script depuis la racine de devops_staging_prod_infra."
  exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)
echo "    Branche actuelle : $CURRENT_BRANCH"

REQUIRED_FILES=(
  "roles/docker_app/defaults/main.yml"
  "roles/docker_app/templates/docker-compose.yml.j2"
  "roles/caddy_proxy/tasks/main.yml"
  "inventories/staging/group_vars/all.yml"
  "inventories/production/group_vars/all.yml"
  "vars/projects/lavallee-website.yml"
  "vars/projects/facturier-landing.yml"
  "vars/projects/facturier-app.yml"
  "vars/projects/grav-docs.yml"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERREUR : '$f' introuvable. Vérifie que tu es à la racine du dépôt"
    echo "et que les fichiers générés lors des sessions précédentes sont bien en place."
    exit 1
  fi
done

echo "    OK — tous les fichiers attendus sont présents."

# ── 1. Vérification du contenu attendu (garde-fou anti-régression) ───────────

echo ""
echo "==> Vérification du contenu des corrections..."

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -qF "$pattern" "$file"; then
    echo "ERREUR : '$label' absent de $file."
    echo "Attendu : $pattern"
    echo "Le fichier ne correspond peut-être pas à la version générée précédemment."
    echo "Vérifie manuellement avant de relancer ce script."
    exit 1
  fi
}

check_contains "roles/docker_app/defaults/main.yml" \
  'docker_bind_address: "0.0.0.0"' \
  "docker_bind_address default"

check_contains "roles/docker_app/templates/docker-compose.yml.j2" \
  '{{ docker_bind_address }}:{{ project.host_port }}:{{ project.container_port }}' \
  "binding dans docker-compose.yml.j2"

check_contains "roles/caddy_proxy/tasks/main.yml" \
  "Create Caddy log directory" \
  "tâche de création du répertoire de logs"

check_contains "inventories/staging/group_vars/all.yml" \
  "facturier_domain: facturier.local" \
  "facturier_domain (staging)"

check_contains "inventories/staging/group_vars/all.yml" \
  "grav_docs_domain: docs.lavallee.local" \
  "grav_docs_domain (staging)"

check_contains "inventories/production/group_vars/all.yml" \
  "facturier_domain: facturier.lavallee.tech" \
  "facturier_domain (production)"

check_contains "inventories/production/group_vars/all.yml" \
  "grav_docs_domain: docs.lavallee.tech" \
  "grav_docs_domain (production)"

echo "    OK — toutes les corrections attendues sont présentes dans les fichiers."

# ── 2. Staging des fichiers concernés uniquement ──────────────────────────────

echo ""
echo "==> Ajout des fichiers concernés (et uniquement ceux-ci) au staging git..."

git add \
  roles/docker_app/defaults/main.yml \
  roles/docker_app/templates/docker-compose.yml.j2 \
  roles/caddy_proxy/tasks/main.yml \
  inventories/staging/group_vars/all.yml \
  inventories/production/group_vars/all.yml \
  vars/projects/lavallee-website.yml \
  vars/projects/facturier-landing.yml \
  vars/projects/facturier-app.yml \
  vars/projects/grav-docs.yml

echo "    Fichiers stagés :"
git diff --cached --name-only | sed 's/^/      /'

# ── 3. Vérification qu'il n'y a rien d'autre en attente ──────────────────────

UNSTAGED=$(git diff --name-only)
if [ -n "$UNSTAGED" ]; then
  echo ""
  echo "ATTENTION : des modifications non stagées existent ailleurs dans le dépôt :"
  echo "$UNSTAGED" | sed 's/^/      /'
  echo "Elles ne seront PAS incluses dans ce commit (comportement voulu)."
fi

# ── 4. Commit ─────────────────────────────────────────────────────────────────

echo ""
echo "==> Commit..."
git commit -m "fix: docker_bind_address, caddy log dir, staging/prod domain separation

1. docker_app: fix 502 errors caused by 127.0.0.1 binding
   - Add docker_bind_address default (0.0.0.0)
   - Use it in docker-compose.yml.j2 instead of hardcoded loopback
   - Allows proxy VM to reach app VM containers across the network
   - Note: firewall restriction (proxy IP only) intentionally deferred
     to a separate task, after staging routing is validated

2. caddy_proxy: explicitly create /var/log/caddy before Caddy starts
   - Split directory creation: config/data dirs (0750) vs log dir (0755)
   - Fixes Caddy startup/logging failures due to missing directory

3. Staging/production domain separation (no role duplication):
   - New variables: facturier_domain, grav_docs_domain
   - nextcloud_domain corrected in staging (was incorrectly .tech)
   - vars/projects/*.yml now reference {{ <service>_domain }} instead of
     hardcoded values
   - Staging: lavallee.local, facturier.local, docs.lavallee.local, nextcloud.local
   - Production: lavallee.tech, facturier.lavallee.tech, docs.lavallee.tech,
     nextcloud.lavallee.tech (unchanged behavior)
   - Roles and templates unchanged: only group_vars data differs by environment"

echo "    OK"

# ── 5. Résumé ─────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " COMMIT CRÉÉ SUR LA BRANCHE : $CURRENT_BRANCH"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo " Ce commit ne contient PAS de modification firewall (volontaire)."
echo ""
echo " Prochaines étapes :"
echo "   1. git push (si tu veux pousser maintenant)"
echo "   2. Tester le routage staging :"
echo "      ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-apps.yml --ask-vault-pass"
echo "      ansible-playbook -i inventories/staging/hosts.yml playbooks/deploy-proxy.yml --ask-vault-pass"
echo "   3. Vérifier /etc/hosts sur ta machine de test :"
echo "      10.10.1.10  lavallee.local"
echo "   4. Tester : https://lavallee.local"
echo "   5. Une fois validé, on traite le firewall dans une tâche séparée."
echo ""
