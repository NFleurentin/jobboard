{#
    Contrôle le dataset BigQuery de destination de chaque modèle.
 
    - En prod : respecte le +schema: déclaré dans dbt_project.yml
      (staging, marts, ...), pour une vraie séparation par couche.
    - En dev et en CI : ignore le +schema: et regroupe tout dans le
      dataset du profil actif (analytics en dev, pr_<n> en CI), pour
      garder un seul dataset à nettoyer/reconstruire en cas de test.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
  {%- if target.name == 'prod' and custom_schema_name is not none -%}
    {{ custom_schema_name | trim }}
  {%- else -%}
    {{ target.schema }}
  {%- endif -%}
{%- endmacro %}
