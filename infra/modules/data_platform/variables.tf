variable "project_id" {
  type        = string
  description = "ID du projet GCP de l'environnement"
}

variable "env" {
  type        = string
  description = "dev ou prod"
}

variable "location" {
  type    = string
  default = "europe-west1"
}

variable "user_email" {
  type        = string
  description = "Ton compte Google, autorisé à impersonner les service accounts (fournir via TF_VAR_user_email)"
}
