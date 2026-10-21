-- Inventaire des clés de premier niveau du JSON brut : pour chaque couple
-- (clé, type JSON), le nombre et la part des offres concernées (raw_offers,
-- une ligne par offre). Une clé sur plusieurs lignes a un type hétérogène,
-- ou est parfois présente avec la valeur null (type NULL). La somme des parts
-- d'une clé donne son taux de présence ; une clé absente n'apparaît pas.

WITH offers_total AS (
    SELECT count(*) AS n_offers
    FROM raw_offers
),

fields AS (
    SELECT
        k.field_name,
        -- -> garde le JSON ; ->> convertirait en texte et masquerait le type
        json_type(r.raw -> k.field_name) AS value_type,
        count(*) AS n_offers
    FROM raw_offers AS r
    CROSS JOIN unnest(json_keys(r.raw)) AS k (field_name)
    GROUP BY k.field_name, value_type
)

SELECT
    f.field_name,
    f.value_type,
    f.n_offers,
    round(f.n_offers / t.n_offers * 100, 2) AS pct_offers
FROM fields AS f
CROSS JOIN offers_total AS t
ORDER BY f.field_name, f.n_offers DESC;
