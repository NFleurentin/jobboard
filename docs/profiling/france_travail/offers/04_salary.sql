-- Profil du salaire, pour trancher la conversion en brut annuel : formats de
-- salaire.libelle, périodicités, nombre de mois de paie, contenu de
-- salaire.commentaire et compléments (futurs dim_benefits). Les regex
-- reprennent celles de stg_france_travail__offers, en dialecte DuckDB.

.print "== 1. Présence du libellé et du commentaire"
SELECT
    raw ->> '$.salaire.libelle' IS NOT NULL AS has_label,
    raw ->> '$.salaire.commentaire' IS NOT NULL AS has_comment,
    count(*) AS n_offers
FROM raw_offers
GROUP BY has_label, has_comment
ORDER BY n_offers DESC;

.print "== 2. Formats du libellé avant le premier ' - ', montants remplacés par N"
-- Le texte libre qui suit ' - ' (avantages, rappel du montant) est compté
-- à part : il multiplie les formats sans changer la partie lue par le
-- staging.
SELECT
    regexp_replace(
        split_part(raw ->> '$.salaire.libelle', ' - ', 1),
        '\d+(\.\d+)?', 'N', 'g'
    ) AS label_format,
    count(*) AS n_offers,
    count(*) FILTER (WHERE raw ->> '$.salaire.libelle' LIKE '% - %')
        AS n_with_free_text
FROM raw_offers
WHERE raw ->> '$.salaire.libelle' IS NOT NULL
GROUP BY label_format
ORDER BY n_offers DESC;

.print "== 3. Montants extraits par périodicité"
WITH parsed AS (
    SELECT
        nullif(
            regexp_extract(raw ->> '$.salaire.libelle', '^(\w+)\s+de\s+', 1),
            ''
        ) AS periodicity,
        try_cast(
            regexp_extract(
                raw ->> '$.salaire.libelle',
                'de\s+(\d+(?:\.\d+)?)\s*Euros', 1
            ) AS DECIMAL(12, 2)
        ) AS salary_min,
        try_cast(
            regexp_extract(
                raw ->> '$.salaire.libelle',
                'à\s+(\d+(?:\.\d+)?)\s*Euros', 1
            ) AS DECIMAL(12, 2)
        ) AS salary_max
    FROM raw_offers
    WHERE raw ->> '$.salaire.libelle' IS NOT NULL
)

SELECT
    periodicity,
    count(*) AS n_offers,
    count(salary_min) AS n_with_min,
    count(salary_max) AS n_with_max,
    min(salary_min) AS lowest_min,
    median(salary_min) AS median_min,
    max(salary_min) AS highest_min,
    max(salary_max) AS highest_max,
    count(*) FILTER (WHERE salary_max < salary_min) AS n_max_below_min
FROM parsed
GROUP BY periodicity
ORDER BY n_offers DESC;

.print "== 3b. Montants hors d'une plage plausible candidate, par périodicité"
-- Plages candidates (hypothèse à valider) : annuel 15 000-200 000,
-- mensuel 1 200-15 000, horaire 9-100. Un minimum hors plage signale
-- souvent une périodicité mal saisie (annuel saisi en mensuel, etc.).
WITH parsed AS (
    SELECT
        regexp_extract(raw ->> '$.salaire.libelle', '^(\w+)\s+de\s+', 1)
            AS periodicity,
        try_cast(
            regexp_extract(
                raw ->> '$.salaire.libelle',
                'de\s+(\d+(?:\.\d+)?)\s*Euros', 1
            ) AS DECIMAL(12, 2)
        ) AS salary_min,
        try_cast(
            regexp_extract(
                raw ->> '$.salaire.libelle',
                'à\s+(\d+(?:\.\d+)?)\s*Euros', 1
            ) AS DECIMAL(12, 2)
        ) AS salary_max
    FROM raw_offers
    WHERE raw ->> '$.salaire.libelle' IS NOT NULL
),

