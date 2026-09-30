-- Éphémère : seul modèle du projet autorisé à appeler source() directement.
-- Inliné dans la requête du snapshot à chaque run, donc "dbt snapshot"
-- fonctionne seul, sans étape préalable pour créer une vue physique.
-- Pour inspecter son contenu en debug : `dbt show --select
-- eph_france_travail_offers`.
--
-- Volontairement minimal, pas de nettoyage/typage ici : juste ce qu'il
-- faut au snapshot (clé, payload brut, signal de changement). Le vrai
-- travail de staging (extraction des champs) est fait après le snapshot,
-- dans stg_france_travail_offers.
--
-- Le filtre est un "=" volontaire, pas un ">" : hard_deletes:invalidate a
-- besoin d'un instant précis (un seul jour) pour comparer correctement les
-- clés présentes/absentes. Le rattrapage de plusieurs jours en retard se
-- fait en rejouant ce modèle et le snapshot plusieurs fois de suite (boucle
-- côté orchestration), pas en élargissant ce filtre.

{{ config(materialized='ephemeral') }}

with source as (

    select * from {{ source('raw', 'france_travail_offers') }}
    where _ingested_at = {{ target_ingested_at_france_travail_offers() }}

),

deduplicated as (

    select *
    from source
    qualify row_number() over (
        partition by id
        order by _extracted_at desc
    ) = 1

)

select
    id as offer_id,
    dateActualisation as updated_at,
    _raw as _raw,
    _extracted_at as _extracted_at,
    _ingested_at as _ingested_at

from deduplicated
