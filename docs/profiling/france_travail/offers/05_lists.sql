-- Profil des listes qui alimenteront dim_skills, dim_educations et leurs
-- bridges : compétences, qualités professionnelles, langues, permis et
-- formations. Pour chaque liste : clé candidate de la dimension (code ou
-- libellé), valeurs d'exigence, doublons au sein d'une offre.

-- Un élément de liste par ligne. json_tree renvoie, pour chaque élément, le
-- chemin de sa liste dans path ; un chemin calculé dans -> ne renverrait
-- pas une liste dépliable par unnest.
CREATE OR REPLACE TEMP VIEW list_elements AS
SELECT
    r.offer_id,
    substr(t.path, 3) AS list_name,
    t.value AS element
FROM raw_offers AS r
CROSS JOIN json_tree(r.raw) AS t
WHERE t.path IN (
    '$.competences',
    '$.qualitesProfessionnelles',
    '$.langues',
    '$.permis',
    '$.formations'
);

.print "== 1. Volume par liste"
SELECT
    list_name,
    count(DISTINCT offer_id) AS n_offers,
    count(*) AS n_elements,
    count(DISTINCT element ->> '$.libelle') AS n_distinct_labels
FROM list_elements
GROUP BY list_name
ORDER BY n_elements DESC;

.print "== 2. Valeurs d'exigence par liste"
SELECT
    list_name,
    element ->> '$.exigence' AS requirement,
    count(*) AS n_elements
FROM list_elements
GROUP BY list_name, requirement
ORDER BY list_name, n_elements DESC;

.print "== 3a. Compétences : correspondance entre code et libellé"
WITH skills AS (
    SELECT
        element ->> '$.code' AS skill_code,
        element ->> '$.libelle' AS skill_label
    FROM list_elements
    WHERE list_name = 'competences'
),

codes AS (
    SELECT skill_code
    FROM skills
    WHERE skill_code IS NOT NULL
    GROUP BY skill_code
    HAVING count(DISTINCT skill_label) > 1
),

labels AS (
    SELECT skill_label
    FROM skills
    WHERE skill_code IS NOT NULL
    GROUP BY skill_label
    HAVING count(DISTINCT skill_code) > 1
)

SELECT
    count(DISTINCT skill_code) AS n_codes,
    count(DISTINCT skill_label) AS n_labels,
    count(*) FILTER (WHERE skill_code IS NULL) AS n_elements_without_code,
    count(DISTINCT skill_label) FILTER (WHERE skill_code IS NULL)
        AS n_labels_without_code,
    (SELECT count(*) FROM codes) AS n_codes_with_several_labels,
    (SELECT count(*) FROM labels) AS n_labels_with_several_codes
FROM skills;

.print "== 3b. Compétences sans code : libellés les plus fréquents"
WITH skills AS (
    SELECT
        element ->> '$.code' AS skill_code,
        element ->> '$.libelle' AS skill_label
    FROM list_elements
    WHERE list_name = 'competences'
)

SELECT
    skill_label,
    count(*) FILTER (WHERE skill_code IS NULL) AS n_without_code,
    -- le même libellé a-t-il un code dans d'autres offres ?
    count(*) FILTER (WHERE skill_code IS NOT NULL) AS n_with_code
FROM skills
GROUP BY skill_label
HAVING count(*) FILTER (WHERE skill_code IS NULL) > 0
ORDER BY n_without_code DESC
LIMIT 15;

.print "== 4. Qualités professionnelles : la description dépend-elle du libellé ?"
SELECT
    count(DISTINCT element ->> '$.libelle') AS n_labels,
    count(DISTINCT element ->> '$.description') AS n_descriptions,
    count(DISTINCT (element ->> '$.libelle') || '|' || (element ->> '$.description'))
        AS n_label_description_pairs
FROM list_elements
WHERE list_name = 'qualitesProfessionnelles';

.print "== 5. Langues et permis : libellés"
SELECT
    list_name,
    element ->> '$.libelle' AS label,
    count(*) AS n_elements
FROM list_elements
WHERE list_name IN ('langues', 'permis')
GROUP BY list_name, label
ORDER BY list_name, n_elements DESC;

.print "== 6a. Formations : niveaux"
SELECT
    element ->> '$.niveauLibelle' AS education_level,
    count(*) AS n_elements,
    count(element ->> '$.domaineLibelle') AS n_with_domain
FROM list_elements
WHERE list_name = 'formations'
GROUP BY education_level
ORDER BY n_elements DESC;

.print "== 6b. Formations : grain candidat (niveau, domaine) et code de domaine"
WITH educations AS (
    SELECT
        element ->> '$.niveauLibelle' AS education_level,
        element ->> '$.domaineLibelle' AS education_domain,
        element ->> '$.codeFormation' AS education_code
    FROM list_elements
    WHERE list_name = 'formations'
)

SELECT
    count(DISTINCT education_domain) AS n_domains,
    count(DISTINCT education_code) AS n_codes,
    count(DISTINCT education_code || '|' || education_domain)
        AS n_code_domain_pairs,
    count(DISTINCT coalesce(education_level, '') || '|'
        || coalesce(education_domain, '')) AS n_level_domain_pairs
FROM educations;

.print "== 6c. Formations : commentaires les plus fréquents"
SELECT
    element ->> '$.commentaire' AS education_comment,
    count(*) AS n_elements
FROM list_elements
WHERE
    list_name = 'formations'
    AND (element ->> '$.commentaire') IS NOT NULL
GROUP BY education_comment
ORDER BY n_elements DESC
LIMIT 15;

.print "== 7. Doublons au sein d'une offre (clé candidate : libellé, ou niveau et domaine)"
WITH entries AS (
    SELECT
        offer_id,
        list_name,
        CASE
            WHEN list_name = 'formations'
                THEN coalesce(element ->> '$.niveauLibelle', '') || '|'
                || coalesce(element ->> '$.domaineLibelle', '')
            ELSE element ->> '$.libelle'
        END AS entry_key,
        count(*) AS n_occurrences
    FROM list_elements
    GROUP BY offer_id, list_name, entry_key
)

SELECT
    list_name,
    count(*) FILTER (WHERE n_occurrences > 1) AS n_duplicated_keys,
    count(DISTINCT offer_id) FILTER (WHERE n_occurrences > 1)
        AS n_offers_with_duplicates
FROM entries
GROUP BY list_name
ORDER BY list_name;
