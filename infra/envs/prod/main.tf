locals {
  env = "prod"
}

provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    env        = local.env
    managed_by = "terraform"
  }
}

module "platform" {
  source     = "../../modules/data_platform"
  project_id = var.project_id
  env        = local.env
  location   = var.region
  user_email = var.user_email
}

output "platform" {
  description = "Buckets et service accounts créés par la plateforme."
  value = {
    buckets          = module.platform.buckets
    service_accounts = module.platform.service_accounts
  }
}
