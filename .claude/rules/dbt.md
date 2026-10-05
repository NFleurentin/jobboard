---
paths:
  - "dbt/**"
globs:
  - "dbt/**"
---

# Règles dbt

Ces règles couvrent la transformation des données avec dbt sur BigQuery : couches, nommage, tests, matérialisations, environnements et commandes à risque. Le style SQL est défini par `.sqlfluff`, qui fait foi, et appliqué par `dbt format` et `dbt lint` (moteur Fusion).

## Périmètre

- dbt transforme des données déjà chargées dans BigQuery. Il ne fait ni extraction ni chargement (Meltano), ni gestion des datasets permanents et des droits (Terraform).
- Seule exception : les datasets `pr_<numéro>` créés par dbt en CI, à supprimer à la fermeture de la PR.

## Structure

```text
dbt_project.yml          # configuration par couche et vars
profiles.yml             # targets dev, ci, prod, sans aucun secret
packages.yml
.sqlfluff
macros/
snapshots/
models/
├── staging/
│   ├── _<source>__sources.yml
│   ├── _<source>__models.yml
│   └── stg_<source>__<entite>.sql
├── intermediate/
└── marts/
```

## Couches

Les dépendances vont dans un seul sens : `raw`, puis snapshot, puis staging, puis intermediate, puis marts.

- **snapshot** : un snapshot par table brute. Il réduit les instantanés quotidiens à une ligne par offre et par version, et conserve `_raw` sans l'interpréter.
- **staging** : un modèle par snapshot, sans jointure ni agrégation. Uniquement l'extraction des champs de `_raw`, du renommage, du typage et du nettoyage.
- Chaque source n'est appelée par `source()` que dans un seul modèle. Tous les autres passent par `ref()`.
- **intermediate** : les étapes de logique métier (jointures, règles de gestion, calculs). Ces modèles ne sont pas exposés aux consommateurs.
- **marts** : les modèles exposés, un par entité ou processus métier. Un mart ne contient pas de logique complexe : elle est préparée en intermediate.
- Aucune référence en dur à un projet, un dataset ou une table : toujours `ref()` ou `source()`. C'est ce qui permet à dbt de construire le graphe et de changer d'environnement.
- Aucune valeur en dur dans les requêtes (seuils, dates, listes de codes) : les déclarer en `vars` dans `dbt_project.yml`.

## Nommage

- Fichiers YAML : préfixe `_` et double underscore, un couple sources et models par source dans chaque répertoire.
- Modèles de staging : `stg_<source>__<entite>`, entité au pluriel. Le double underscore sépare la source de l'entité.
- Le préfixe `eph_` est réservé aux rares modèles `ephemeral` créés pour un besoin particulier. Leur raison d'être est expliquée dans leur description.
- Modèles intermediate : `int_<entite>` pour le modèle qui consolide une entité (`int_offers`), `int_<entite>__<action>` pour une étape (`int_offers__deduplicated`). Marts : `fct_<processus>` pour les faits, `dim_<entite>` pour les dimensions.
- Colonnes en `snake_case` et en anglais. Clé primaire `<entite>_id`, booléens `is_` ou `has_`, horodatages `_at` (en UTC), dates `_date`.
- Une même notion porte le même nom dans tous les modèles. Le renommage se fait une fois, en staging.
- Descriptions des modèles et des colonnes en français.

## Style SQL et Jinja

- Un modèle s'écrit en CTE : d'abord une CTE par `ref()` ou `source()`, puis les CTE de logique, puis un `select` final simple.
- Liste de colonnes explicite dans les marts, pas de `select *` vers une table exposée : un ajout de colonne en amont ne doit pas modifier un mart en silence.
- Jinja au minimum : le SQL compilé doit rester lisible. Créer une macro quand une logique se répète au moins trois fois, pas avant, et la documenter.
- `dbt format` puis `dbt lint` passent sans erreur avant chaque commit.

## Tests et documentation

- Chaque modèle a une description et une clé primaire testée (`unique` et `not_null`).
- Clés étrangères testées avec `relationships`, colonnes à valeurs énumérées avec `accepted_values`.
- Chaque source déclare sa fraîcheur attendue (`freshness`).
- Dans les marts, toutes les colonnes sont décrites, et un contrat (`contract: enforced`) fige leurs noms et leurs types.
- Une logique métier non triviale est couverte par un test unitaire, avec des données d'exemple.
- Un test en `severity: warn` porte un commentaire qui justifie pourquoi il n'est pas bloquant.

## Matérialisations et coût

Le coût des requêtes est le premier critère de choix d'une matérialisation. Sur BigQuery en facturation à la demande, ce coût dépend des octets lus, pas du nombre de lignes écrites ni du temps de calcul.

