#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: ./run.sh dev|prod}"
[[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "prod" ]] || { echo "Environnement invalide : ${ENVIRONMENT}" >&2; exit 1; }

: "${INGESTED_AT:?INGESTED_AT doit être défini avant l'appel (export INGESTED_AT=$(date -u +%Y%m%dT%H%M%SZ))}"

export MELTANO_STATE_BACKEND_URI="gs://jobboard-${ENVIRONMENT}-3b375b-meltano-state/state"

meltano --environment="$ENVIRONMENT" run --state-id-suffix=france-travail tap-francetravail target-gcs--francetravail

echo "Run terminé sur ${ENVIRONMENT} à ${INGESTED_AT}"