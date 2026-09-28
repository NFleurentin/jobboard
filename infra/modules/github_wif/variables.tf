variable "project_id" {
  type = string
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
  type    = string
  default = "github"
}
