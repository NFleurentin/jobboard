variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "user_email" {
  type        = string
  description = "Fournir via TF_VAR_user_email, ne jamais le commiter"
}
