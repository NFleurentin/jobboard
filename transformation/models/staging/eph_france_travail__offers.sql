-- Éphémère : seul modèle du projet autorisé à appeler source() directement.
-- Inliné dans la requête du snapshot à chaque run, donc "dbt snapshot"
-- fonctionne seul, sans étape préalable pour créer une vue physique.
-- Pour inspecter son contenu en debug : `dbt show --select
-- eph_france_travail__offers --vars '{ingested_at: <run>}'`.
--
-- Volontairement minimal, pas de nettoyage/typage ici : juste ce qu'il
-- faut au snapshot (clé, payload brut, signal de changement). Le vrai
-- travail de staging (extraction des champs) est fait après le snapshot,
-- dans stg_france_travail_offers.
--
-- Le run traité est fourni par la var ingested_at (format du dossier GCS,
-- ex. 20261008T050000Z), obligatoire : sans elle, la compilation échoue.
-- Elle est choisie par loading/load.py (issue #85), qui enchaîne les runs
-- terminés dans l'ordre et contrôle leur volume avant le snapshot. Le
-- filtre porte sur ingested_at, clé de partition Hive de la table externe,
-- et non sur _ingested_at, colonne des fichiers qui n'élague rien.
--
-- Le filtre est un "=" volontaire, pas un ">" : hard_deletes:invalidate a
-- besoin d'un instant précis (un seul run) pour comparer correctement les
-- clés présentes/absentes. Le rattrapage de plusieurs runs en retard se
-- fait en rejouant le snapshot une fois par run (boucle de load.py), pas
-- en élargissant ce filtre.

{{ config(materialized='ephemeral') }}

WITH source AS (

    SELECT * FROM {{ source('raw', 'france_travail_offers_ext') }}
    WHERE ingested_at = '{{ var("ingested_at") }}'

),

deduplicated AS (

    SELECT *
    FROM source
    QUALIFY row_number() OVER (
        PARTITION BY id
        ORDER BY _extracted_at DESC
    ) = 1

)

SELECT
    id AS offer_id,
    dateactualisation AS updated_at,
    _raw,
    _extracted_at,
    _ingested_at

FROM deduplicated
