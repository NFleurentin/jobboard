#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID doit être défini avant de lancer le script}"
: "${INGESTED_AT:?INGESTED_AT doit être défini avant de lancer le script (export INGESTED_AT=\$(date -u +%Y%m%dT%H%M%SZ))}"
: "${MELTANO_ENVIRONMENT:?MELTANO_ENVIRONMENT doit être défini (dev ou prod)}"

cd "$(dirname "$0")"

export MELTANO_STATE_BACKEND_URI="gs://${GCP_PROJECT_ID}-meltano-state/state"

meltano --environment="$MELTANO_ENVIRONMENT" \
  run --state-id-suffix=france-travail tap-francetravail target-gcs--francetravail

# Marqueur de fin de run : seuls les dossiers qui le contiennent sont chargés
# (issue #85). Écrit en dernier, donc seulement si meltano a réussi (set -e).
# Même chemin que key_naming_convention dans
# plugins/loaders/target-gcs--francetravail.meltano.yml : les garder alignés.
# sa-extract (objectCreator) ne peut pas écraser un objet : relancer avec le
# même INGESTED_AT échoue ici, un run = un INGESTED_AT.
gcloud storage cp /dev/null \
  "gs://${GCP_PROJECT_ID}-raw/france-travail/offers/ingested_at=${INGESTED_AT}/_SUCCESS"

echo "Run ${INGESTED_AT} terminé sur ${GCP_PROJECT_ID}"
