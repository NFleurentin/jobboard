#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID doit être défini avant de lancer le script}"
: "${INGESTED_AT:?INGESTED_AT doit être défini avant de lancer le script (export INGESTED_AT=\$(date -u +%Y%m%dT%H%M%SZ))}"

bq load --project_id="$GCP_PROJECT_ID" --location=europe-west1 \
  --source_format=NEWLINE_DELIMITED_JSON \
  --schema="$(dirname "$0")/schemas/france_travail/offers_raw.json" \
  --time_partitioning_field=_ingested_at \
  --time_partitioning_type=DAY \
  "raw.france_travail_offers" \
  "gs://${GCP_PROJECT_ID}-raw/france-travail/offers/ingested_at=${INGESTED_AT}/part-*.jsonl"

# Rejette toute requête sans filtre sur _ingested_at (scan de tout
# l'historique de _raw). Appliqué à chaque run plutôt qu'au seul bq load,
# qui ne positionne l'option qu'à la création de la table : couvre les
# tables existantes et corrige une éventuelle dérive. Idempotent, gratuit.
bq update --project_id="$GCP_PROJECT_ID" \
  --require_partition_filter=true \
  "raw.france_travail_offers"

echo "Chargement terminé : raw.france_travail_offers, run ${INGESTED_AT}, projet ${GCP_PROJECT_ID}"
