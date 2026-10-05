# CLAUDE.md

Pipeline ELT d'offres d'emploi (API France Travail → GCS → BigQuery → dbt), pour analyser le marché et suivre une recherche d'emploi personnelle. Le [README.md](README.md) fait référence pour l'architecture, l'avancement et surtout la table « Choix techniques et compromis » : la consulter avant de proposer une alternative déjà écartée.

## Organisation

| Dossier | Contenu | Détails |
|---|---|---|
| `infra/` | Terraform (bootstrap, modules, `envs/`, `identity/`) | [infra/CLAUDE.md](infra/CLAUDE.md) |
| `extraction/` | Projet Meltano + tap Singer maison | [extraction/CLAUDE.md](extraction/CLAUDE.md) |
| `loading/` | `load.sh` : GCS → `raw.france_travail_offers` (`bq load`, APPEND) | ci-dessous |
| `dbt/` | Transformations BigQuery (dbt Fusion) | [dbt/CLAUDE.md](dbt/CLAUDE.md) |
| `enrichment/`, `oracle/`, `orchestration/` | Vides (`.gitkeep`), à venir | |
| `.github/workflows/` | Collecte quotidienne en prod, test WIF | |

## Environnements

- Deux projets GCP : `jobboard-dev-3b375b` et `jobboard-prod-3b375b`, région unique `europe-west1`. Les ressources sont nommées `<projet>-raw`, `<projet>-enriched`, `<projet>-meltano-state`, `<projet>-tfstate`.
- Travailler en **dev**. Claude ne lance **jamais** de commande visant la prod depuis le poste local (`terraform plan`/`apply` dans `envs/prod` ou `identity/prod`, `run.sh`/`load.sh` ou dbt avec le projet de prod) : la prod passe par la CI. Les opérations qui n'ont pas de CI (`bootstrap.sh`, `identity/prod`) sont lancées à la main par le propriétaire du dépôt.
- Sur dev, toute commande qui écrit ou peut coûter (`run.sh`, `load.sh`, `terraform apply`, `dbt build`/`snapshot`, requête `bq`) demande une confirmation explicite ; le détail par outil est dans les règles.
- La collecte de prod tourne chaque jour à 05:00 UTC via [extraction-france-travail.yml](.github/workflows/extraction-france-travail.yml), dans le GitHub Environment `prod-collect`.

## Exécution d'un run (extraction + chargement)

`INGESTED_AT` est l'identifiant unique du run : il est généré **une seule fois** par l'appelant et partagé par `run.sh` et `load.sh`. Ne jamais le recalculer dans un script, sinon le chemin GCS relu diverge de celui écrit.

```bash
export MELTANO_ENVIRONMENT=dev
export GCP_PROJECT_ID=jobboard-dev-3b375b
export INGESTED_AT=$(date -u +%Y%m%dT%H%M%SZ)
export TAP_FRANCETRAVAIL_CLIENT_ID=... TAP_FRANCETRAVAIL_CLIENT_SECRET=...
(cd extraction && ./run.sh) && (cd loading && ./load.sh)
```

`run.sh` et `load.sh` sont les seuls points d'entrée, appelés tels quels en local, en CI et plus tard par Airflow : y mettre la logique, pas dans le YAML des workflows.

## Sécurité et données

- **Aucune clé JSON de service account**, jamais. En local : impersonation (`sa-extract`, `sa-dbt`, `sa-enrich`). En CI : Workload Identity Federation.
- Un service account par usage (moindre privilège) : un nouveau besoin de droits va sur le compte concerné, pas sur un compte plus large.
- Secrets (`TAP_FRANCETRAVAIL_*`) dans les GitHub Environments ou en variables d'environnement locales, jamais dans le dépôt.
- Les coordonnées de contact (`contact_*`, `agency_*`) existent dans le brut et en staging, mais ne doivent jamais dépasser la couche staging (exclues dès `int_offers`).

## Règles par outil

Les conventions par outil sont dans [.claude/rules/](.claude/rules/). `git.md` et `github.md` sont toujours chargées ; les autres ne le sont que lorsqu'un fichier de leur périmètre (`paths:`) est lu. Les CLAUDE.md ne gardent que ce qui est propre à ce dépôt : ne pas y recopier une règle.

## Conventions

- Documentation, commentaires de code, docstrings et README **en français** ; identifiants (variables, fonctions, colonnes) en anglais.
- Une décision de conception nouvelle ou modifiée se reporte dans la table « Choix techniques et compromis » du README, et la liste « Avancement » se met à jour en même temps que le code.
- Pas de CI de test pour l'instant : valider localement (`dbt parse`, `terraform plan`, run en dev) avant de proposer une PR.
