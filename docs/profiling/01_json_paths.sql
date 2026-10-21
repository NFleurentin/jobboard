-- Inventaire de tous les chemins du JSON brut, à tous les niveaux : pour
-- chaque couple (chemin, type JSON), le nombre et la part des offres
-- concernées (raw_offers, une ligne par offre). json_tree parcourt le
-- document récursivement, une ligne par nœud.
--
-- Les indices de listes sont normalisés en [*] : une ligne par champ, pas
-- par position. Un même chemin peut alors apparaître plusieurs fois dans une
-- offre (une compétence par élément) : n_offers compte les offres
-- distinctes, n_nodes les nœuds ; leur rapport donne le nombre moyen
-- d'éléments par offre.
--
-- Un chemin sur plusieurs lignes a un type hétérogène, ou est parfois présent
-- avec la valeur null (type NULL). Un chemin absent n'apparaît pas.

WITH offers_total AS (
    SELECT count(*) AS n_offers
    FROM raw_offers
),

nodes AS (
    SELECT
        r.offer_id,
        regexp_replace(t.fullkey, '\[\d+\]', '[*]', 'g') AS json_path,
        t.type AS value_type
    FROM raw_offers AS r
    CROSS JOIN json_tree(r.raw) AS t
    -- exclut la racine, le document entier
    WHERE t.fullkey != '$'
),

paths AS (
    SELECT
        json_path,
        value_type,
        count(DISTINCT offer_id) AS n_offers,
        count(*) AS n_nodes
    FROM nodes
    GROUP BY json_path, value_type
)

SELECT
    p.json_path,
    p.value_type,
    p.n_offers,
    round(p.n_offers / t.n_offers * 100, 2) AS pct_offers,
    p.n_nodes
FROM paths AS p
CROSS JOIN offers_total AS t
ORDER BY p.json_path, p.n_offers DESC;
