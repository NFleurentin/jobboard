provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    env        = "dev"
    managed_by = "terraform"
  }
}

module "github_wif" {
  source            = "../../modules/github_wif"
  project_id        = var.project_id
  github_repository = var.github_repository

  sa_environment = {
    deployer = "dev"
    dbt      = "dev"
    extract  = "dev"
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
