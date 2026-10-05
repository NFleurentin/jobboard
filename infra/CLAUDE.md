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
gcloud auth application-default set-quota-project jobboard-dev-3b375b
cd infra/envs/dev && terraform init && terraform plan
```

- `plan` et `apply` se lancent sur dev uniquement. La prod (`envs/prod`, `identity/prod`) est appliquée à la main par le propriétaire du dépôt, jamais par Claude.
- Une modification dans `identity/` peut couper l'accès de la CI : la signaler comme telle.

## Règles

- Les différences entre environnements passent par `var.env` dans le module (ex. rétention du brut 7 j / 30 j, `force_destroy` et `delete_contents_on_destroy` seulement en dev) ou par `terraform.tfvars`. Le code de `envs/dev` et `envs/prod` reste identique.
- Mapping service account → GitHub Environment dans `identity/<env>/main.tf` (`sa_environment`) : en prod, `extract` est lié à `prod-collect` (sans approbation), `deployer` et `dbt` à `prod` (approbation manuelle).
- Chaque rôle IAM porte un commentaire sur sa ligne pour dire pourquoi il est nécessaire.
- L'accès humain passe par `roles/iam.serviceAccountTokenCreator` sur `var.user_email` (impersonation).
- `*.tfvars.local` n'est jamais commité.
- Une API GCP nouvelle s'ajoute dans la liste `APIS` de `bootstrap.sh`.
