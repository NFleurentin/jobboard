#!/usr/bin/env bash
# Plan Terraform d'une racine de dev, publié dans le résumé du job (issue #105).
#
#   ./ci/plan.sh envs/dev
#
# Variables : TF_VAR_user_email (exigée par envs/dev, jamais versionnée),
# GITHUB_STEP_SUMMARY (optionnelle : en CI, fichier du résumé du job).
#
# Plan seul, rien n'est appliqué. -lock=false : un plan n'écrit pas le state, et un
# run annulé (cancel-in-progress) laisserait sinon un verrou à lever par force-unlock.
# Le fichier tfplan contient des valeurs sensibles en clair : il reste dans un dossier
# temporaire supprimé en fin de script. Appelé tel quel en local et par
# .github/workflows/terraform-pr.yml.
#
# Code de sortie : 0 si le plan aboutit, avec ou sans changements ; 1 en cas d'erreur.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  echo "Usage : TF_VAR_user_email=<compte Google> $0 envs/dev" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
root="$1"
# Liste explicite plutôt qu'un motif : un plan avec les identifiants de prod est
# interdit depuis le poste local, et le WIF de prod refuse les branches de PR
case "$root" in
  envs/dev) ;;
  *) echo "Racine non autorisée : ${root} (autorisées : envs/dev)" >&2; exit 2 ;;
esac
: "${TF_VAR_user_email:?TF_VAR_user_email doit être défini}"

# Sorties sans conseils destinés à un humain (« run terraform apply »)
export TF_IN_AUTOMATION=1
# Taille maximale du plan recopié dans le résumé, limité à 1 Mio par étape
max_bytes=900000

tmp=$(mktemp -d)
# shellcheck disable=SC2064 # $tmp est fixé ici, volontairement
trap "rm -rf '$tmp'" EXIT

summary() {
  [[ -z ${GITHUB_STEP_SUMMARY:-} ]] || cat >> "$GITHUB_STEP_SUMMARY"
}

# Résumé d'erreur : fin du log, lisible sans ouvrir les logs du job
fail() {
  local step="$1"
  {
    echo "### Plan Terraform \`${root}\` : échec (${step})"
    echo
    echo '```'
    tail -n 50 "$tmp/${step}.log"
    echo '```'
  } | summary
  echo "Plan de ${root} en échec (${step})" >&2
  exit 1
}

cd "$root"

rc=0
terraform init -input=false -lockfile=readonly -no-color 2>&1 | tee "$tmp/init.log" || rc=$?
[[ $rc -eq 0 ]] || fail init

# -detailed-exitcode : 0 aucun changement, 2 changements, 1 erreur
terraform plan -input=false -lock=false -no-color -detailed-exitcode -out="$tmp/tfplan" \
  2>&1 | tee "$tmp/plan.log" || rc=$?

case "$rc" in
  0)
    echo "### Plan Terraform \`${root}\` : aucun changement" | summary
    ;;
  2)
    # Fichier intermédiaire : head sur un pipe couperait terraform show (SIGPIPE),
    # que pipefail transformerait en échec
    terraform show -no-color "$tmp/tfplan" > "$tmp/show.txt"
    {
      echo "### Plan Terraform \`${root}\` : $(grep -m 1 '^Plan:' "$tmp/plan.log" || echo 'changements')"
      echo
      echo '<details><summary>Détail du plan</summary>'
      echo
      echo '```'
      head -c "$max_bytes" "$tmp/show.txt"
      echo '```'
      if [[ $(wc -c < "$tmp/show.txt") -gt $max_bytes ]]; then
        echo
        echo "Plan tronqué à ${max_bytes} octets : détail complet dans les logs du job."
      fi
      echo
      echo '</details>'
    } | summary
    ;;
  *)
    fail plan
    ;;
esac

echo "Plan de ${root} terminé (code ${rc} : 0 aucun changement, 2 changements)"
