variable "project_id" {
  type        = string
  description = "ID du projet GCP surveillé et plafonné"
}

variable "billing_account" {
  type        = string
  description = "ID du compte de facturation (XXXXXX-XXXXXX-XXXXXX), jamais versionné"
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "billing_account doit avoir la forme XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "monthly_budget" {
  type        = number
  description = "Budget mensuel du projet, en unités de la devise du compte de facturation"

  validation {
    condition     = var.monthly_budget > 0 && floor(var.monthly_budget) == var.monthly_budget
    error_message = "monthly_budget doit être un entier strictement positif."
  }
}

variable "query_usage_per_day_mib" {
  type        = number
  description = "Quota BigQuery QueryUsagePerDay : octets facturés par jour pour le projet, en Mio"

  validation {
    condition     = var.query_usage_per_day_mib > 0 && floor(var.query_usage_per_day_mib) == var.query_usage_per_day_mib
    error_message = "query_usage_per_day_mib doit être un entier strictement positif."
  }
}
