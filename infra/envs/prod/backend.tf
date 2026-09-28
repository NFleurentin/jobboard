terraform {
  backend "gcs" {
    bucket = "jobboard-prod-nf89-tfstate"
    prefix = "platform"
  }
}
