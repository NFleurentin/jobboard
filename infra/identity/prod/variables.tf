variable "project_id" {
  type        = string
  description = "ID du projet GCP de l'environnement"
}

variable "region" {
  type        = string
  description = "Région GCP par défaut du provider"
  default     = "europe-west1"
}

variable "github_repository" {
  type        = string
  description = "OWNER/REPO"
}
