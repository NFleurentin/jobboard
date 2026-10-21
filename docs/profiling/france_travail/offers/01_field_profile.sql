-- Profil de tous les champs du JSON brut, à tous les niveaux (raw_offers, une
-- ligne par offre) : une ligne par couple (chemin, type JSON), avec sa
-- présence et, pour les scalaires, le profil de ses valeurs. json_tree
-- parcourt le document récursivement, une ligne par nœud.
--
-- Présence : les indices de listes sont normalisés en [*], une ligne par
-- champ et non par position. n_offers compte les offres distinctes, n_nodes
-- les nœuds (une compétence par élément) : leur rapport donne le nombre
-- moyen d'éléments par offre. Un chemin sur plusieurs lignes a un type
-- hétérogène, ou est parfois présent avec la valeur null (type NULL) ; un
-- chemin absent n'apparaît pas.
--
-- Valeurs (NULL pour OBJECT et ARRAY) : valeurs distinctes, chaînes vides,
-- longueurs, top 5 des valeurs et des motifs. Le motif remplace chaque lettre
-- par a et chaque chiffre par 9 (un code postal donne 99999) : il montre le
-- format sans afficher la valeur. Valeurs et motifs sont tronqués à 30
-- caractères : sur un texte libre, seule la longueur est informative.
--
-- Les valeurs de contact et agence (données personnelles) sont masquées par
-- défaut, seuls leurs motifs sont affichés. PROFILING_SHOW_SENSITIVE=1 les
-- affiche, pour une lecture locale uniquement : ne pas les recopier dans la
-- documentation.

WITH offers_total AS (
    SELECT count(*) AS n_offers
    FROM raw_offers
),

nodes AS (
    SELECT
        r.offer_id,
        regexp_replace(t.fullkey, '\[\d+\]', '[*]', 'g') AS json_path,
        t.type AS value_type,
        -- ->> '$' renvoie la valeur sans les guillemets JSON
        CASE
            WHEN t.type NOT IN ('OBJECT', 'ARRAY') THEN t.value ->> '$'
        END AS value_text
    FROM raw_offers AS r
    CROSS JOIN json_tree(r.raw) AS t
    -- exclut la racine, le document entier
    WHERE t.fullkey != '$'
),

profiled AS (
    SELECT
        offer_id,
        json_path,
        value_type,
        value_text,
        regexp_replace(
            regexp_replace(value_text, '\pL', 'a', 'g'), '\d', '9', 'g'
        ) AS value_pattern,
        (json_path LIKE '$.contact.%' OR json_path LIKE '$.agence.%')
        AND coalesce(getenv('PROFILING_SHOW_SENSITIVE'), '') != '1'
            AS is_masked
    FROM nodes
),

path_stats AS (
    SELECT
        json_path,
        value_type,
        count(DISTINCT offer_id) AS n_offers,
        count(*) AS n_nodes,
        CASE
            WHEN value_type NOT IN ('OBJECT', 'ARRAY')
                THEN count(DISTINCT value_text)
        END AS n_distinct,
        CASE
            WHEN value_type NOT IN ('OBJECT', 'ARRAY')
                THEN count(*) FILTER (WHERE trim(value_text) = '')
        END AS n_empty,
        min(length(value_text)) AS min_length,
        max(length(value_text)) AS max_length
    FROM profiled
    GROUP BY json_path, value_type
),

value_counts AS (
    SELECT
        json_path,
        value_type,
        value_text,
        count(*) AS n,
        row_number() OVER (
            PARTITION BY json_path, value_type
            ORDER BY count(*) DESC, value_text
        ) AS rank_in_path
    FROM profiled
    WHERE value_text IS NOT NULL AND NOT is_masked
    GROUP BY json_path, value_type, value_text
),

top_values AS (
    SELECT
        json_path,
        value_type,
        list(left(value_text, 30) || ' (' || n || ')' ORDER BY rank_in_path)
            AS top_values
    FROM value_counts
    WHERE rank_in_path <= 5
    GROUP BY json_path, value_type
),

pattern_counts AS (
    SELECT
        json_path,
        value_type,
        value_pattern,
        count(*) AS n,
        row_number() OVER (
            PARTITION BY json_path, value_type
            ORDER BY count(*) DESC, value_pattern
        ) AS rank_in_path
    FROM profiled
    WHERE value_pattern IS NOT NULL
    GROUP BY json_path, value_type, value_pattern
),

top_patterns AS (
    SELECT
        json_path,
        value_type,
        list(
            left(value_pattern, 30) || ' (' || n || ')' ORDER BY rank_in_path
        ) AS top_patterns
    FROM pattern_counts
    WHERE rank_in_path <= 5
    GROUP BY json_path, value_type
)

SELECT
    s.json_path,
    s.value_type,
    s.n_offers,
    round(s.n_offers / t.n_offers * 100, 2) AS pct_offers,
    s.n_nodes,
    s.n_distinct,
    s.n_empty,
    s.min_length,
    s.max_length,
    v.top_values,
    p.top_patterns
FROM path_stats AS s
CROSS JOIN offers_total AS t
LEFT JOIN top_values AS v
    ON s.json_path = v.json_path AND s.value_type = v.value_type
LEFT JOIN top_patterns AS p
    ON s.json_path = p.json_path AND s.value_type = p.value_type
ORDER BY s.json_path, s.n_offers DESC;
