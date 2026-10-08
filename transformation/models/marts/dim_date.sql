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

WITH spine AS (

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

dates AS (

    SELECT CAST(date_day AS DATE) AS date_day
    FROM spine

    -- Garde-fou, désormais redondant en temps normal puisque start_date
    -- borne déjà la plage côté date_spine — gardé par prudence (coût nul).
    {% if is_incremental() %}
        where cast(date_day as date) > (select max(date_day) from {{ this }})
    {% endif %}
)

SELECT
    date_day,
    EXTRACT(YEAR FROM date_day) AS year,
    EXTRACT(QUARTER FROM date_day) AS quarter,
    EXTRACT(MONTH FROM date_day) AS month,
    format_date('%Y-%m', date_day) AS year_month,
    [
        'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
        'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ][offset(EXTRACT(MONTH FROM date_day) - 1)] AS month_name,
    EXTRACT(ISOYEAR FROM date_day) AS iso_year,
    EXTRACT(ISOWEEK FROM date_day) AS iso_week,
    -- dayofweek BigQuery : 1 = dimanche. Converti en ISO : 1 = lundi.
    mod(EXTRACT(DAYOFWEEK FROM date_day) + 5, 7) + 1 AS day_of_week,
    [
        'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
    ][offset(mod(EXTRACT(DAYOFWEEK FROM date_day) + 5, 7))] AS day_name,
    EXTRACT(DAYOFWEEK FROM date_day) IN (1, 7) AS is_weekend
FROM dates
