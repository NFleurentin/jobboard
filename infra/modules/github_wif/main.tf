locals {
  environments = distinct(values(var.sa_environment))
  env_list     = join(", ", [for e in local.environments : "'${e}'"])

  # Seuls sont acceptés : CE dépôt ET un job déclarant l'un de ces GitHub Environments
  # ET, si allowed_ref est renseigné, un job lancé depuis cette référence Git
  ref_condition = var.allowed_ref == null ? "" : " && assertion.ref == '${var.allowed_ref}'"
  condition     = "assertion.repository == '${var.github_repository}' && assertion.environment in [${local.env_list}]${local.ref_condition}"

  sa_emails = {
    deployer = google_service_account.deployer.email
    dbt      = "sa-dbt@${var.project_id}.iam.gserviceaccount.com"
    extract  = "sa-extract@${var.project_id}.iam.gserviceaccount.com"
  }

  sa_ids = {
    deployer = google_service_account.deployer.name
    dbt      = "projects/${var.project_id}/serviceAccounts/sa-dbt@${var.project_id}.iam.gserviceaccount.com"
    extract  = "projects/${var.project_id}/serviceAccounts/sa-extract@${var.project_id}.iam.gserviceaccount.com"
  }

  deployer_roles = toset([
    "roles/storage.admin",                     # buckets, y compris le bucket de state
    "roles/bigquery.dataOwner",                # datasets et leur IAM
    "roles/iam.serviceAccountAdmin",           # créer les service accounts et leur IAM
    "roles/resourcemanager.projectIamAdmin",   # IAM au niveau du projet
    "roles/serviceusage.serviceUsageConsumer", # user_project_override du provider
  ])
}

# ---------- Pool et provider ----------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }

  # Sans cette condition, n'importe quel dépôt GitHub pourrait s'authentifier
  attribute_condition = local.condition

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ---------- Service account de déploiement (Terraform) ----------
resource "google_service_account" "deployer" {
  account_id   = "sa-deployer"
  display_name = "Déploiement Terraform (CI)"
}

resource "google_project_iam_member" "deployer" {
  for_each = local.deployer_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

# ---------- Qui peut utiliser quel service account ----------
resource "google_service_account_iam_member" "wif" {
  for_each = var.sa_environment

  service_account_id = local.sa_ids[each.key]
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${each.value}"
}