- staging : `incremental` quand il extrait les champs de `_raw` depuis un snapshot, pour ne traiter que les lignes nouvelles ou modifiées depuis le dernier run. `view` sinon.
- Un filtre incrémental ne réduit les octets lus que si la table lue est partitionnée ou clusterisée sur la colonne filtrée. Sinon, la colonne `_raw` du snapshot est relue en entier à chaque run : le vérifier par un dry run.
- intermediate : `view` ou `ephemeral`. marts : `table` ou `incremental`.
- Privilégier `incremental` dès qu'il évite de relire des données déjà traitées. Il s'accompagne toujours de `partition_by`, d'un filtre sur la partition côté source et côté cible, et d'un `on_schema_change` explicite.
- Un modèle incrémental n'est pas moins cher par nature : il relit sa propre table pour trouver son point de reprise, et un `merge` sans filtre de partition scanne toute la cible. Comparer les octets lus des deux approches par un dry run avant de choisir.
- Ne sélectionner que les colonnes utiles : le stockage est en colonnes, chaque colonne lue est facturée.
- Un modèle lu par plusieurs modèles en aval est matérialisé en `table` : en `view` ou en `ephemeral`, son calcul est refait et refacturé à chaque lecture.
- Partitionner et clusteriser les grandes tables selon les filtres réellement utilisés par les consommateurs.
- En dev, limiter le volume traité : `--select` ciblé et filtre sur une période récente.
- `maximum_bytes_billed` est le filet de sécurité contre une requête qui scanne trop : c'est un signal à comprendre, pas un obstacle à lever.

## Snapshots

- Un snapshot historise une source modifiable (SCD type 2). Il porte sur la donnée brute, pas sur un modèle transformé.
- Le snapshot des offres a deux rôles : suivre les évolutions d'une offre, et détecter sa clôture. Une offre absente de la dernière extraction est considérée comme close.
- La détection de clôture suppose une extraction complète. Après une extraction partielle, toutes les offres manquantes seraient marquées closes à tort, puis rouvertes au run suivant. Un test de volume sur la source bloque donc le snapshot quand la dernière partition est anormalement petite.
- Elle suppose aussi un périmètre de recherche constant : retirer ou modifier un critère de `search_queries` dans Meltano fait passer pour closes les offres qui sortent du périmètre.
- La date de clôture est déduite, pas fournie par la source : c'est la date du premier run où l'offre est absente. La colonne et sa description le disent explicitement.
- Une offre close peut réapparaître : les modèles en aval gèrent ce cas au lieu de supposer qu'une clôture est définitive.
- Sa requête ne lit qu'une seule partition `_ingested_at` de la table brute (le prochain jour à traiter), et retourne une seule ligne par clé. Une clé en double fait échouer la fusion ou fausse l'historique.
- La détection de changement porte sur une colonne courte (date de mise à jour fournie par la source, ou empreinte de `_raw`), pas sur `_raw` lui-même : la comparaison relit cette colonne dans tout le snapshot à chaque run.
- L'historique d'un snapshot est irremplaçable : il ne peut pas être reconstruit à partir de la source.

## Environnements

- Trois targets : `dev` (par défaut), `ci` (dataset `pr_<numéro>`), `prod` (exécuté uniquement par la CI).
- Authentification par `oauth` avec impersonation du service account `sa-dbt`. Aucune clé, aucun secret dans `profiles.yml`.
- Le projet GCP vient de `GCP_PROJECT_ID`, et les targets `dev` et `prod` écrivent dans un dataset de même nom. Le target ne suffit donc pas à protéger la production : c'est la valeur de `GCP_PROJECT_ID` qui décide où dbt écrit.

## Paquets et versions

- Version fixée pour chaque paquet dans `packages.yml`. `package-lock.yml` est versionné.
- dbt change de moteur et de spécification YAML entre versions majeures. Vérifier la version installée (`dbt --version`) et la documentation correspondante avant de proposer une syntaxe, et ne jamais changer de version majeure sans PR dédiée.

## Garde-fous pour Claude

Autorisé sans confirmation : `dbt --version`, `dbt deps`, `dbt parse`, `dbt compile`, `dbt ls`, `dbt format`, `dbt lint`.

Avant toute commande qui exécute des requêtes : afficher `GCP_PROJECT_ID` et vérifier qu'il désigne le projet de dev.

Pour tout nouveau modèle et tout changement de matérialisation : estimer les octets lus par un dry run et les indiquer, avec l'alternative écartée.

Demander une confirmation explicite avant :

- `dbt build`, `dbt run`, `dbt test`, `dbt seed`, `dbt snapshot`, `dbt show` sur dev, toujours avec un `--select` ciblé ;
- `--full-refresh` sur un modèle incrémental ;
- `dbt run-operation` ;
- un changement de matérialisation, de partitionnement ou de stratégie incrémentale ;
- le renommage ou la suppression d'un modèle ou d'une colonne dans les marts : c'est un changement cassant ;
- l'ajout ou la mise à jour d'un paquet.

Interdit :

- toute commande avec `--target prod`, ou avec un `GCP_PROJECT_ID` de production, depuis le poste local ;
- `--full-refresh` sur un snapshot, ou la suppression d'une table de snapshot ;
- lancer `dbt snapshot` après une extraction en échec ou incomplète ;
- augmenter ou retirer `maximum_bytes_billed` ;
- supprimer un test, l'affaiblir ou le passer en `warn` pour obtenir un build vert ;
- écrire un nom de projet, de dataset ou un secret en dur.

Si un modèle ou un test échoue : lire le SQL compilé sous `target/`, expliquer la cause, puis proposer un correctif. Pour un test en échec, déterminer d'abord si c'est la donnée ou le modèle qui est en faute.
