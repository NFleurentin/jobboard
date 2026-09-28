#!/usr/bin/env bash
# Bootstrap GCP : projets dev/prod, facturation, APIs, bucket de state Terraform.
# Rejouable : chaque étape vérifie l'existant avant de créer.
#
# Usage :
#   export PROJECT_PREFIX="jobboard" SUFFIX="yyy" BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"
#   ./bootstrap.sh
set -euo pipefail  # arrêt sur erreur, variable non définie interdite, échec propagé dans les pipes

: "${PROJECT_PREFIX:?à définir}" "${SUFFIX:?à définir}" "${BILLING_ACCOUNT:?à définir}"
LOCATION="${LOCATION:-europe-west1}"

APIS=(
  bigquery.googleapis.com # Entrepôt de données analytique
  storage.googleapis.com # Stockage brut et bucket Terraform
  secretmanager.googleapis.com # Gestion des secrets
  iam.googleapis.com # Créer et gérer des service accounts
  iamcredentials.googleapis.com # Générer des jetons temporaires
  sts.googleapis.com # Echange du jeton GitHub contre un accès GCP (WIF)                 
  cloudresourcemanager.googleapis.com # Terraform l'utilise pour lire l'état des APIs
  serviceusage.googleapis.com # Terraform nécessite cette API pour gérer les services Google Cloud
  artifactregistry.googleapis.com # Stocke les images Docker et autres artefacts
  run.googleapis.com # Execute les conteneurs sur Cloud Run (LLM, Meltano)
)

echo "Compte actif : $(gcloud config get-value account 2>/dev/null)"

for E in dev prod; do
  P="${PROJECT_PREFIX}-${E}-${SUFFIX}"
  echo "==> ${P}"

  # 1. Projet
  if gcloud projects describe "$P" >/dev/null 2>&1; then
    echo "    projet déjà existant"
  else
    gcloud projects create "$P" --name="offres d'emploi - ${E}"
  fi

  # 2. Facturation (ré-exécutable sans effet de bord)
  gcloud billing projects link "$P" --billing-account="$BILLING_ACCOUNT"

  # 3. APIs (ré-exécutable)
  gcloud services enable "${APIS[@]}" --project="$P"

  # 4. Bucket de state Terraform, versionné
  BUCKET="gs://${P}-tfstate"
  if gcloud storage buckets describe "$BUCKET" >/dev/null 2>&1; then
    echo "    bucket déjà existant"
  else
    gcloud storage buckets create "$BUCKET" \
      --project="$P" --location="$LOCATION" --uniform-bucket-level-access
  fi
  gcloud storage buckets update "$BUCKET" --versioning
done

echo "Terminé. N'oublie pas de créer l'alerte de budget (console : Facturation > Budgets et alertes)."