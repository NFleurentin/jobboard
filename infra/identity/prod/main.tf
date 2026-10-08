provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    env        = "prod"
    managed_by = "terraform"
  }
}

module "github_wif" {
  source            = "../../modules/github_wif"
  project_id        = var.project_id
  github_repository = var.github_repository
  allowed_ref       = "refs/heads/main" # défense en plus de la règle de branche des GitHub Environments

  sa_environment = {
    deployer = "prod"         # déploiements, avec approbation manuelle
    dbt      = "prod-load"    # chargement quotidien (loading/load.py), sans approbation
    extract  = "prod-collect" # collecte planifiée, sans approbation
  }
}

output "github_variables" {
  description = "Valeurs à reporter dans les variables du GitHub Environment."
  value = {
    GCP_PROJECT_ID   = var.project_id
    WIF_PROVIDER     = module.github_wif.workload_identity_provider
    service_accounts = module.github_wif.service_accounts
  }
}
