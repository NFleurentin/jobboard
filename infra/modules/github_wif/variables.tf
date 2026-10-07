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

variable "allowed_ref" {
  type        = string
  description = "Référence Git complète seule autorisée (ex. refs/heads/main) ; null n'impose aucune restriction de branche"
  default     = null

  validation {
    condition     = var.allowed_ref == null || startswith(coalesce(var.allowed_ref, "refs/"), "refs/")
    error_message = "allowed_ref doit être null ou une référence complète commençant par refs/ (ex. refs/heads/main)."
  }
}
