{#
    Renvoie le prochain jour de raw.france_travail_offers non encore traité
    par le snapshot (le plus ancien après le marqueur meta.state_snapshot),
    ou une date explicite si fournie via
    --vars '{"target_ingested_at_france_travail_offers": "..."}' (utile en
    debug).
    Spécifique à cette source : source() et le nom de pipeline sont en dur.
    Aucune coordination externe nécessaire : rejouer simplement
    "dbt snapshot" plusieurs fois de suite rattrape les jours manqués un par
    un, dans l'ordre.
#}
{% macro target_ingested_at_france_travail_offers() %}
  {%- set explicit = var('target_ingested_at_france_travail_offers', none) -%}
  {%- if explicit -%}
    timestamp('{{ explicit }}')
  {%- else -%}
    {%- if execute -%}
      {%- set query %}
        select coalesce(
          (select last_ingest
           from `{{ target.project }}.meta.state_snapshot`
           where name = '{{ var("france_travail_offers_snapshot_name") }}'),
          timestamp('1970-01-01')
        ) as last_ingest
      {%- endset -%}
      {%- set results = run_query(query) -%}
      {%- set last_ingest = results.columns[0].values()[0] -%}
    {%- else -%}
      {%- set last_ingest = '1970-01-01 00:00:00' -%}
    {%- endif -%}
    (
      select min(_ingested_at)
      from {{ source('raw', 'france_travail_offers') }}
      where _ingested_at > timestamp('{{ last_ingest }}')
    )
  {%- endif -%}
{% endmacro %}