{#
    Renvoie, sous forme d'expression SQL timestamp('...'), le jour de
    raw.france_travail_offers à traiter par le snapshot :
    - par défaut, le plus ancien jour après le marqueur meta.state_snapshot ;
    - ou une date explicite fournie via
      --vars '{"target_ingested_at_france_travail_offers": "..."}' (debug).
    Rejouer "dbt snapshot" plusieurs fois de suite rattrape les jours manqués
    un par un, dans l'ordre.

    Garde-fous (issue #11) : hard_deletes: invalidate clôt toute offre absente
    de la source. La macro fait donc échouer le run, avant toute écriture,
    quand :
    - aucun jour n'est à traiter (marqueur déjà sur la dernière partition) ;
    - le jour ciblé n'a aucune ligne ;
    - son volume est inférieur à france_travail_offers_min_volume_ratio fois
      celui du jour de référence (le marqueur, ou le jour précédent en mode
      explicite). Contrôle ignoré sans jour de référence (premier run).
      Passer la var à 0 force le run après une baisse assumée (critère
      retiré de search_queries, par exemple).
    Appelée plusieurs fois par run (eph_france_travail__offers,
    bigquery__snapshot_get_time pour dater les clôtures, post_hook du
    snapshot) : le marqueur n'avance qu'à la fin, tous les appels ciblent le
    même jour.
    Spécifique à cette source : source() et le nom de pipeline sont en dur.
#}
{% macro target_ingested_at_france_travail_offers() %}
  {#- Au parse : aucune requête, SQL factice mais valide. -#}
  {%- if not execute -%}
    {{ return("timestamp('1970-01-01')") }}
  {%- endif -%}

  {%- set source_relation = source('raw', 'france_travail_offers') -%}
  {%- set explicit = var('target_ingested_at_france_travail_offers', none) -%}

  {#- 1. Jour ciblé et jour de référence (1970 = pas de référence) -#}
  {%- if explicit -%}
    {%- set query -%}
      select
        timestamp('{{ explicit }}') as target_ingested_at,
        coalesce(
          (select max(_ingested_at)
           from {{ source_relation }}
           where _ingested_at < timestamp('{{ explicit }}')),
          timestamp('1970-01-01')
        ) as reference_ingested_at
    {%- endset -%}
  {%- else -%}
    {#- Marqueur lu à part : le filtre de partition de raw doit être un
        littéral, une sous-requête corrélée empêcherait l'élagage. -#}
    {%- set query -%}
      select coalesce(
        (select last_ingest
         from `{{ target.project }}.meta.state_snapshot`
         where name = '{{ var("france_travail_offers_snapshot_name") }}'),
        timestamp('1970-01-01')
      ) as last_ingest
    {%- endset -%}
    {%- set last_ingest = run_query(query).rows[0]['last_ingest'] -%}
    {%- set query -%}
      select
        (select min(_ingested_at)
         from {{ source_relation }}
         where _ingested_at > timestamp('{{ last_ingest }}')) as target_ingested_at,
        timestamp('{{ last_ingest }}') as reference_ingested_at
    {%- endset -%}
  {%- endif -%}

  {%- set dates = run_query(query).rows[0] -%}
  {%- set target_ingested_at = dates['target_ingested_at'] -%}
  {%- set reference_ingested_at = dates['reference_ingested_at'] -%}

  {%- if target_ingested_at is none -%}
    {{ exceptions.raise_compiler_error(
      "Aucun jour d'ingestion après le marqueur " ~ reference_ingested_at
      ~ " : snapshot annulé, rien à traiter."
    ) }}
  {%- endif -%}

  {#- 2. Volumes des deux jours, en une seule lecture -#}
  {%- set query -%}
    select
      countif(_ingested_at = timestamp('{{ target_ingested_at }}')) as target_count,
      countif(_ingested_at = timestamp('{{ reference_ingested_at }}')) as reference_count
    from {{ source_relation }}
    where _ingested_at in (
      timestamp('{{ target_ingested_at }}'),
      timestamp('{{ reference_ingested_at }}')
    )
  {%- endset -%}

  {%- set counts = run_query(query).rows[0] -%}
  {%- set target_count = counts['target_count'] -%}
  {%- set reference_count = counts['reference_count'] -%}
  {%- set min_ratio = var('france_travail_offers_min_volume_ratio') -%}

  {%- if target_count == 0 -%}
    {{ exceptions.raise_compiler_error(
      "Le jour ciblé (" ~ target_ingested_at
      ~ ") n'a aucune ligne dans raw : snapshot annulé."
    ) }}
  {%- endif -%}

  {%- if reference_count > 0 and target_count / reference_count < min_ratio -%}
    {{ exceptions.raise_compiler_error(
      "Volume anormalement bas pour le " ~ target_ingested_at ~ " : "
      ~ target_count ~ " lignes contre " ~ reference_count
      ~ " pour le jour de référence (" ~ reference_ingested_at
      ~ ") (ratio " ~ (target_count / reference_count) | round(3)
      ~ ", seuil " ~ min_ratio ~ "). Extraction partielle ? Pour forcer"
      ~ " après une baisse assumée : france_travail_offers_min_volume_ratio = 0."
    ) }}
  {%- endif -%}

  {{ return("timestamp('" ~ target_ingested_at ~ "')") }}
{% endmacro %}