bounded AS (
    SELECT
        *,
        CASE periodicity
            WHEN 'Annuel' THEN 15000
            WHEN 'Mensuel' THEN 1200
            WHEN 'Horaire' THEN 9
        END AS lower_bound,
        CASE periodicity
            WHEN 'Annuel' THEN 200000
            WHEN 'Mensuel' THEN 15000
            WHEN 'Horaire' THEN 100
        END AS upper_bound
    FROM parsed
)

SELECT
    periodicity,
    count(*) FILTER (
        WHERE salary_min NOT BETWEEN lower_bound AND upper_bound
    ) AS n_min_out_of_range,
    count(*) FILTER (
        WHERE salary_max NOT BETWEEN lower_bound AND upper_bound
    ) AS n_max_out_of_range,
    list(salary_min || '-' || coalesce(salary_max::VARCHAR, ''))
        FILTER (
            WHERE salary_min NOT BETWEEN lower_bound AND upper_bound
            OR salary_max NOT BETWEEN lower_bound AND upper_bound
        ) AS out_of_range_amounts
FROM bounded
GROUP BY periodicity
ORDER BY periodicity;

.print "== 4. Nombre de mois de paie cité dans le libellé ou le commentaire"
SELECT
    regexp_extract(
        concat_ws(' ', raw ->> '$.salaire.libelle',
            raw ->> '$.salaire.commentaire'),
        '(\d+(?:[.,]\d+)?)\s*mois', 1
    ) AS n_months,
    count(*) AS n_offers
FROM raw_offers
WHERE regexp_matches(
    concat_ws(' ', raw ->> '$.salaire.libelle',
        raw ->> '$.salaire.commentaire'),
    '\d+(?:[.,]\d+)?\s*mois'
)
GROUP BY n_months
ORDER BY n_offers DESC;

.print "== 5. Commentaires les plus fréquents (30 premiers)"
SELECT
    raw ->> '$.salaire.commentaire' AS salary_comment,
    count(*) AS n_offers,
    count(raw ->> '$.salaire.libelle') AS n_with_label
FROM raw_offers
WHERE raw ->> '$.salaire.commentaire' IS NOT NULL
GROUP BY salary_comment
ORDER BY n_offers DESC
LIMIT 30;

.print "== 5b. Taux journaliers dans le commentaire, par type de contrat"
SELECT
    raw ->> '$.typeContrat' AS contract_type_code,
    (raw ->> '$.entreprise.nom') = 'Collective.work' AS is_collective_work,
    count(*) AS n_offers
FROM raw_offers
WHERE (raw ->> '$.salaire.commentaire') ILIKE '%par jour%'
GROUP BY contract_type_code, is_collective_work
ORDER BY n_offers DESC;

.print "== 6a. Compléments de salaire (listeComplements)"
WITH complements AS (
    SELECT
        unnest(
            from_json(
                raw -> '$.salaire.listeComplements',
                '[{"code": "VARCHAR", "libelle": "VARCHAR"}]'
            )
        ) AS complement
    FROM raw_offers
)

SELECT
    complement.code AS complement_code,
    complement.libelle AS complement_label,
    count(*) AS n_offers
FROM complements
GROUP BY complement_code, complement_label
ORDER BY n_offers DESC;

.print "== 6b. complement1 et complement2 face aux deux premiers éléments de la liste"
SELECT
    -- parenthèses obligatoires : = est prioritaire sur ->>
    (raw ->> '$.salaire.complement1')
    = (raw ->> '$.salaire.listeComplements[0].libelle') AS complement1_matches,
    (raw ->> '$.salaire.complement2')
    = (raw ->> '$.salaire.listeComplements[1].libelle') AS complement2_matches,
    json_array_length(raw -> '$.salaire.listeComplements') AS n_complements,
    count(*) AS n_offers
FROM raw_offers
WHERE (raw -> '$.salaire.listeComplements') IS NOT NULL
GROUP BY complement1_matches, complement2_matches, n_complements
ORDER BY n_complements, n_offers DESC;
