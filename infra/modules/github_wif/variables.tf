variable "project_id" {
  type        = string
  description = "ID du projet GCP qui héberge le pool WIF et les service accounts"
}

variable "github_repository" {
  type        = string
  description = "OWNER/REPO, exactement comme sur GitHub (sensible à la casse)"
}

variable "sa_environment" {
  type        = map(string)
  description = "Pour chaque service account (deployer, dbt, extract), le GitHub Environment autorisé à l'utiliser"
}

variable "pool_id" {
  type        = string
  description = "Identifiant du pool Workload Identity Federation"
  default     = "github"
}
