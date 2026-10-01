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

with source as (

    select * from {{ ref('int_offers') }}

),

filtered as (

    {% if is_incremental() %}

    select * from source
    where _valid_from > (
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

final as (

    select
        *,

        -- Clés de date, pour jointure directe avec dim_date.
        date(created_at) as created_date,
        date(updated_at) as updated_date,
        date(_valid_from) as valid_from_date,
        date(_valid_to) as valid_to_date

    from filtered

)

select * from final