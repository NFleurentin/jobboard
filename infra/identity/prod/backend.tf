terraform {
  backend "gcs" {
    bucket = "jobboard-prod-3b375b-tfstate"
    prefix = "identity"
  }
}
