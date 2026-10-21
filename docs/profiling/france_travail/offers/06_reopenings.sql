-- Profil des clôtures et réouvertures, pour trancher la règle de clôture de
-- fct_offers : une offre est considérée close à sa disparition de la
-- collecte. Chaque run étant complet (full-refresh), une offre absente d'un
-- run puis de nouveau présente est une réouverture, ou un trou de collecte.
-- Lu sur raw_offer_runs, une ligne par offre et par run.

-- Runs numérotés dans l'ordre : un écart de numéros entre deux présences
-- d'une offre est un nombre de runs d'absence.
CREATE OR REPLACE TEMP VIEW runs AS
SELECT
    ingested_at,
    row_number() OVER (ORDER BY ingested_at) AS run_number
FROM (SELECT DISTINCT ingested_at FROM raw_offer_runs);

-- Une ligne par présence, avec la présence précédente de la même offre.
CREATE OR REPLACE TEMP VIEW presences AS
SELECT
    o.offer_id,
    r.run_number,
    o.ingested_at,
    o.raw ->> '$.dateActualisation' AS updated_at,
    lag(r.run_number) OVER w AS previous_run_number,
    lag(o.ingested_at) OVER w AS previous_ingested_at,
    lag(o.raw ->> '$.dateActualisation') OVER w AS previous_updated_at
FROM raw_offer_runs AS o
INNER JOIN runs AS r ON o.ingested_at = r.ingested_at
WINDOW w AS (PARTITION BY o.offer_id ORDER BY r.run_number);

.print "== 1. Volume par run : une chute brutale signale un run incomplet"
SELECT
    r.run_number,
    r.ingested_at,
    count(*) AS n_offers,
    count(*) - lag(count(*)) OVER (ORDER BY r.run_number) AS delta
FROM raw_offer_runs AS o
INNER JOIN runs AS r ON o.ingested_at = r.ingested_at
GROUP BY r.run_number, r.ingested_at
ORDER BY r.run_number;

.print "== 2. Clôtures et réouvertures"
WITH offers AS (
    SELECT
        offer_id,
        min(run_number) AS first_run,
        max(run_number) AS last_run,
        count(*) FILTER (WHERE run_number - previous_run_number > 1)
            AS n_reopenings
    FROM presences
    GROUP BY offer_id
)

SELECT
    count(*) AS n_offers,
    count(*) FILTER (WHERE last_run < (SELECT max(run_number) FROM runs))
        AS n_closed,
    count(*) FILTER (WHERE n_reopenings > 0) AS n_reopened,
    count(*) FILTER (WHERE n_reopenings > 1) AS n_reopened_several_times,
    round(
        count(*) FILTER (WHERE n_reopenings > 0) * 100.0
        / count(*) FILTER (
            WHERE last_run < (SELECT max(run_number) FROM runs)
            OR n_reopenings > 0
        ),
        2
    ) AS pct_closures_reopened
FROM offers;

.print "== 3. Durée des absences avant réouverture"
SELECT
    run_number - previous_run_number - 1 AS n_runs_absent,
    date_diff('day', previous_ingested_at, ingested_at) AS n_days_between,
    count(*) AS n_reopenings,
    count(*) FILTER (WHERE updated_at != previous_updated_at)
        AS n_updated_at_changed
FROM presences
WHERE run_number - previous_run_number > 1
GROUP BY n_runs_absent, n_days_between
ORDER BY n_runs_absent, n_days_between;

.print "== 4. Runs manqués par les offres rouvertes : un trou concentré sur un run désigne la collecte"
SELECT
    r.run_number,
    r.ingested_at,
    count(*) AS n_offers_missing
FROM presences AS p
INNER JOIN runs AS r
    ON
        r.run_number > p.previous_run_number
        AND r.run_number < p.run_number
GROUP BY r.run_number, r.ingested_at
ORDER BY r.run_number;
