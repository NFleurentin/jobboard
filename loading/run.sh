#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID doit être défini avant l'appel}"
: "${INGESTED_AT:?INGESTED_AT doit être défini avant l'appel (export INGESTED_AT=$(date -u +%Y%m%dT%H%M%SZ))}"

bq load --project_id="$GCP_PROJECT_ID" --location=europe-west1 \
  --source_format=NEWLINE_DELIMITED_JSON \
  --schema="$(dirname "$0")/schemas/france_travail/offers_raw.json" \
  --time_partitioning_field=_ingested_at \
  --time_partitioning_type=DAY \
  "raw.france_travail_offers" \
  "gs://${GCP_PROJECT_ID}-raw/france-travail/offers/ingested_at=${INGESTED_AT}/part-*.jsonl"

echo "Chargement terminé : raw.france_travail_offers, run ${INGESTED_AT}, projet ${GCP_PROJECT_ID}"