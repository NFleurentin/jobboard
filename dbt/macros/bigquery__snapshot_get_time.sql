{#
    Surcharge de la macro interne de dbt qui fournit l'heure d'un snapshot
    (issue #13). Avec strategy: check, elle date toutes les bornes :
    dbt_valid_from d'une nouvelle version, dbt_valid_to d'une version
    remplacée et d'une offre absente (hard_deletes: invalidate).

    Par défaut, cette heure est current_timestamp, soit l'heure d'exécution :
    en rattrapage de plusieurs jours, toutes les bornes porteraient la date
    du rattrapage. Pour le snapshot des offres France Travail, elle devient
    le jour d'ingestion traité : date de détection d'une version, ou premier
    run où l'offre est absente. Les autres snapshots éventuels gardent le
    comportement par défaut.

    Nommée bigquery__ pour être trouvée par adapter.dispatch('snapshot_get_time',
    'dbt'), appelé à la fois par snapshot_get_time() et par le contrôle de
    type get_snapshot_get_time_data_type().
#}
{% macro bigquery__snapshot_get_time() -%}
  {%- if model is defined and model.name == var('france_travail_offers_snapshot_name') -%}
    {{ target_ingested_at_france_travail_offers() }}
  {%- else -%}
    {{ current_timestamp() }}
  {%- endif -%}
{%- endmacro %}
