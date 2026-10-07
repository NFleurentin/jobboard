#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID doit être défini avant de lancer le script}"
: "${INGESTED_AT:?INGESTED_AT doit être défini avant de lancer le script (export INGESTED_AT=\$(date -u +%Y%m%dT%H%M%SZ))}"
: "${MELTANO_ENVIRONMENT:?MELTANO_ENVIRONMENT doit être défini (dev ou prod)}"

cd "$(dirname "$0")"

export MELTANO_STATE_BACKEND_URI="gs://${GCP_PROJECT_ID}-meltano-state/state"

meltano --environment="$MELTANO_ENVIRONMENT" \
  run --state-id-suffix=france-travail tap-francetravail target-gcs--francetravail

echo "Run ${INGESTED_AT} terminé sur ${GCP_PROJECT_ID}"
