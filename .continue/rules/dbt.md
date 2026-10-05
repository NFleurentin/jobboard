---
paths:
  - "dbt/**"
globs:
  - "dbt/**"
---

# Règles dbt

Le projet suit le guide *How we structure our dbt projects* de dbt Labs (couches staging, intermediate et marts, nommage, une CTE par import puis une CTE `final`, `ref()` et `source()` partout). Seuls les écarts, les spécificités et les garde-fous sont listés ici. Il s'exécute avec le **moteur Fusion** (dbt 2.x, `+static_analysis: strict`). Le style SQL est défini par `.sqlfluff`, appliqué par `dbt format` et `dbt lint`. Le coût et la conception des tables BigQuery sont dans `bigquery.md`.

## Commandes

Toutes les commandes se lancent depuis `dbt/`, où se trouve `profiles.yml`.

```bash
export GCP_PROJECT_ID=jobboard-dev-3b375b      # requis par profiles.yml
dbt parse --profiles-dir .                     # validation rapide, sans requête BigQuery
dbt snapshot --select snap_france_travail__offers --profiles-dir .   # traite UN jour d'ingestion par appel
dbt build --select <selection> --profiles-dir .                       # toujours une sélection ciblée
dbt format -s <modele> --profiles-dir . && dbt lint -s <modele> --profiles-dir . --fix
```

## Couches

- Une couche **snapshot** s'intercale entre `raw` et staging : un snapshot par table brute, qui réduit les instantanés quotidiens à une ligne par offre et par version et conserve `_raw` sans l'interpréter.
- Staging : un modèle par snapshot, qui extrait les champs de `_raw`, renomme, type et nettoie.
- Aucune valeur en dur dans les requêtes (seuils, dates, listes de codes) : les déclarer en `vars` dans `dbt_project.yml`.

## Flux du projet

```text
source raw.france_travail_offers
  → eph_france_travail__offers   (éphémère, filtre = sur UN _ingested_at, dédoublonne)
  → snap_france_travail__offers  (SCD2 timestamp sur updated_at, hard_deletes: invalidate)
  → stg_france_travail__offers   (incrémental merge, PARSE_JSON(_raw) + extraction des champs)
  → int_offers                   (schéma commun multi-source, offer_key, sans contact_*/agency_*)
  → fct_offers, dim_date         (marts)
```

- `raw.france_travail_offers` n'est lue que par `eph_france_travail__offers`. Le snapshot est déclaré en YAML et `relation:` n'accepte ni filtre ni SQL : c'est `eph_`, inliné dans la requête du snapshot, qui porte le filtre et le dédoublonnage.
- Le filtre de `eph_` est un `=` volontaire : `hard_deletes: invalidate` compare les offres présentes un jour donné. Ne pas l'élargir en `>` ; un retard se rattrape en rejouant `dbt snapshot` plusieurs fois (un jour par appel).
- Le jour traité vient de la macro `dbt/macros/target_ingested_at_france_travail_offers.sql`, lu dans `meta.state_snapshot` (table gérée par Terraform, avancée par le post-hook du snapshot). Forcer un jour en debug : `--vars '{"target_ingested_at_france_travail_offers": "<timestamp>"}'`.
- `_raw` reste une chaîne jusqu'au snapshot inclus ; le `PARSE_JSON` se fait uniquement dans `stg_`.
- Incrémentaux de `stg_` et `fct_offers` : deux marqueurs combinés par `UNION DISTINCT`, `valid_from` pour les nouvelles versions et `valid_to` pour les fermetures. Ne pas simplifier en un seul marqueur, les fermetures seraient perdues.
- Grain de `stg_`, `int_offers` et `fct_offers` : une ligne par offre **et par version**. Clé unique : (`offer_id` ou `offer_key`, `_valid_from`).
- `int_offers` contient un CTE `unioned` prévu pour ajouter une deuxième source : y ajouter un `UNION ALL` plutôt que restructurer.

## Nommage

- Le préfixe `eph_` est réservé aux rares modèles `ephemeral` créés pour un besoin particulier, expliqué dans leur description.
- Intermediate : `int_<entite>` pour le modèle qui consolide une entité, `int_<entite>__<action>` pour une étape.
- Colonnes techniques préfixées par `_` (`_raw`, `_ingested_at`, `_valid_from`…). Horodatages `_at`, en UTC.
- Colonnes en anglais ; descriptions des modèles et des colonnes en français.

