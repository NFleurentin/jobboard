# CLAUDE.md — infra

Terraform (≥ 1.6, provider google ≥ 6.0), state distant dans `gs://<projet>-tfstate`.

## Structure

| Dossier | Rôle | Prefix de state |
|---|---|---|
| `bootstrap/bootstrap.sh` | Projets, facturation, APIs, bucket tfstate (gcloud, rejouable) | — |
| `modules/data_platform` | Buckets `raw`/`enriched`/`meltano-state`, datasets `raw` et `meta` (avec `meta.state_snapshot`), SA `sa-extract`/`sa-dbt`/`sa-enrich`, IAM | — |
| `modules/github_wif` | Pool WIF, `sa-deployer`, liaison service account ↔ GitHub Environment | — |
| `envs/<env>` | Instancie `data_platform` | `platform` |
| `identity/<env>` | Instancie `github_wif` | `identity` |

`identity/` est séparé de `envs/` volontairement : la CI ne peut pas modifier sa propre porte d'entrée, et détruire la plateforme dev ne supprime pas le pool WIF. Ne pas fusionner les deux states.

## Commandes

```bash
export TF_VAR_user_email="<compte Google>"       # jamais commité
gcloud auth application-default set-quota-project jobboard-<env>-3b375b   # à refaire à chaque changement d'env
cd infra/envs/<env> && terraform init && terraform plan
```

- Toujours `terraform plan` d'abord et montrer le résultat. `terraform apply` uniquement après confirmation explicite, et en dev avant la prod.
- Une modification dans `identity/` peut couper l'accès de la CI : la signaler comme telle.

## Règles

- Les différences entre environnements passent par `var.env` dans le module (ex. rétention du brut 7 j / 30 j, `force_destroy` et `delete_contents_on_destroy` seulement en dev) ou par `terraform.tfvars`. Le code de `envs/dev` et `envs/prod` reste identique.
- Mapping service account → GitHub Environment dans `identity/<env>/main.tf` (`sa_environment`) : en prod, `extract` est lié à `prod-collect` (sans approbation), `deployer` et `dbt` à `prod` (approbation manuelle).
- Moindre privilège : droits au niveau bucket ou dataset plutôt que projet quand c'est possible, un rôle commenté par ligne pour dire pourquoi il est nécessaire.
- Aucune ressource `google_service_account_key`. L'accès humain passe par `roles/iam.serviceAccountTokenCreator` sur `var.user_email`.
- Les fichiers `.terraform.lock.hcl` sont commités ; `*.tfstate` et `*.tfvars.local` ne le sont jamais.
- Une API GCP nouvelle s'ajoute dans la liste `APIS` de `bootstrap.sh`.
