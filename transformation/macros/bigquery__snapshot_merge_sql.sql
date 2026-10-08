{#
    Surcharge de la macro interne de dbt qui écrit le MERGE final d'un
    snapshot (issue #80). Copie de default__snapshot_merge_sql de Fusion
    2.0.6, à un déplacement près : le filtre sur les versions ouvertes
    passe du WHEN MATCHED au ON.

    Dans un WHEN MATCHED, ce filtre n'élague aucune partition : le MERGE
    lisait toute la table, _raw compris, alors que le snapshot est
    partitionné sur dbt_valid_to (issue #78). Dans le ON, c'est un
    prédicat constant sur la colonne de partition, et BigQuery ne lit
    que la partition NULL des versions ouvertes.

    Résultat inchangé : une ligne update ou delete porte le dbt_scd_id
    d'une version ouverte, et une ligne insert un dbt_scd_id nouveau
    (hash de la clé et de snapshot_get_time, soit du run traité). Seule
    exception, le rejeu d'un run déjà traité dont la version a été
    fermée depuis : l'insert, qui retrouvait la version fermée et était
    ignoré, devient un doublon de dbt_scd_id. Ce rejeu fausse déjà les
    bornes et loading/load.py l'empêche.

    Code interne de dbt : à comparer avec la macro d'origine à chaque
    mise à jour de Fusion.
#}
{% macro bigquery__snapshot_merge_sql(target, source, insert_cols) -%}
    {%- set insert_cols_csv = insert_cols | join(', ') -%}
    {%- set columns = config.get("snapshot_table_column_names") or get_snapshot_table_column_names() -%}
    merge into {{ target.render() }} as DBT_INTERNAL_DEST
    using {{ source }} as DBT_INTERNAL_SOURCE
    on DBT_INTERNAL_SOURCE.{{ columns.dbt_scd_id }} = DBT_INTERNAL_DEST.{{ columns.dbt_scd_id }}
     {% if config.get("dbt_valid_to_current") %}
	{% set source_unique_key = ("DBT_INTERNAL_DEST." ~ columns.dbt_valid_to) | trim %}
	{% set target_unique_key = config.get('dbt_valid_to_current') | trim %}
	and ({{ equals(source_unique_key, target_unique_key) }} or {{ source_unique_key }} is null)
     {% else %}
       and DBT_INTERNAL_DEST.{{ columns.dbt_valid_to }} is null
     {% endif %}

    when matched
     and DBT_INTERNAL_SOURCE.dbt_change_type in ('update', 'delete')
        then update
        set {{ columns.dbt_valid_to }} = DBT_INTERNAL_SOURCE.{{ columns.dbt_valid_to }}

    when not matched
     and DBT_INTERNAL_SOURCE.dbt_change_type = 'insert'
        then insert ({{ insert_cols_csv }})
        values ({{ insert_cols_csv }})
{% endmacro %}
