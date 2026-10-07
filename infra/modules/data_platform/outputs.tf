output "buckets" {
  description = "Noms des buckets GCS, par usage."
  value = {
    raw           = google_storage_bucket.raw.name
    enriched      = google_storage_bucket.enriched.name
    meltano_state = google_storage_bucket.meltano_state.name
  }
}

output "service_accounts" {
  description = "Emails des service accounts de la plateforme, par usage."
  value = {
    extract = google_service_account.extract.email
    dbt     = google_service_account.dbt.email
    enrich  = google_service_account.enrich.email
  }
}
