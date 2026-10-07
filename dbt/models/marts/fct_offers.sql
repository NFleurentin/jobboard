-- Mart : une ligne par offre et par version (grain hérité du snapshot via
-- stg_ et int_offers). Incrémental, même logique à deux marqueurs
-- qu'avant (dbt_valid_from pour les nouvelles versions, dbt_valid_to pour
-- les fermetures), simplement repointée sur int_offers plutôt que
-- directement sur stg_, pour rester valable si une deuxième source est
-- ajoutée un jour.

{{
    config(
        materialized='incremental',
        unique_key=['offer_key', '_valid_from'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

WITH source AS (

    SELECT * FROM {{ ref('int_offers') }}

),

filtered AS (

    {% if is_incremental() %}

        selecT * from source
        where
            _valid_from > (
                select coalesce(max(_valid_from), timestamp('1970-01-01')) from {{ this }}
            )

        union distinct

        select * from source
        where _valid_to > (
            select coalesce(max(_valid_to), timestamp('1970-01-01'))
            from {{ this }}
            where _valid_to is not null
        )

    {% else %}

        select * from source

    {% endif %}

),

final AS (

    -- Liste explicite, figée par le contrat du YAML : une colonne ajoutée
    -- dans int_offers n'arrive dans le mart que si on l'ajoute ici et
    -- dans le contrat.
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
        _valid_to,

        -- Clés de date, pour jointure directe avec dim_date.
        date(created_at) AS created_date,
        date(updated_at) AS updated_date,
        date(_valid_from) AS valid_from_date,
        date(_valid_to) AS valid_to_date

    FROM filtered

)

SELECT *
FROM final
