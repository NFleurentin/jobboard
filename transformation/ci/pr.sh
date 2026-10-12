#!/usr/bin/env bash
# Build dbt d'une pull request dans le dataset pr_<PR_NUMBER> du projet de dev (issue #104).
#
#   ./ci/pr.sh build : modèles modifiés et leurs descendants (state:modified+),
#                      le reste lu dans analytics de dev (--defer)
#   ./ci/pr.sh drop  : suppression du dataset pr_<PR_NUMBER>
#
# Variables : GCP_PROJECT_ID (projet de dev uniquement), PR_NUMBER (entier),
# BASE_SHA (commit de référence, origin/main par défaut).
#
# Le manifest de référence est produit à chaque appel par un dbt parse --target dev
# du commit de base : aucun artefact à conserver. Les snapshots sont exclus, donc
# lus dans analytics : reconstruits depuis un seul run, leur historique serait
# artificiel. Appelé tel quel en local et par .github/workflows/dbt-pr.yml.
#
# En local, gcloud et bq doivent agir en tant que sa-dbt, comme dbt (profiles.yml) :
# export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=sa-dbt@<projet>.iam.gserviceaccount.com
# Sans elle, INFORMATION_SCHEMA.JOBS_BY_USER ne voit pas les jobs du build. En CI,
# l'authentification WIF fournit déjà cette identité.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  echo "Usage : PR_NUMBER=<n> GCP_PROJECT_ID=<projet de dev> $0 build|drop" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID doit être défini}"
: "${PR_NUMBER:?PR_NUMBER doit être défini}"
# Entier strict : PR_NUMBER entre dans le nom du dataset supprimé par drop
[[ $PR_NUMBER =~ ^[0-9]+$ ]] || { echo "PR_NUMBER doit être un entier" >&2; exit 2; }
# Le target ci écrit dans le projet de GCP_PROJECT_ID : refuser tout autre projet que dev
[[ $GCP_PROJECT_ID == *-dev-* ]] || { echo "GCP_PROJECT_ID doit désigner le projet de dev" >&2; exit 2; }
export PR_NUMBER GCP_PROJECT_ID

dataset="pr_${PR_NUMBER}"

build() {
  local base_sha="${BASE_SHA:-origin/main}"
  local tmp
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064 # $tmp est fixé ici, volontairement
  trap "git worktree remove --force '$tmp/base' 2>/dev/null; rm -rf '$tmp'" EXIT

  # Manifest de référence : en --target dev, ses relations pointent vers analytics,
  # cible du --defer. Aucune connexion BigQuery pour un parse.
  git worktree add --detach --quiet "$tmp/base" "$base_sha"
  (
    cd "$tmp/base/transformation"
    dbt deps
    dbt parse --target dev --target-path "$tmp/state"
  )

  # Dernier run terminé : requis par les tests d'eph_france_travail__offers. Une
  # valeur factice les ferait passer sur une partition vide, sans rien vérifier.
  local run
  run=$(gcloud storage ls "gs://${GCP_PROJECT_ID}-raw/france-travail/offers/*/_SUCCESS" \
    | sed -nE 's#.*/ingested_at=([0-9]{8}T[0-9]{6}Z)/_SUCCESS$#\1#p' \
    | sort | tail -n 1)
  [[ -n $run ]] || { echo "Aucun run terminé (_SUCCESS) dans le bucket raw" >&2; exit 1; }
  echo "Run utilisé pour ingested_at : ${run}"

  local status=0
  dbt build --target ci \
    --select state:modified+ \
    --defer --state "$tmp/state" \
    --exclude-resource-type snapshot \
    --vars "{ingested_at: \"${run}\"}" || status=$?

  # Coût du run, y compris en cas d'échec. Fusion ne renseigne ni bytes_billed ni
  # bytes_processed dans run_results.json, mais expose le job_id de chaque nœud :
  # le coût se lit dans INFORMATION_SCHEMA.JOBS_BY_USER (jobs de sa-dbt).
  local job_ids summary
  job_ids=$(jq -c '[.results[].adapter_response.job_id // empty]' target/run_results.json)
  if [[ $job_ids == "[]" ]]; then
    summary="aucun modèle modifié, rien à construire"
  else
    local expected found bytes
    expected=$(jq 'length' <<< "$job_ids")
    # shellcheck disable=SC2016 # backticks SQL littéraux, aucune expansion attendue
    IFS=, read -r found bytes < <(bq query \
      --nouse_legacy_sql \
      --project_id="$GCP_PROJECT_ID" \
      --maximum_bytes_billed=100000000 \
      --format=csv \
      --quiet \
      --parameter="ids:ARRAY<STRING>:${job_ids}" \
      'SELECT COUNT(*), IFNULL(SUM(total_bytes_billed), 0)
       FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS_BY_USER
       WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
         AND job_id IN UNNEST(@ids)' \
      | tail -n 1)
    summary="${bytes} octets facturés (${found} jobs sur ${expected})"
    # Mesure secondaire : un écart avertit sans faire échouer le build
    [[ $found -eq $expected ]] \
      || echo "Coût incomplet : ${found} jobs retrouvés sur ${expected}, bq agit-il en tant que sa-dbt ?" >&2
  fi
  echo "Coût : ${summary}"
  [[ -z ${GITHUB_STEP_SUMMARY:-} ]] \
    || echo "dbt build de \`${dataset}\` : ${summary}" >> "$GITHUB_STEP_SUMMARY"

  echo "Build de ${dataset} $([[ $status -eq 0 ]] && echo terminé || echo 'en échec') : run ${run}, référence ${base_sha}, projet ${GCP_PROJECT_ID}"
  return "$status"
}

drop() {
  # Rien à supprimer si aucun build n'a créé le dataset (PR sans modèle modifié)
  if ! bq show --dataset "${GCP_PROJECT_ID}:${dataset}" > /dev/null 2>&1; then
    echo "Dataset ${dataset} absent, rien à supprimer"
    return 0
  fi
  bq rm --recursive --force --dataset "${GCP_PROJECT_ID}:${dataset}"
  echo "Dataset ${dataset} supprimé du projet ${GCP_PROJECT_ID}"
}

case "$1" in
  build) build ;;
  drop) drop ;;
  *) usage ;;
esac
