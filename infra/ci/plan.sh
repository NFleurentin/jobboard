#!/usr/bin/env bash
# Plan Terraform d'une racine, publié dans le résumé du job (issues #105, #106), et
# application de ce plan après vérification de son empreinte.
#
#   ./ci/plan.sh envs/dev                       # plan seul
#   ./ci/plan.sh --apply <empreinte> envs/dev   # nouveau plan, appliqué s'il a cette empreinte
#
# Variables : TF_VAR_user_email (exigée par envs/*, jamais versionnée),
# GITHUB_STEP_SUMMARY et GITHUB_OUTPUT (optionnelles : en CI, fichiers du résumé et
# des sorties de l'étape).
#
# Empreinte : sha256 du texte de terraform show. Le fichier tfplan contient des valeurs
# sensibles en clair et ne peut pas passer d'un job à l'autre (artifact téléchargeable
# sur un dépôt public) : le job d'apply refait le plan et ne l'applique que s'il est
# identique à celui relu. Les valeurs sensibles, masquées dans ce texte, n'entrent pas
# dans l'empreinte.
#
# Plan seul : -lock=false, un plan n'écrit pas le state, et un run annulé
# (cancel-in-progress) laisserait sinon un verrou à lever par force-unlock.
# Appelé tel quel en local (envs/dev seulement) et par .github/workflows/terraform-pr.yml
# et terraform-apply.yml.
#
# Sorties (GITHUB_OUTPUT) : fingerprint, changes (true/false).
# Code de sortie : 0 si le plan (et l'apply) aboutit, avec ou sans changements ;
# 1 en cas d'erreur ou d'empreinte différente.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  echo "Usage : TF_VAR_user_email=<compte Google> $0 [--apply <empreinte>] envs/dev" >&2
  exit 2
}

expected=""
if [[ ${1:-} == --apply ]]; then
  [[ $# -eq 3 ]] || usage
  expected="$2"
  shift 2
fi
[[ $# -eq 1 ]] || usage
root="$1"
# Liste explicite plutôt qu'un motif : un plan avec les identifiants de prod est
# interdit depuis le poste local. Le test de GITHUB_ACTIONS n'est qu'un garde-fou contre
# l'erreur : la barrière est le WIF de prod, limité à l'environment prod et à main.
case "$root" in
  envs/dev) ;;
  envs/prod)
    if [[ ${GITHUB_ACTIONS:-} != true ]]; then
      echo "envs/prod : réservé à la CI (terraform-apply.yml), jamais depuis le poste local" >&2
      exit 2
    fi
    ;;
  *) echo "Racine non autorisée : ${root} (autorisées : envs/dev, envs/prod en CI)" >&2; exit 2 ;;
esac
: "${TF_VAR_user_email:?TF_VAR_user_email doit être défini}"

# Sorties sans conseils destinés à un humain (« run terraform apply »)
export TF_IN_AUTOMATION=1
# Taille maximale du plan recopié dans le résumé, limité à 1 Mio par étape
max_bytes=900000

if [[ -n $expected ]]; then
  action=Apply
  lock_opt=()
else
  action=Plan
  lock_opt=(-lock=false)
fi

tmp=$(mktemp -d)
# shellcheck disable=SC2064 # $tmp est fixé ici, volontairement
trap "rm -rf '$tmp'" EXIT

summary() {
  [[ -z ${GITHUB_STEP_SUMMARY:-} ]] || cat >> "$GITHUB_STEP_SUMMARY"
}

output() {
  [[ -z ${GITHUB_OUTPUT:-} ]] || echo "$1" >> "$GITHUB_OUTPUT"
}

# Résumé d'erreur : fin du log, lisible sans ouvrir les logs du job
fail() {
  local step="$1"
  {
    echo "### ${action} Terraform \`${root}\` : échec (${step})"
    echo
    echo '```'
    tail -n 50 "$tmp/${step}.log"
    echo '```'
  } | summary
  echo "${action} de ${root} en échec (${step})" >&2
  exit 1
}

cd "$root"

rc=0
terraform init -input=false -lockfile=readonly -no-color 2>&1 | tee "$tmp/init.log" || rc=$?
[[ $rc -eq 0 ]] || fail init

# -detailed-exitcode : 0 aucun changement, 2 changements, 1 erreur
terraform plan -input=false "${lock_opt[@]}" -no-color -detailed-exitcode -out="$tmp/tfplan" \
  2>&1 | tee "$tmp/plan.log" || rc=$?
[[ $rc -eq 0 || $rc -eq 2 ]] || fail plan

# Fichier intermédiaire : head sur un pipe couperait terraform show (SIGPIPE),
# que pipefail transformerait en échec
terraform show -no-color "$tmp/tfplan" > "$tmp/show.txt"
fingerprint=$(sha256sum "$tmp/show.txt" | cut -d ' ' -f 1)
output "fingerprint=${fingerprint}"
output "changes=$([[ $rc -eq 2 ]] && echo true || echo false)"

if [[ $rc -eq 0 ]]; then
  echo "### ${action} Terraform \`${root}\` : aucun changement" | summary
else
  {
    echo "### ${action} Terraform \`${root}\` : $(grep -m 1 '^Plan:' "$tmp/plan.log" || echo 'changements')"
    echo
    echo "Empreinte du plan : \`${fingerprint}\`"
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
fi

if [[ -z $expected ]]; then
  echo "Plan de ${root} terminé (code ${rc} : 0 aucun changement, 2 changements)"
  exit 0
fi

# Le state ou le code a changé depuis le plan relu (apply local, dérive) : rien n'est
# appliqué, relancer le workflow pour relire le nouveau plan
if [[ $fingerprint != "$expected" ]]; then
  {
    echo
    echo "**Empreinte différente du plan relu (\`${expected}\`) : rien n'est appliqué.**"
  } | summary
  echo "Empreinte ${fingerprint} différente de ${expected} : apply annulé" >&2
  exit 1
fi

if [[ $rc -eq 0 ]]; then
  echo "Aucun changement sur ${root} : rien à appliquer"
  exit 0
fi

# Un plan enregistré s'applique sans confirmation interactive : il est déjà approuvé
rc=0
terraform apply -input=false -no-color "$tmp/tfplan" 2>&1 | tee "$tmp/apply.log" || rc=$?
[[ $rc -eq 0 ]] || fail apply

{
  echo
  echo "Plan appliqué."
} | summary
echo "Apply de ${root} terminé"
