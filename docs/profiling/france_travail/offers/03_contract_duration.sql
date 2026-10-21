-- Profil du type et de la durée du contrat, pour trancher la conversion en
-- mois de contract_duration_months : le brut n'a pas de champ de durée, elle
-- est portée par typeContratLibelle ("CDD - 12 Mois"). Les regex reprennent
-- celles de stg_france_travail__offers, en dialecte DuckDB.

.print "== 1. Couples code et libellé du type de contrat"
SELECT
    raw ->> '$.typeContrat' AS contract_type_code,
    raw ->> '$.typeContratLibelle' AS contract_type_label,
    count(*) AS n_offers
FROM raw_offers
GROUP BY contract_type_code, contract_type_label
ORDER BY contract_type_code, n_offers DESC;

.print "== 2. Unités de durée : valeurs extraites par type de contrat"
WITH parsed AS (
    SELECT
        raw ->> '$.typeContrat' AS contract_type_code,
        try_cast(
            regexp_extract(
                raw ->> '$.typeContratLibelle', '-\s*(\d+)\s*\S+$', 1
            ) AS INTEGER
        ) AS duration_value,
        regexp_extract(
            raw ->> '$.typeContratLibelle', '-\s*\d+\s*(\S+)$', 1
        ) AS duration_unit
    FROM raw_offers
)

SELECT
    contract_type_code,
    nullif(duration_unit, '') AS duration_unit,
    count(*) AS n_offers,
    min(duration_value) AS min_value,
    max(duration_value) AS max_value,
    list(DISTINCT duration_value ORDER BY duration_value) AS duration_values
FROM parsed
GROUP BY contract_type_code, duration_unit
ORDER BY contract_type_code, n_offers DESC;

.print "== 3. Libellés contenant un tiret mais hors du motif de durée"
SELECT
    raw ->> '$.typeContratLibelle' AS contract_type_label,
    count(*) AS n_offers
FROM raw_offers
WHERE
    raw ->> '$.typeContratLibelle' LIKE '%-%'
    AND NOT regexp_matches(
        raw ->> '$.typeContratLibelle', '^.+-\s*\d+\s*\S+$'
    )
GROUP BY contract_type_label
ORDER BY n_offers DESC;

.print "== 4. Nature du contrat et alternance par type de contrat"
SELECT
    raw ->> '$.typeContrat' AS contract_type_code,
    raw ->> '$.natureContrat' AS contract_nature,
    raw ->> '$.alternance' AS is_work_study,
    count(*) AS n_offers
FROM raw_offers
GROUP BY contract_type_code, contract_nature, is_work_study
ORDER BY contract_type_code, n_offers DESC;
