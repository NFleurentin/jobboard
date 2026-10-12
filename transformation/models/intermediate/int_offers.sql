-- Intermediate : regroupe les offres de toutes les sources d'extraction
-- dans un schéma commun. Pas de nouveau nettoyage ici (déjà fait dans
-- stg_) : ce modèle mappe vers un schéma commun entre sources, et calcule
-- une clé de substitution stable.
--
-- Exclut volontairement : contact_*/agency_* (données personnelles, pas
-- utiles pour un rapport de marché) et les champs composites JSON bruts
-- (à réintroduire via des tables de pont dédiées si besoin, plus tard).

WITH france_travail AS (

    SELECT
        -- Clé de substitution faite main (plutôt que
        -- dbt_utils.generate_surrogate_key : son dispatch vers
        -- l'implémentation BigQuery échoue sous Fusion au moment de
        -- l'écriture). COALESCE sur chaque champ avant concaténation :
        -- si offer_id était un jour NULL, la clé ne devient pas NULL
        -- silencieusement.
        to_hex(md5(
            COALESCE(CAST('{{ var("france_travail_source_name") }}' AS STRING), '') || '-'
            || COALESCE(CAST(offer_id AS STRING), '')
        )) AS offer_key,
        '{{ var("france_travail_source_name") }}' AS source,
        offer_id AS source_offer_id,

        created_at,
        updated_at,

        title,
        description,

        company_name,
        company_description,
        company_url,

        work_location_label,
        work_location_city,
        work_location_department_code,
        work_location_postal_code,
        work_location_commune_code,
        work_location_latitude,
        work_location_longitude,

        rome_code,
        rome_label,
        appellation_label,
        naf_code,
        sector_code,
        sector_label,
        company_size_label,

        contract_type_code,
        contract_type_label_clean AS contract_type_label,
        contract_duration_value,
        contract_duration_unit,
        contract_nature,

        working_hours_min,
        working_hours_max,
        working_hours_periodicity,
        working_schedule_type,
        working_time_label,

        position_count,
        is_apprenticeship,

        experience_required_code,
        experience_label,

        qualification_code,
        qualification_label,

        salary_periodicity,
        salary_min,
        salary_max,

        is_disability_accessible,
        offer_is_adapted,
        employer_disability_committed,

        source_url,

        _valid_from,
        _valid_to

    FROM {{ ref('stg_france_travail__offers') }}

),

unioned AS (

    -- Pas d'UNION ALL utile pour l'instant (une seule source) : ce CTE
    -- existe déjà pour qu'ajouter une deuxième source se résume à un
    -- "union all select * from <nouvelle_source>" ici, sans rien
    -- restructurer ailleurs dans le fichier.
    SELECT * FROM france_travail

),

final AS (

    SELECT
        offer_key,
        source,
        source_offer_id,

        created_at,
        updated_at,

        title,
        description,

        company_name,
        company_description,
        company_url,

        work_location_label,
        work_location_city,
        work_location_department_code,
        work_location_postal_code,
        work_location_commune_code,
        work_location_latitude,
        work_location_longitude,

        rome_code,
        rome_label,
        appellation_label,
        naf_code,
        sector_code,
        sector_label,
        company_size_label,

        contract_type_code,
        contract_type_label,
        contract_duration_value,
        contract_duration_unit,
        contract_nature,

        working_hours_min,
        working_hours_max,
        working_hours_periodicity,
        working_schedule_type,
        working_time_label,

        position_count,
        is_apprenticeship,

        experience_required_code,
        experience_label,

        qualification_code,
        qualification_label,

        salary_periodicity,
        salary_min,
        salary_max,

        is_disability_accessible,
        offer_is_adapted,
        employer_disability_committed,

        source_url,

        _valid_from,
        _valid_to

    FROM unioned

)

SELECT * FROM final
