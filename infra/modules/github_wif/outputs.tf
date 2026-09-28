output "workload_identity_provider" {
  description = "Valeur de la variable GitHub WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_accounts" {
  description = "E-mails à copier dans les variables GitHub"
  value       = local.sa_emails
}
