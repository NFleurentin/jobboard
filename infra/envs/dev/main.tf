provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

module "platform" {
  source     = "../../modules/data_platform"
  project_id = var.project_id
  env        = "dev"
  location   = var.region
  user_email = var.user_email
}

output "platform" {
  value = {
    buckets          = module.platform.buckets
    service_accounts = module.platform.service_accounts
  }
}
