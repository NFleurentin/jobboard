---
paths:
  - "infra/**"
---

# Règles Terraform

Ces règles couvrent l'infrastructure GCP décrite avec Terraform : organisation du code, state, conventions, sécurité et commandes à risque. Le déploiement par la CI est décrit dans `github.md`.

## Périmètre

- Terraform gère l'infrastructure : projets et APIs activées, datasets BigQuery, buckets, service accounts, IAM, Workload Identity Federation.
- dbt gère le contenu des datasets : tables, vues, modèles. Ne jamais déclarer dans Terraform une table ou une vue produite par dbt, sinon les deux outils se disputent le même objet.
- Toute ressource créée à la main dans la console est une dette : soit elle est importée dans Terraform, soit elle est supprimée.

## Organisation du code

```text
infra/
├── bootstrap/        # bootstrap.sh : projets, APIs, bucket du state (gcloud)
├── modules/          # data_platform, github_wif : code partagé par dev et prod
├── envs/<env>/       # plateforme : un répertoire = un environnement = un state
└── identity/<env>/   # Workload Identity Federation et sa-deployer, state séparé
```

- Un répertoire par environnement plutôt que des workspaces : l'environnement visé est visible dans le chemin, et une erreur de sélection est impossible.
- Fichiers d'un répertoire d'environnement : `versions.tf` (versions de Terraform et des providers), `backend.tf`, `variables.tf`, `terraform.tfvars`, `main.tf` (appel du module). Dans un module, `main.tf`, `variables.tf` et `outputs.tf` ; découper `main.tf` par domaine (`bigquery.tf`, `iam.tf`, `storage.tf`) quand il devient difficile à relire.
- Créer un module seulement quand un même ensemble de ressources est utilisé au moins deux fois. Un module prématuré ajoute de l'indirection sans bénéfice.

## State

Le state est le fichier où Terraform mémorise la correspondance entre le code et les ressources réelles. Il contient des valeurs sensibles en clair.

- Backend distant sur un bucket GCS, jamais de state local ni versionné dans Git.
- Bucket du state : versioning activé (retour arrière possible), accès uniforme, non public, accès limité au strict nécessaire.
- Un state par environnement, pour qu'une erreur en dev ne puisse pas atteindre la production.
- Ne jamais modifier le state à la main. Pour renommer ou adopter une ressource, utiliser les blocs `moved` et `import` dans le code : ils sont relus en PR et visibles dans le plan, contrairement aux commandes `terraform state mv` et `terraform import`.

## Versions

- Fixer `required_version` et la version de chaque provider avec l'opérateur `~>`, qui accepte les correctifs mais pas les versions majeures.
- `.terraform.lock.hcl` est versionné : il garantit les mêmes binaires de providers pour tous et pour la CI.
- Une montée de version de provider fait l'objet d'une PR dédiée, avec lecture du changelog et du plan.

## Conventions de code

- Noms Terraform en `snake_case`, sans répéter le type de la ressource : `google_bigquery_dataset.raw`, pas `google_bigquery_dataset.raw_dataset`.
- Un projet GCP par environnement, nommé `<projet>-<env>-<suffixe>`. L'environnement est porté par le projet : les ressources ne le répètent pas dans leur nom.
- Noms des ressources GCP en `kebab-case` (`sa-extract`), sauf les datasets BigQuery, qui n'acceptent que le `snake_case`.
- Buckets nommés `<project_id>-<usage>` (`<project_id>-raw`, `<project_id>-meltano-state`) : un nom de bucket est unique au niveau mondial, le préfixe par projet évite les collisions.
- Chaque variable a un `type` et une `description`, et une `validation` quand les valeurs autorisées sont limitées. Chaque output a une `description`.
- Aucun identifiant en dur (projet, région, email) : passer par des variables ou des `locals`.
- Utiliser `for_each` pour créer plusieurs ressources à partir d'une collection. Avec `count`, supprimer un élément au milieu de la liste décale les index et provoque la destruction et la recréation des suivants. Réserver `count` au cas conditionnel (0 ou 1).
- Éviter `depends_on` : Terraform déduit l'ordre à partir des références entre ressources. Un `depends_on` signale souvent une référence manquante.
- Pas de provisioner (`local-exec`, `remote-exec`) : leur effet est hors du state, donc invisible dans le plan.
- Poser les labels `env` et `managed_by = "terraform"` sur toutes les ressources qui les acceptent.
- Le code passe `terraform fmt -recursive` et `terraform validate` avant chaque commit.

## Sécurité

- Aucun secret dans les fichiers `.tf`, dans une valeur par défaut de variable ou dans un `.tfvars` versionné. Les secrets vivent dans les GitHub Environments ou des variables d'environnement locales (pas de Secret Manager, voir le README).
- `sensitive = true` masque une valeur dans les sorties, mais elle reste en clair dans le state : ce n'est pas une protection suffisante.
- Le dépôt est public : ne pas versionner l'identifiant du compte de facturation ni d'adresses email personnelles. Les fournir par des variables non versionnées.
- IAM au moindre privilège : pas de rôles `owner` ou `editor`, mais des rôles prédéfinis ciblés, attribués au niveau le plus bas possible (dataset ou bucket plutôt que projet).
- Utiliser les ressources `google_*_iam_member`, qui ajoutent un droit. Les variantes `_iam_policy` et `_iam_binding` sont autoritaires : elles suppriment les droits existants qu'elles ne déclarent pas, et peuvent couper l'accès à un projet.
- Un service account par usage (Meltano, dbt, CI), jamais de compte partagé. Aucune clé de service account (`google_service_account_key`) : l'authentification passe par Workload Identity Federation.
- Le dev est jetable : `force_destroy` et `delete_contents_on_destroy` y sont activés par `var.env`, et désactivés en prod. `prevent_destroy` n'accepte pas de variable : dans un module partagé, il bloquerait aussi la destruction du dev. La prod repose donc sur l'absence d'apply local et sur la lecture du plan.

## Lire un plan

`terraform plan` compare le code, le state et la réalité, puis liste ce qu'un `apply` changerait. C'est la seule protection avant un changement réel.

- `+` création, `~` modification en place, `-` destruction.
- `-/+` ou "must be replaced" : destruction puis recréation. Sur une ressource qui porte des données, c'est une perte de données. Toujours identifier l'attribut qui force le remplacement.
- Un plan qui annonce plus de changements que ceux du diff révèle une dérive (modification manuelle) ou un effet de bord : s'arrêter et comprendre avant d'appliquer.
- Appliquer uniquement un plan enregistré (`terraform plan -out=tfplan` puis `terraform apply tfplan`), pour que ce qui est appliqué soit exactement ce qui a été relu.

## Garde-fous pour Claude

Autorisé sans confirmation : `terraform fmt`, `terraform validate`, `terraform plan` sur dev, `terraform state list`, `terraform providers`.

Après chaque plan : résumer en français ce qui sera créé, modifié et détruit, en signalant les remplacements, les changements d'IAM et les ressources qui génèrent un coût.

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
