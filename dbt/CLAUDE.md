# CLAUDE.md — dbt

Projet dbt sur BigQuery, exécuté avec le **moteur Fusion** (dbt 2.x, `+static_analysis: strict`). Toutes les commandes se lancent depuis `dbt/`, où se trouve `profiles.yml`.

## Commandes

```bash
export GCP_PROJECT_ID=jobboard-dev-3b375b      # requis par profiles.yml
dbt parse --profiles-dir .                     # validation rapide, sans requête BigQuery
dbt snapshot --select snap_france_travail__offers --profiles-dir .   # traite UN jour d'ingestion par appel
dbt build --select <selection> --profiles-dir .                       # toujours une sélection ciblée
dbt format -s <modele> --profiles-dir . && dbt lint -s <modele> --profiles-dir . --fix
```

- Le target `ci` (dataset `pr_<PR_NUMBER>`) existe dans `profiles.yml` mais n'est pas encore branché sur une CI.
- `maximum_bytes_billed` vaut 10 Go en dev et en ci.

## Flux et règles par couche

```
source raw.france_travail_offers
  → eph_france_travail__offers   (éphémère, filtre = sur UN _ingested_at, dédoublonne)
  → snap_france_travail__offers  (SCD2 timestamp sur updated_at, hard_deletes: invalidate)
  → stg_france_travail__offers   (incrémental merge, PARSE_JSON(_raw) + extraction des champs)
  → int_offers                   (schéma commun multi-source, offer_key, sans contact_*/agency_*)
  → fct_offers, dim_date         (marts)
```

- `raw.france_travail_offers` n'est lue que par `eph_france_travail__offers` (une source, un seul modèle). Le snapshot est déclaré en YAML et `relation:` n'accepte ni filtre ni SQL : c'est `eph_`, inliné dans la requête du snapshot, qui porte le filtre et le dédoublonnage.
- Le filtre de `eph_` est un `=` volontaire : `hard_deletes: invalidate` compare les offres présentes un jour donné. Ne pas l'élargir en `>` ; un retard se rattrape en rejouant `dbt snapshot` plusieurs fois (un jour par appel).
- Le jour traité vient de [target_ingested_at_france_travail_offers.sql](macros/target_ingested_at_france_travail_offers.sql), lu dans `meta.state_snapshot` (table gérée par Terraform, avancée par le post-hook du snapshot). Forcer un jour en debug : `--vars '{"target_ingested_at_france_travail_offers": "<timestamp>"}'`.
- `_raw` reste une chaîne jusqu'au snapshot inclus ; le `PARSE_JSON` se fait uniquement dans `stg_`.
- Incrémentaux de `stg_` et `fct_offers` : deux marqueurs combinés par `UNION DISTINCT`, `valid_from` pour les nouvelles versions et `valid_to` pour les fermetures. Ne pas simplifier en un seul marqueur, les fermetures seraient perdues.
- Grain de `stg_`, `int_offers` et `fct_offers` : une ligne par offre **et par version**. Clé unique : (`offer_id` ou `offer_key`, `_valid_from`).
- `int_offers` contient un CTE `unioned` prévu pour ajouter une deuxième source : y ajouter un `UNION ALL` plutôt que restructurer.

## Spécificités Fusion

- `dbt_utils.generate_surrogate_key` échoue sous Fusion sur BigQuery : clé faite main `to_hex(md5(COALESCE(...) || '-' || COALESCE(...)))`.
- Tests au format récent : `data_tests:` et paramètres sous `arguments:` (ex. `accepted_values`, `relationships`) ; la sévérité se règle sous `config:`.

## Style SQL

- Imposé par [.sqlfluff](.sqlfluff) et appliqué par `dbt format` / `dbt lint` : mots-clés en MAJUSCULES, fonctions et identifiants en minuscules, virgules en fin de ligne, 100 caractères max, indentation de 4 espaces, alias explicites.
- Modèle structuré en CTE successives à responsabilité unique (`source` → … → `final`), puis `SELECT * FROM final`.
- Commentaire d'en-tête en français expliquant le *pourquoi* (grain, incrémental, choix écartés), comme dans les modèles existants.
- Fichiers YAML hors staging : `_<couche>__models.yml`. Colonnes techniques préfixées par `_` (`_raw`, `_ingested_at`, `_valid_from`…).
