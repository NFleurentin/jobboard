---
paths:
  - "dbt/**"
  - "loading/**"
---

# Règles BigQuery

Ces règles couvrent l'usage de BigQuery : organisation des projets et des datasets, coût, conception des tables, droits et commandes à risque. Les règles de modélisation sont dans `dbt.md`, la création des datasets et des droits dans `terraform_gcp.md`.

## Projets et datasets

Deux projets GCP distincts, un pour la production et un pour le développement. Tout est dans la région `europe-west1` : BigQuery ne sait pas joindre des données de régions différentes.

| Contexte | Projet | Datasets des modèles dbt |
|---|---|---|
| prod | projet de prod | un dataset par couche, selon le `+schema` de `dbt_project.yml` (`staging`, `intermediate`, `marts`) |
| dev | projet de dev | un seul dataset, `analytics` |
| CI | projet de dev | un seul dataset, `pr_<numéro>` |

- Cette logique est portée par la macro `generate_schema_name`, et uniquement par elle. Aucun modèle ne force son dataset.
- Pourquoi : en prod, la séparation par couche permet de donner des droits par dataset. En dev et en CI, un dataset unique se nettoie et se reconstruit d'un seul geste.
- Conséquence : les droits par couche ne peuvent pas être validés en dev. Un changement de droits ou de `+schema` se vérifie à la lecture du plan Terraform et du SQL compilé pour le target `prod`.
- Les données brutes vivent dans le dataset `raw` de chaque projet, que dbt lit par `source()` sans jamais y écrire. Voir "Données brutes".
- Les consommateurs ne lisent que `marts`.
- Les datasets permanents sont créés par Terraform. Les datasets `pr_<numéro>` sont créés par dbt et supprimés à la fermeture de la PR.

## Données brutes

- Les tables de `raw` sont des tables natives nommées `<source>_<entite>` (`france_travail_offers`), chargées par `loading/load.sh` avec `bq load`, qui est gratuit.
- Les fichiers sources sont dans `gs://<project_id>-raw/<source>/<entite>/ingested_at=<horodatage>/`, un répertoire par run.
- Le chargement est en ajout seul, dans une table partitionnée par jour sur `_ingested_at`. Chaque run ajoute un instantané : une même offre figure dans plusieurs partitions, et c'est le snapshot dbt qui en tire une ligne par offre et par version.
- Recharger un run déjà chargé (même `INGESTED_AT`) ajoute les mêmes lignes une seconde fois. Le snapshot doit rester correct dans ce cas : sa requête dédoublonne sur la clé.
- Le schéma d'une table brute est fixe : des colonnes techniques (dont `_ingested_at`) et une colonne `_raw` qui contient la réponse de l'API telle quelle. Il est versionné sous `loading/schemas/<source>/` et n'a pas vocation à changer.
- Une évolution de l'API ne casse donc pas le chargement et ne perd aucune donnée. L'extraction et le typage des champs se font dans le staging, où un nouveau champ est ajouté quand il devient utile.
- `_raw` est de type `STRING`. Ses champs s'extraient avec `JSON_VALUE`, `JSON_QUERY` et leurs variantes pour les tableaux. Lire un seul champ facture la chaîne entière de chaque ligne parcourue.
- `_raw` est donc la colonne la plus coûteuse du projet. Elle n'est lue que deux fois : par le snapshot, sur une seule partition de `raw` (le prochain jour à traiter), puis par le staging, sur les lignes nouvelles du snapshot. Aucun autre modèle ni aucune requête d'exploration ne la parcourt sur tout l'historique.
- Toute lecture de `raw` filtre sur `_ingested_at`.

## Coût

En facturation à la demande, une requête coûte ce qu'elle lit : les octets des colonnes référencées, dans les partitions parcourues. Le nombre de lignes retournées, le temps de calcul et les écritures ne comptent pas.

- Toujours estimer avant d'exécuter : `bq query --dry_run` affiche les octets qui seraient lus, sans rien facturer.
- `LIMIT` ne réduit pas le coût : la table est lue avant la limite. Pour regarder des données, utiliser l'aperçu de table (`bq head`), qui est gratuit.
- Pas de `select *` sur une table large : lister les colonnes utiles.
- Filtrer sur la colonne de partition avec une valeur constante ou un paramètre. Un filtre calculé par une sous-requête ou appliqué à travers une fonction empêche l'élagage des partitions.
- `maximum_bytes_billed` est fixé dans `profiles.yml` et se passe aussi à `bq query` pour toute requête manuelle. Une requête qui dépasse le plafond échoue sans être facturée.
- Le suivi des coûts se fait dans `INFORMATION_SCHEMA.JOBS` de la région, par utilisateur, par requête et par jour.

## Conception des tables

- Partitionner toute table appelée à grossir, sur la colonne de date la plus utilisée dans les filtres. Partition au jour par défaut, au mois si le volume quotidien est faible.
- Clusteriser sur les colonnes de filtre et de jointure les plus fréquentes, de la moins à la plus sélective, quatre au maximum.
- Activer `require_partition_filter` sur les grandes tables : une requête sans filtre de partition est refusée au lieu de tout scanner.
- Pas de tables suffixées par date (`events_20260101`) : une table partitionnée les remplace.
- Types : `TIMESTAMP` en UTC pour les instants, `DATE` pour les jours, `NUMERIC` pour les montants (jamais `FLOAT64`), `STRUCT` et `ARRAY` pour les données imbriquées quand leur structure est stable.
- Chaque table et chaque colonne exposée porte une description, alimentée depuis dbt (`persist_docs`).
- Poser une expiration sur tout ce qui est temporaire : tables de CI, tables de travail.

## Différences avec Oracle

Ces points guident les explications, et évitent de transposer des réflexes qui ne s'appliquent pas.

- Pas d'index : la performance vient du partitionnement, du clustering et du nombre de colonnes lues.
- Les contraintes de clé primaire et étrangère sont déclaratives et non vérifiées. L'intégrité est garantie par les tests dbt.
- Pas de transaction longue ni de traitement ligne à ligne : tout se pense en opérations ensemblistes, et les `UPDATE` et `DELETE` unitaires fréquents sont un contresens.
- Le clustering trie physiquement les données, il ne se comporte pas comme un index : son bénéfice dépend du volume et n'apparaît pas toujours dans le dry run.
- Le time travel permet de relire une table telle qu'elle était quelques jours plus tôt (`FOR SYSTEM_TIME AS OF`), comme une requête flashback, mais sur une durée limitée.

## Droits et données

- Droits attribués au niveau du dataset, jamais au niveau du projet quand un niveau plus fin existe.
- Un service account par usage : `sa-extract` écrit les données brutes, `sa-dbt` lit le brut et écrit les datasets de modèles.
- Aucun utilisateur n'écrit en prod. En dev, on agit par impersonation de `sa-dbt`, pour tester avec les droits réels du pipeline.
- Les offres peuvent contenir des coordonnées de contact : ne pas les propager dans les marts sans besoin identifié.
- Le dépôt est public : ne jamais versionner de données réelles, d'export ou de résultat de requête.

## Garde-fous pour Claude

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
- écrire dans le dataset des données brutes ;
- enregistrer des données réelles dans le dépôt.