## Style et tests

- Liste de colonnes explicite dans la CTE `final` des marts : un ajout de colonne en amont ne doit pas modifier un mart en silence.
- Commentaire d'en-tête en français expliquant le *pourquoi* (grain, incrémental, choix écartés), comme dans les modèles existants.
- Créer une macro quand une logique se répète au moins trois fois, pas avant.
- Dans les marts, toutes les colonnes sont décrites, et un contrat (`contract: enforced`) fige leurs noms et leurs types.
- Chaque source déclare sa `freshness`. Une logique métier non triviale est couverte par un test unitaire.
- Un test en `severity: warn` porte un commentaire qui justifie pourquoi il n'est pas bloquant.
- `dbt format` puis `dbt lint` passent sans erreur avant chaque commit.

## Matérialisations

- staging : `incremental` quand il extrait les champs de `_raw` depuis un snapshot, `view` sinon. intermediate : `view` ou `ephemeral`. marts : `table` ou `incremental`.
- Un `incremental` s'accompagne toujours de `partition_by`, d'un filtre sur la partition côté source et côté cible, et d'un `on_schema_change` explicite.
- Il n'est pas moins cher par nature : il relit sa propre table pour trouver son point de reprise, et un `merge` sans filtre de partition scanne toute la cible. Comparer les deux approches par un dry run avant de choisir.
- Un modèle lu par plusieurs modèles en aval est matérialisé en `table` : en `view` ou en `ephemeral`, son calcul est refacturé à chaque lecture.
- `maximum_bytes_billed` (10 Go en dev et en ci) est un signal à comprendre, pas un obstacle à lever.

## Snapshots

- Le snapshot des offres a deux rôles : suivre les évolutions d'une offre, et détecter sa clôture. Une offre absente de la dernière extraction est considérée comme close.
- La détection de clôture suppose une extraction complète. Après une extraction partielle, toutes les offres manquantes seraient marquées closes à tort, puis rouvertes au run suivant. Un test de volume sur la source bloque donc le snapshot quand la dernière partition est anormalement petite.
- Elle suppose aussi un périmètre de recherche constant : retirer ou modifier un critère de `search_queries` dans Meltano fait passer pour closes les offres qui sortent du périmètre.
- La date de clôture est déduite, pas fournie par la source : c'est la date du premier run où l'offre est absente. La colonne et sa description le disent explicitement.
- Une offre close peut réapparaître : les modèles en aval gèrent ce cas au lieu de supposer qu'une clôture est définitive.
- Sa requête retourne une seule ligne par clé : une clé en double fait échouer la fusion ou fausse l'historique.
- La détection de changement porte sur une colonne courte (`updated_at`, ou une empreinte de `_raw`), pas sur `_raw` lui-même : la comparaison relit cette colonne dans tout le snapshot à chaque run.
- L'historique d'un snapshot est irremplaçable : il ne peut pas être reconstruit à partir de la source.

## Environnements

- Trois targets : `dev` (par défaut, dataset `analytics`), `ci` (dataset `pr_<numéro>`, déclaré mais pas encore branché sur une CI, supprimé à la fermeture de la PR), `prod` (exécuté uniquement par la CI).
- Authentification `oauth` avec impersonation de `sa-dbt`. Aucun secret dans `profiles.yml`.
- Le projet GCP vient de `GCP_PROJECT_ID`, et les targets `dev` et `prod` écrivent dans un dataset de même nom. Le target ne suffit donc pas à protéger la production : c'est la valeur de `GCP_PROJECT_ID` qui décide où dbt écrit.

## Paquets et Fusion

- Version fixée pour chaque paquet dans `packages.yml`. `package-lock.yml` est versionné.
- dbt change de moteur et de spécification YAML entre versions majeures. Vérifier la version installée (`dbt --version`) et la documentation correspondante avant de proposer une syntaxe. Pas de changement de version majeure sans PR dédiée.
- `dbt_utils.generate_surrogate_key` échoue sous Fusion sur BigQuery : clé faite main `to_hex(md5(COALESCE(...) || '-' || COALESCE(...)))`.
- Tests au format récent : `data_tests:` et paramètres sous `arguments:` (ex. `accepted_values`, `relationships`) ; la sévérité se règle sous `config:`.

## Garde-fous pour l'agent

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
