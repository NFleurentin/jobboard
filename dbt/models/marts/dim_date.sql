-- Incrémental : chaque run ajoute seulement les jours qui manquent en fin
-- de plage. Les lignes existantes ne sont jamais réécrites.
-- Modifier le calcul d'une colonne exige un --full-refresh.
--
-- start_date dynamique, décidé explicitement par is_incremental() (pas de
-- variable intermédiaire qui pourrait laisser croire qu'elle s'évalue
-- avant que la table existe) : au premier run (table absente), plage
-- complète depuis 2015 ; ensuite, uniquement le lendemain du dernier jour
-- connu — date_spine() ne génère alors que les jours réellement manquants.

{{
    config(
        materialized='incremental',
        on_schema_change='fail'
    )
}}

with spine as (

    {% if is_incremental() %}

    {{ dbt_utils.date_spine(
        datepart='day',
        start_date="(select coalesce(date_add(max(date_day), interval 1 day), cast('2015-01-01' as date)) from " ~ this ~ ")",
        end_date="date_add(current_date(), interval 1 year)"
    ) }}

    {% else %}

    {{ dbt_utils.date_spine(
        datepart='day',
        start_date="cast('2015-01-01' as date)",
        end_date="date_add(current_date(), interval 1 year)"
    ) }}

    {% endif %}

),

dates as (

    select cast(date_day as date) as date_day
    from spine

    -- Garde-fou, désormais redondant en temps normal puisque start_date
    -- borne déjà la plage côté date_spine — gardé par prudence (coût nul).
    {% if is_incremental() %}
        where cast(date_day as date) > (select max(date_day) from {{ this }})
    {% endif %}
)

select
    date_day,
    extract(year from date_day) as year,
    extract(quarter from date_day) as quarter,
    extract(month from date_day) as month,
    format_date('%Y-%m', date_day) as year_month,
    [
        'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
        'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ][offset(extract(month from date_day) - 1)] as month_name,
    extract(isoyear from date_day) as iso_year,
    extract(isoweek from date_day) as iso_week,
    -- dayofweek BigQuery : 1 = dimanche. Converti en ISO : 1 = lundi.
    mod(extract(dayofweek from date_day) + 5, 7) + 1 as day_of_week,
    [
        'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
    ][offset(mod(extract(dayofweek from date_day) + 5, 7))] as day_name,
    extract(dayofweek from date_day) in (1, 7) as is_weekend
from dates
