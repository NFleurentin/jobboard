---
paths:
  - "infra/**"
globs:
  - "infra/**"
---

# Règles Terraform

Ces règles couvrent l'infrastructure GCP décrite avec Terraform : organisation du code, state, conventions, sécurité et commandes à risque. Le déploiement par la CI est décrit dans `github_actions.md`.

## Périmètre

- Terraform gère projets et APIs, datasets BigQuery, buckets, service accounts, IAM et Workload Identity Federation.
- dbt gère le contenu des datasets. Ne jamais déclarer dans Terraform une table ou une vue produite par dbt, sinon les deux outils se disputent le même objet.
- Toute ressource créée à la main dans la console est soit importée dans Terraform, soit supprimée.

## Organisation du code

| Dossier | Rôle | Prefix de state |
|---|---|---|
| `infra/bootstrap/bootstrap.sh` | Projets, facturation, APIs, bucket tfstate (gcloud, rejouable) | — |
| `infra/modules/data_platform` | Buckets `raw`/`enriched`/`meltano-state`, datasets `raw` et `meta` (avec `meta.state_snapshot`), SA `sa-extract`/`sa-dbt`/`sa-enrich`, IAM | — |
| `infra/modules/github_wif` | Pool WIF, `sa-deployer`, liaison service account ↔ GitHub Environment | — |
| `infra/envs/<env>` | Instancie `data_platform` | `platform` |
| `infra/identity/<env>` | Instancie `github_wif` | `identity` |

- `identity/` est séparé de `envs/` volontairement : la CI ne peut pas modifier sa propre porte d'entrée, et détruire la plateforme dev ne supprime pas le pool WIF. Ne pas fusionner les deux states.
- Un répertoire par environnement plutôt que des workspaces : l'environnement visé est visible dans le chemin.
- Le code de `envs/dev` et `envs/prod` reste identique. Les différences passent par `var.env` dans le module (ex. rétention du brut 7 j / 30 j) ou par `terraform.tfvars`.
- Créer un module seulement quand un même ensemble de ressources est utilisé au moins deux fois.
- Une API GCP nouvelle s'ajoute dans la liste `APIS` de `bootstrap.sh`.

## Commandes

```bash
export TF_VAR_user_email="<compte Google>"       # jamais commité
gcloud auth application-default set-quota-project jobboard-dev-3b375b
cd infra/envs/dev && terraform init && terraform plan
```

## State et versions

- Backend distant sur `gs://<projet>-tfstate` (créé par `bootstrap.sh`), un state par environnement. Le state contient des valeurs sensibles en clair.
- Ne jamais modifier le state à la main. Pour renommer ou adopter une ressource, utiliser les blocs `moved` et `import` dans le code : ils sont relus en PR et visibles dans le plan.
- Versions minimales : Terraform 1.6, provider google 6.0, fixées avec `~>`. `.terraform.lock.hcl` est versionné. Une montée de version de provider fait l'objet d'une PR dédiée.

## Conventions de code

- Noms Terraform en `snake_case`, sans répéter le type de la ressource : `google_bigquery_dataset.raw`, pas `google_bigquery_dataset.raw_dataset`.
- L'environnement est porté par le projet GCP (`<projet>-<env>-<suffixe>`) : les ressources ne le répètent pas dans leur nom.
- Noms GCP en `kebab-case` (`sa-extract`), sauf les datasets BigQuery en `snake_case`. Buckets nommés `<project_id>-<usage>`.
- Chaque variable a un `type`, une `description`, et une `validation` quand les valeurs sont limitées. Chaque output a une `description`.
- Aucun identifiant en dur (projet, région, email) : variables ou `locals`.
- Labels `env` et `managed_by = "terraform"` sur toutes les ressources qui les acceptent.
- `terraform fmt -recursive` et `terraform validate` passent avant chaque commit.

## Sécurité

- Aucun secret dans les `.tf`, une valeur par défaut ou un `.tfvars` versionné (`*.tfvars.local` n'est jamais commité). Pas de Secret Manager (voir le README).
- Le dépôt est public : ni identifiant du compte de facturation ni adresse email personnelle versionnés.
- IAM au moindre privilège : pas de `owner` ni `editor`, des rôles prédéfinis ciblés au niveau le plus bas (dataset ou bucket). Chaque rôle porte un commentaire sur sa ligne pour dire pourquoi il est nécessaire.
- Uniquement `google_*_iam_member`. Les variantes `_iam_policy` et `_iam_binding` sont autoritaires : elles suppriment les droits existants qu'elles ne déclarent pas, et peuvent couper l'accès à un projet.
- Aucune `google_service_account_key`. L'accès humain passe par `roles/iam.serviceAccountTokenCreator` sur `var.user_email` (impersonation).
- Mapping service account → GitHub Environment dans `identity/<env>/main.tf` (`sa_environment`) : en prod, `extract` est lié à `prod-collect` (sans approbation), `deployer` et `dbt` à `prod` (approbation manuelle).
- Le dev est jetable : `force_destroy` et `delete_contents_on_destroy` y sont activés par `var.env`, et désactivés en prod. `prevent_destroy` n'accepte pas de variable : dans un module partagé, il bloquerait aussi la destruction du dev. La prod repose donc sur l'absence d'apply local, sur la lecture du plan et, pour les tables déclarées dans Terraform, sur `deletion_protection` activé hors dev.
- `deletion_protection` n'agit que dans Terraform (destroy ou remplacement) : il ne bloque ni `bq rm` ni un `DROP TABLE`. Pour remplacer volontairement une table protégée, désactiver la protection dans un premier apply, puis appliquer le changement.

## Plan

- `-/+` ou "must be replaced" sur une ressource qui porte des données, c'est une perte de données : toujours identifier l'attribut qui force le remplacement.
- Un plan qui annonce plus de changements que le diff révèle une dérive ou un effet de bord : s'arrêter et comprendre avant d'appliquer.
- Appliquer uniquement un plan enregistré (`terraform plan -out=tfplan` puis `terraform apply tfplan`).

## Garde-fous pour l'agent

Autorisé sans confirmation : `terraform fmt`, `terraform validate`, `terraform plan` sur dev, `terraform state list`, `terraform providers`.

Après chaque plan : résumer en français ce qui sera créé, modifié et détruit, en signalant les remplacements, les changements d'IAM et les ressources qui génèrent un coût. Une modification dans `identity/` peut couper l'accès de la CI : la signaler comme telle.

Demander une confirmation explicite avant :

- `terraform init`, en particulier avec `-upgrade` ou `-migrate-state` ;
- `terraform apply` sur dev, toujours à partir d'un plan enregistré et relu ;
- l'ajout d'une ressource payante ou d'une nouvelle API activée ;
- tout changement d'IAM, de backend ou de version de provider ;
- l'ajout d'un bloc `moved`, `import` ou `removed`.

Interdit :

- `terraform apply` ou `terraform plan` avec les identifiants de production depuis le poste local ;
- `terraform destroy` et `-auto-approve` ;
- `-target`, qui applique une partie du graphe et laisse le state incohérent avec le code ;
- `terraform state mv`, `rm`, `push`, `terraform import` en ligne de commande, `terraform force-unlock` ;
- afficher le state brut ou des valeurs sensibles : `terraform state pull`, `terraform show -json`, `terraform output -json` ou `-raw` ;
- retirer un `prevent_destroy` ou affaiblir une règle de sécurité pour faire passer un plan.

Si un plan ou un apply échoue : expliquer l'erreur et sa cause avant de proposer un correctif. Ne pas relancer en modifiant le code à l'aveugle.
