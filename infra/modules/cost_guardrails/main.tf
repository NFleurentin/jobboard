data "google_project" "this" {
  project_id = var.project_id
}

# ---------- Alerte de budget ----------
# Prévient par e-mail les administrateurs du compte de facturation : un budget ne bloque aucune dépense.
resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = var.project_id

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }

  # Sans currency_code : la devise du compte de facturation
  amount {
    specified_amount {
      units = tostring(var.monthly_budget)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }

  # Prévision de fin de mois : alerte avant le dépassement
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }
}

# ---------- Quota quotidien BigQuery ----------
# Plafond des octets facturés par jour pour tout le projet, toutes identités confondues.
# Une fois atteint, les requêtes échouent jusqu'à la remise à zéro (minuit, heure du Pacifique).
resource "google_cloud_quotas_quota_preference" "query_usage_per_day" {
  parent   = "projects/${var.project_id}"
  name     = "bigquery_googleapis_com-QueryUsagePerDay"
  service  = "bigquery.googleapis.com"
  quota_id = "QueryUsagePerDay"

  quota_config {
    preferred_value = tostring(var.query_usage_per_day_mib)
  }

  # Baisse depuis la valeur par défaut (200 Tio) : refusée par l'API sans cette option
  ignore_safety_checks = "QUOTA_DECREASE_PERCENTAGE_TOO_HIGH"
  justification        = "Garde-fou de coût du projet jobboard"
}
