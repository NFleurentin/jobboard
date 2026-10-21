-- Profil de l'entreprise, pour trancher la clé de dim_companies : le brut
-- n'a pas d'identifiant (01_field_profile.sql), la clé candidate est dérivée
-- du nom normalisé. Cinq questions, une requête chacune.

-- Normalisation candidate, en deux niveaux pour mesurer l'apport de chacun :
--   base : minuscules, sans accents, ponctuation remplacée par un espace ;
--   clé  : base, sans les formes juridiques courantes.
CREATE OR REPLACE TEMP MACRO company_name_base(company_name) AS
trim(regexp_replace(
    lower(strip_accents(company_name)), '[^a-z0-9]+', ' ', 'g'
));

CREATE OR REPLACE TEMP MACRO company_key(company_name) AS
trim(regexp_replace(
    regexp_replace(
        company_name_base(company_name),
        '\b(sas|sasu|sarl|sa|eurl|sci|snc|scop|ltd|inc|gmbh)\b', '', 'g'
    ),
    '\s+', ' ', 'g'
));

.print "== 1a. Noms distincts selon le niveau de normalisation"
SELECT
    count(*) AS n_offers_with_name,
    count(DISTINCT raw ->> '$.entreprise.nom') AS n_raw_names,
    count(DISTINCT company_name_base(raw ->> '$.entreprise.nom'))
        AS n_base_names,
    count(DISTINCT company_key(raw ->> '$.entreprise.nom')) AS n_keys
FROM raw_offers
WHERE raw ->> '$.entreprise.nom' IS NOT NULL;

.print "== 1b. Clés qui regroupent plusieurs noms bruts (20 premières)"
SELECT
    company_key(raw ->> '$.entreprise.nom') AS company_key,
    count(DISTINCT raw ->> '$.entreprise.nom') AS n_raw_names,
    count(*) AS n_offers,
    list(DISTINCT raw ->> '$.entreprise.nom') AS raw_names
FROM raw_offers
WHERE raw ->> '$.entreprise.nom' IS NOT NULL
GROUP BY company_key
HAVING count(DISTINCT raw ->> '$.entreprise.nom') > 1
ORDER BY n_raw_names DESC, n_offers DESC
LIMIT 20;

.print "== 2. Offres dont le nom d'entreprise change d'un run à l'autre"
WITH names_per_offer AS (
    SELECT
        offer_id,
        count(DISTINCT coalesce(raw ->> '$.entreprise.nom', '<absent>'))
            AS n_names,
        list(DISTINCT coalesce(raw ->> '$.entreprise.nom', '<absent>'))
            AS names
    FROM raw_offer_runs
    GROUP BY offer_id
)

SELECT
    count(*) AS n_offers,
    count(*) FILTER (WHERE n_names > 1) AS n_offers_name_changed,
    list(names) FILTER (WHERE n_names > 1)[1:5] AS examples
FROM names_per_offer;

.print "== 3a. Noms les plus fréquents : secteurs et partenaires de diffusion"
SELECT
    raw ->> '$.entreprise.nom' AS company_name,
    count(*) AS n_offers,
    count(DISTINCT raw ->> '$.codeNAF') AS n_naf_codes,
    list(DISTINCT raw ->> '$.secteurActiviteLibelle')[1:3] AS sectors,
    list(DISTINCT raw ->> '$.origineOffre.partenaires[0].nom') AS partners
FROM raw_offers
WHERE raw ->> '$.entreprise.nom' IS NOT NULL
GROUP BY company_name
ORDER BY n_offers DESC
LIMIT 15;

.print "== 3b. Offres d'agences d'intérim et de placement (NAF 78)"
SELECT
    raw ->> '$.codeNAF' AS naf_code,
    raw ->> '$.secteurActiviteLibelle' AS sector,
    count(*) AS n_offers,
    count(raw ->> '$.entreprise.nom') AS n_with_name
FROM raw_offers
WHERE raw ->> '$.codeNAF' LIKE '78%'
GROUP BY naf_code, sector
ORDER BY n_offers DESC;

.print "== 4. Noms suspects : clé vide ou de 3 caractères au plus"
SELECT
    raw ->> '$.entreprise.nom' AS company_name,
    company_key(raw ->> '$.entreprise.nom') AS company_key,
    count(*) AS n_offers
FROM raw_offers
WHERE length(company_key(raw ->> '$.entreprise.nom')) <= 3
GROUP BY company_name
ORDER BY n_offers DESC;

.print "== 5a. Clés dont un attribut varie d'une offre à l'autre"
WITH attributes_per_key AS (
    SELECT
        company_key(raw ->> '$.entreprise.nom') AS company_key,
        count(DISTINCT raw ->> '$.codeNAF') AS n_naf_codes,
        count(DISTINCT raw ->> '$.trancheEffectifEtab') AS n_size_bands,
        count(DISTINCT raw ->> '$.entreprise.url') AS n_urls,
        count(DISTINCT raw ->> '$.entreprise.description') AS n_descriptions
    FROM raw_offers
    WHERE raw ->> '$.entreprise.nom' IS NOT NULL
    GROUP BY company_key
)

SELECT
    count(*) AS n_keys,
    count(*) FILTER (WHERE n_naf_codes > 1) AS n_keys_multi_naf,
    count(*) FILTER (WHERE n_size_bands > 1) AS n_keys_multi_size_band,
    count(*) FILTER (WHERE n_urls > 1) AS n_keys_multi_url,
    count(*) FILTER (WHERE n_descriptions > 1) AS n_keys_multi_description
FROM attributes_per_key;

.print "== 5b. entrepriseAdaptee : premier niveau et objet entreprise"
SELECT
    raw ->> '$.entrepriseAdaptee' AS offer_level,
    raw ->> '$.entreprise.entrepriseAdaptee' AS company_level,
    count(*) AS n_offers
FROM raw_offers
GROUP BY offer_level, company_level
ORDER BY n_offers DESC;
