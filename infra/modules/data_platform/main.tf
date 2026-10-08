locals {
  is_dev             = var.env == "dev"
  raw_retention_days = local.is_dev ? 7 : 30
}

# ---------- Buckets ----------
resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-raw"
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = local.is_dev

  lifecycle_rule {
    condition {
      age = local.raw_retention_days
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "enriched" {
  name                        = "${var.project_id}-enriched"
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = local.is_dev
}

resource "google_storage_bucket" "meltano_state" {
  name                        = "${var.project_id}-meltano-state"
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

# ---------- BigQuery ----------

resource "google_bigquery_dataset" "raw" {
  dataset_id                 = "raw"
  location                   = var.location
  delete_contents_on_destroy = local.is_dev
}

resource "google_bigquery_dataset" "meta" {
  dataset_id = "meta"
  location   = var.location
}

# Datasets des couches dbt, en prod seulement : en dev et en CI,
# generate_schema_name regroupe tout dans le dataset du profil, créé par dbt.
resource "google_bigquery_dataset" "dbt_layer" {
  for_each = local.is_dev ? toset([]) : toset(["staging", "intermediate", "marts", "snapshots"])

  dataset_id = each.key
  location   = var.location
}

resource "google_bigquery_table" "state_snapshot" {
  dataset_id = google_bigquery_dataset.meta.dataset_id
  table_id   = "state_snapshot"

  schema = jsonencode([
    { name = "name", type = "STRING", mode = "REQUIRED" },
    { name = "last_ingest", type = "TIMESTAMP", mode = "REQUIRED" },
  ])

  deletion_protection = !local.is_dev
}

# Table externe sur les fichiers du bucket raw : le brut n'est stocké qu'une
# fois, dans GCS (issue #85). Un dossier ingested_at=<run> par run, lu comme
# une partition Hive : la clé ingested_at (STRING) est ajoutée par BigQuery,
# elle ne figure donc pas dans le schéma, et doit être filtrée par chaque
# requête (require_partition_filter). _ingested_at, colonne des fichiers,
# n'élague rien. Suffixe _ext : signale une table externe, et évite un
# renommage (donc un remplacement) à la suppression de la table native.
resource "google_bigquery_table" "france_travail_offers_ext" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  table_id   = "france_travail_offers_ext"

  external_data_configuration {
    autodetect    = false
    source_format = "NEWLINE_DELIMITED_JSON"
    source_uris   = ["gs://${google_storage_bucket.raw.name}/france-travail/offers/*"]

    hive_partitioning_options {
      mode                     = "STRINGS"
      source_uri_prefix        = "gs://${google_storage_bucket.raw.name}/france-travail/offers"
      require_partition_filter = true
    }

    schema = jsonencode([
      { "mode" : "REQUIRED", "name" : "id", "type" : "STRING" },
      { "mode" : "NULLABLE", "name" : "dateActualisation", "type" : "TIMESTAMP" },
      { "mode" : "REQUIRED", "name" : "_raw", "type" : "STRING" },
      { "mode" : "REQUIRED", "name" : "_extracted_at", "type" : "TIMESTAMP" },
      { "mode" : "REQUIRED", "name" : "_ingested_at", "type" : "TIMESTAMP" }
    ])
  }

  deletion_protection = !local.is_dev
}

# ---------- Service accounts ----------
resource "google_service_account" "extract" {
  account_id   = "sa-extract"
  display_name = "Extraction et chargement du brut"
}

resource "google_service_account" "dbt" {
  account_id   = "sa-dbt"
  display_name = "Transformations dbt"
}

resource "google_service_account" "enrich" {
  account_id   = "sa-enrich"
  display_name = "Enrichissement LLM (local)"
}

# ---------- Droits : extraction ----------
resource "google_storage_bucket_iam_member" "extract_raw_create" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectCreator" # crée des objets, n'écrase ni ne supprime
  member = "serviceAccount:${google_service_account.extract.email}"
}

resource "google_storage_bucket_iam_member" "extract_raw_read" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer" # nécessaire au load job BigQuery
  member = "serviceAccount:${google_service_account.extract.email}"
}

resource "google_storage_bucket_iam_member" "extract_raw_legacy_reader" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.legacyBucketReader" # storage.buckets.get, storage.buckets.list
  member = "serviceAccount:${google_service_account.extract.email}"
}

resource "google_storage_bucket_iam_member" "extract_state" {
  bucket = google_storage_bucket.meltano_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.extract.email}"
}

resource "google_bigquery_dataset_iam_member" "extract_raw_editor" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.extract.email}"
}

resource "google_project_iam_member" "extract_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.extract.email}"
}

# ---------- Droits : enrichissement ----------
resource "google_storage_bucket_iam_member" "enrich_read_raw" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.enrich.email}"
}

resource "google_storage_bucket_iam_member" "enrich_write" {
  bucket = google_storage_bucket.enriched.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.enrich.email}"
}

# ---------- Droits : dbt ----------
# Aucun droit d'écriture au niveau du projet : dbt ne doit pas pouvoir
# modifier le brut. Il devient propriétaire des datasets qu'il crée
# (analytics en dev, pr_<n> en CI) ; les autres sont accordés un par un.
resource "google_project_iam_member" "dbt_user" {
  project = var.project_id
  role    = "roles/bigquery.user" # jobs, read sessions, création de datasets ; aucun accès aux données
  member  = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_raw_viewer" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataViewer" # lit la source, sans pouvoir l'écrire
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_meta_editor" {
  dataset_id = google_bigquery_dataset.meta.dataset_id
  role       = "roles/bigquery.dataEditor" # post-hook du snapshot (MERGE dans meta.state_snapshot)
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_layer_editor" {
  for_each = google_bigquery_dataset.dbt_layer

  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataEditor" # tables et vues des modèles de la couche
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_storage_bucket_iam_member" "dbt_raw_read" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer" # lecture de la table externe raw.france_travail_offers_ext
  member = "serviceAccount:${google_service_account.dbt.email}"
}

# En CI, l'action d'authentification fournit déjà l'identité sa-dbt, et le
# profil dbt (impersonate_service_account) demande en plus à impersonner
# sa-dbt : il lui faut donc ce droit sur lui-même. Aucun privilège nouveau,
# il ne peut créer que ses propres jetons.
resource "google_service_account_iam_member" "dbt_self_impersonate" {
  service_account_id = google_service_account.dbt.name
  role               = "roles/iam.serviceAccountTokenCreator" # profil dbt impersonné depuis sa-dbt en CI
  member             = "serviceAccount:${google_service_account.dbt.email}"
}

# ---------- Impersonation depuis ton compte (pas de clé JSON) ----------
resource "google_service_account_iam_member" "me_impersonate" {
  for_each = {
    extract = google_service_account.extract.name
    dbt     = google_service_account.dbt.name
    enrich  = google_service_account.enrich.name
  }

  service_account_id = each.value
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.user_email}"
}
