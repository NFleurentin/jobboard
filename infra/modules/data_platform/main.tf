locals {
  raw_retention_days = var.env == "dev" ? 7 : 30
}

# ---------- Buckets ----------
resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-raw"
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.env == "dev"

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
  force_destroy               = var.env == "dev"
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
# Seul "raw" est géré ici. dbt crée lui-même ses datasets (staging, marts, dbt_<user>, pr_<n>).
resource "google_bigquery_dataset" "raw" {
  dataset_id                 = "raw"
  location                   = var.location
  delete_contents_on_destroy = var.env == "dev"
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
# Au niveau du projet : dbt doit pouvoir créer ses propres datasets.
resource "google_project_iam_member" "dbt_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_project_iam_member" "dbt_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_project_iam_member" "dbt_readsession" {
  project = var.project_id
  role    = "roles/bigquery.readSessionUser"
  member  = "serviceAccount:${google_service_account.dbt.email}"
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
