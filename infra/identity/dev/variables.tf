variable "project_id" {
  type        = string
  description = "ID du projet GCP de l'environnement"
}

variable "region" {
  type        = string
  description = "Région GCP par défaut du provider"
  default     = "europe-west1"
}

variable "github_repository" {
  type        = string
  description = "OWNER/REPO"
}

variable "billing_account" {
  type        = string
  description = "ID du compte de facturation, fourni par TF_VAR_billing_account (jamais versionné)"
  sensitive   = true
}

variable "monthly_budget" {
  type        = number
  description = "Budget mensuel du projet, en unités de la devise du compte de facturation"
}

variable "query_usage_per_day_mib" {
  type        = number
  description = "Quota BigQuery QueryUsagePerDay du projet, en Mio"
}
