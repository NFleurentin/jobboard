---
paths:
  - "transformation/**"
  - "loading/**"
globs:
  - "transformation/**"
  - "loading/**"
---

# Règles BigQuery

Ces règles couvrent l'usage de BigQuery : datasets, données brutes, coût, conception des tables et commandes à risque. La modélisation est dans `dbt.md`, la création des datasets et des droits dans `terraform_gcp.md`.

## Projets et datasets

| Contexte | Projet | Datasets des modèles dbt |
|---|---|---|
| prod | projet de prod | un dataset par couche, selon le `+schema` de `dbt_project.yml` (`staging`, `intermediate`, `marts`) |
| dev | projet de dev | un seul dataset, `analytics` |
| CI | projet de dev | un seul dataset, `pr_<numéro>` |

- Cette logique est portée par la macro `generate_schema_name`, et uniquement par elle. Aucun modèle ne force son dataset.
- Pourquoi : en prod, la séparation par couche permet de donner des droits par dataset. En dev et en CI, un dataset unique se nettoie et se reconstruit d'un seul geste.
- Conséquence : les droits par couche ne peuvent pas être validés en dev. Un changement de droits ou de `+schema` se vérifie à la lecture du plan Terraform et du SQL compilé pour le target `prod`.
- Les consommateurs ne lisent que `marts`. Les datasets permanents (`raw`, et en prod `staging`, `intermediate`, `marts`, `snapshots`) sont créés par Terraform. En dev et en CI, `sa-dbt` crée son dataset unique et en devient propriétaire.

## Données brutes

- Les tables de `raw` sont des tables externes nommées `<source>_<entite>_ext` (`france_travail_offers_ext`), déclarées dans Terraform, sur `gs://<project_id>-raw/<source>/<entite>/ingested_at=<horodatage>/` : rien n'est chargé, le brut n'existe que dans GCS, pendant la rétention du bucket.
- Partitionnement Hive : la clé `ingested_at` (`STRING`, tirée du nom du dossier) est la seule colonne qui élague, et `require_partition_filter` l'impose. Chaque run est un instantané complet, et une même offre figure dans plusieurs runs.
- Le cache de résultats ne voit pas les fichiers ajoutés dans GCS : ne lire que des runs terminés (`_SUCCESS`), donc figés.
- Schéma fixe, déclaré dans Terraform (`autodetect` désactivé) : des colonnes techniques et une colonne `_raw` (`STRING`) qui contient la réponse de l'API telle quelle. Une évolution de l'API ne casse donc pas le chargement ; un nouveau champ s'ajoute dans le staging.
- `_raw` est la colonne la plus coûteuse du projet : lire un seul de ses champs avec `JSON_VALUE` facture la chaîne entière. Elle n'est lue que par le snapshot et le staging, sur la partition des versions ouvertes du snapshot et le mois en cours. Aucune requête ne la parcourt sur tout l'historique.
- Toute lecture de `raw` filtre sur la clé Hive `ingested_at`, jamais sur `_ingested_at` (rejeté par `require_partition_filter`). Le dry run annonce 0 octet sur une table externe : le volume réel se lit dans les statistiques du job.

## Coût

- Toujours estimer avant d'exécuter : `bq query --dry_run`.
- Sur un `MERGE` vers une table partitionnée, le dry run ne donne qu'une borne haute, sans élagage. Les octets réels se lisent après coup dans `INFORMATION_SCHEMA.JOBS` (`total_bytes_processed`).
- `LIMIT` ne réduit pas le coût. Pour regarder des données, utiliser `bq head`, gratuit.
- Filtrer sur la colonne de partition avec une valeur constante ou un paramètre : un filtre calculé par une sous-requête ou à travers une fonction empêche l'élagage.
- `maximum_bytes_billed` est fixé dans `profiles.yml` et se passe aussi à `bq query` pour toute requête manuelle.
- Suivi des coûts : `INFORMATION_SCHEMA.JOBS` de la région.

## Conception des tables

- `require_partition_filter` sur les grandes tables.
- Types : `TIMESTAMP` en UTC pour les instants, `DATE` pour les jours, `NUMERIC` pour les montants (jamais `FLOAT64`).
- Descriptions alimentées depuis dbt (`persist_docs`).
- Expiration sur tout ce qui est temporaire : tables de CI, tables de travail.

## Différences avec Oracle

Ces points guident les explications, et évitent de transposer des réflexes qui ne s'appliquent pas.

- Pas d'index : la performance vient du partitionnement, du clustering et du nombre de colonnes lues.
- Les contraintes de clé primaire et étrangère sont déclaratives et non vérifiées. L'intégrité est garantie par les tests dbt.
- Pas de transaction longue ni de traitement ligne à ligne : tout se pense en opérations ensemblistes, et les `UPDATE` et `DELETE` unitaires fréquents sont un contresens.
- Le clustering trie physiquement les données, il ne se comporte pas comme un index : son bénéfice dépend du volume et n'apparaît pas toujours dans le dry run.
- Le time travel permet de relire une table telle qu'elle était quelques jours plus tôt (`FOR SYSTEM_TIME AS OF`), comme une requête flashback, mais sur une durée limitée.

## Droits et données

- Droits au niveau du dataset, pas du projet. Au niveau du projet, `sa-dbt` n'a que `bigquery.user` (requêtes, création de dataset) : il lit `raw` sans pouvoir l'écrire. Aucun utilisateur n'écrit en prod ; en dev, on agit par impersonation de `sa-dbt`, pour tester avec les droits réels du pipeline.
- Le dépôt est public : ne jamais versionner de données réelles, d'export ou de résultat de requête.

## Garde-fous pour l'agent

Avant toute commande : afficher le projet actif et vérifier qu'il s'agit du projet de dev.

Autorisé sans confirmation, sur dev : `bq ls`, `bq show`, `bq head`, `bq query --dry_run`.

Demander une confirmation explicite avant, sur dev :

- toute requête exécutée, en indiquant les octets annoncés par le dry run ;
- `bq load`, `bq cp`, `bq mk`, `bq update`, `bq extract` ;
- tout ordre `DROP`, `TRUNCATE`, `DELETE`, `UPDATE` ou `MERGE` lancé hors de dbt, et `bq rm`.

Interdit :

- toute commande d'écriture ou toute requête sur le projet de prod depuis le poste local ;
- créer à la main un dataset permanent, ou modifier des droits avec `bq` ou `gcloud` : cela passe par Terraform ;
- exécuter une requête sans dry run préalable, ou sans `maximum_bytes_billed` ;
- écrire dans le dataset des données brutes.
