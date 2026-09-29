#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID doit être défini avant l'appel}"
: "${INGESTED_AT:?INGESTED_AT doit être défini avant l'appel (export INGESTED_AT=$(date -u +%Y%m%dT%H%M%SZ))}"

export MELTANO_STATE_BACKEND_URI="gs://${GCP_PROJECT_ID}-meltano-state/state"

meltano --environment="${MELTANO_ENVIRONMENT:?MELTANO_ENVIRONMENT doit être défini (dev ou prod)}" \
  run --state-id-suffix=france-travail tap-francetravail target-gcs--francetravail

echo "Run ${INGESTED_AT} terminé sur ${GCP_PROJECT_ID}"