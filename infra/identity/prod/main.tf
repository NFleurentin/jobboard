provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

module "github_wif" {
  source            = "../../modules/github_wif"
  project_id        = var.project_id
  github_repository = var.github_repository

  sa_environment = {
  deployer = "prod"          # déploiements, avec approbation manuelle
  dbt      = "prod"
  extract  = "prod-collect"  # collecte planifiée, sans approbation
}
}

output "github_variables" {
  value = {
    GCP_PROJECT_ID = var.project_id
    WIF_PROVIDER   = module.github_wif.workload_identity_provider
    service_accounts = module.github_wif.service_accounts
  }
}
