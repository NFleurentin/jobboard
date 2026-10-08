# AGENTS.md

Pipeline ELT d'offres d'emploi (API France Travail → GCS → BigQuery → dbt), pour analyser le marché et suivre une recherche d'emploi personnelle. Le [README.md](README.md) fait référence pour l'architecture, l'avancement et surtout la table « Choix techniques et compromis » : la consulter avant de proposer une alternative déjà écartée.

## Organisation

| Dossier | Contenu | Détails |
|---|---|---|
| `infra/` | Terraform (bootstrap, modules, `envs/`, `identity/`) | [terraform_gcp.md](.continue/rules/terraform_gcp.md) |
| `extraction/` | Projet Meltano + tap Singer maison | [meltano.md](.continue/rules/meltano.md) |
| `loading/` | `load.py` : runs terminés → snapshot dbt (garde-fou de volume, `dbt snapshot`, `dbt build`) | ci-dessous |
| `transformation/` | Transformations BigQuery (dbt Fusion) | [dbt.md](.continue/rules/dbt.md) |
| `enrichment/`, `oracle/`, `orchestration/` | Vides (`.gitkeep`), à venir | |
| `.github/workflows/` | Collecte quotidienne en prod, test WIF | [github_actions.md](.continue/rules/github_actions.md) |

## Environnements

- Deux projets GCP : `jobboard-dev-3b375b` et `jobboard-prod-3b375b`, région unique `europe-west1`. Les ressources sont nommées `<projet>-raw`, `<projet>-enriched`, `<projet>-meltano-state`, `<projet>-tfstate`.
- Travailler en **dev**. L'agent ne lance **jamais** de commande visant la prod depuis le poste local (`terraform plan`/`apply` dans `envs/prod` ou `identity/prod`, `run.sh`/`load.py` ou dbt avec le projet de prod) : la prod passe par la CI. Les opérations qui n'ont pas de CI (`bootstrap.sh`, `identity/prod`) sont lancées à la main par le propriétaire du dépôt.
- Sur dev, toute commande qui écrit ou peut coûter (`run.sh`, `load.py`, `terraform apply`, `dbt build`/`snapshot`, requête `bq`) demande une confirmation explicite ; le détail par outil est dans les règles.
- Le pipeline de prod tourne chaque jour à 05:00 UTC via [extraction-france-travail.yml](.github/workflows/extraction-france-travail.yml) (« Pipeline France Travail ») : job `extract` dans le GitHub Environment `prod-collect` (`sa-extract`), puis job `load` dans `prod-load` (`sa-dbt`), lancé même si la collecte échoue pour rattraper les runs en attente. Un lancement manuel (`gh workflow run extraction-france-travail.yml --ref <branche> -f environment=dev`) exécute le pipeline en dev depuis n'importe quelle branche, pour valider une modification du workflow avant le merge ; `-f load_only=true` saute la collecte.

## Exécution d'un run (extraction + chargement)

`INGESTED_AT` est l'identifiant unique du run : il est généré **une seule fois** par l'appelant de `run.sh`, qui l'utilise pour le chemin GCS et pour `_ingested_at`. Ne jamais le recalculer dans un script. `load.py` n'en dépend pas : il retrouve lui-même les runs terminés (`_SUCCESS`) qui restent à snapshoter.

```bash
export MELTANO_ENVIRONMENT=dev
export GCP_PROJECT_ID=jobboard-dev-3b375b
export INGESTED_AT=$(date -u +%Y%m%dT%H%M%SZ)
export TAP_FRANCETRAVAIL_CLIENT_ID=... TAP_FRANCETRAVAIL_CLIENT_SECRET=...
(cd extraction && ./run.sh) && (cd loading && uv run load.py)
```

`run.sh` et `load.py` sont les seuls points d'entrée, appelés tels quels en local, en CI et plus tard par Airflow : y mettre la logique, pas dans le YAML des workflows.

## Sécurité et données

- **Aucune clé JSON de service account**, jamais. En local : impersonation (`sa-extract`, `sa-dbt`, `sa-enrich`). En CI : Workload Identity Federation.
- Un service account par usage (moindre privilège) : un nouveau besoin de droits va sur le compte concerné, pas sur un compte plus large.
- Secrets (`TAP_FRANCETRAVAIL_*`) dans les GitHub Environments ou en variables d'environnement locales, jamais dans le dépôt.
- Les coordonnées de contact (`contact_*`, `agency_*`) existent dans le brut et en staging, mais ne doivent jamais dépasser la couche staging (exclues dès `int_offers`).

## Règles par outil

- Les règles sont dans [.continue/rules/](.continue/rules/), lu nativement par Continue. `.claude/rules` est un lien symbolique vers ce dossier, et `CLAUDE.md` se limite à importer ce fichier : Claude Code et Continue lisent les mêmes fichiers.
- `git.md` et `github.md` sont toujours chargées. Les autres, dont `github_actions.md` pour `.github/`, ne le sont que lorsqu'un fichier de leur périmètre est en jeu : chaque règle à périmètre porte la même liste sous deux clés, `paths:` (Claude Code) et `globs:` (Continue), à garder identiques.
- Une règle ne contient que ce qui est propre à ce dépôt, s'écarte de la convention de l'outil ou sert de garde-fou : les conventions courantes, que les modèles connaissent, n'y sont pas recopiées. Chaque règle est injectée dans le contexte, et un modèle local en a peu. Ce fichier ne garde que le transverse : ne pas y recopier une règle.

## Conventions

- Documentation, commentaires de code, docstrings et README **en français** ; identifiants (variables, fonctions, colonnes) en anglais.
- Une décision de conception nouvelle ou modifiée se reporte dans la table « Choix techniques et compromis » du README, et la liste « Avancement » se met à jour en même temps que le code.
- Pas de CI de test pour l'instant : valider localement (`dbt parse`, `terraform plan`, run en dev) avant de proposer une PR.
