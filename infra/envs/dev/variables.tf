variable "project_id" {
  type        = string
  description = "ID du projet GCP de l'environnement"
}

variable "region" {
  type        = string
  description = "Région GCP par défaut du provider et des ressources de la plateforme"
  default     = "europe-west1"
}

variable "user_email" {
  type        = string
  description = "Fournir via TF_VAR_user_email, ne jamais le commiter"
}
