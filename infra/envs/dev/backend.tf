terraform {
  backend "gcs" {
    bucket = "jobboard-dev-3b375b-tfstate"
    prefix = "platform"
  }
}
