-- Staging : extrait, type et renomme les champs métier depuis _raw.
-- Incrémental, avec deux marqueurs distincts, chacun sur la colonne que le
-- snapshot modifie réellement pour ce type d'événement :
--   - dbt_valid_from > marqueur : capture les nouvelles versions.
--   - dbt_valid_to > marqueur (parmi les lignes déjà fermées) : capture les
--     fermetures, où SEUL dbt_valid_to change sur une ligne existante.
-- UNION DISTINCT (obligatoire en syntaxe BigQuery) : une ligne à la fois
-- "nouvelle" et "fermée" dans une même fenêtre de rattrapage apparaîtrait
-- dans les deux branches ; DISTINCT évite qu'elle ne fasse échouer le MERGE.
--
-- contact.* et agence.* SONT extraits ici (décision explicite, documentée
-- dans le README) : contact.nom peut contenir un nom de recruteur, publié
-- par France Travail lui-même dans le but de permettre de postuler. Gardé
-- pour usage personnel ; à exclure de toute vue ou dashboard rendu public.
--
-- Structure en CTE séparées par responsabilité :
--   extracted  : un JSON_VALUE/JSON_QUERY par champ, renommage seul.
--   derived    : dérive de nouveaux champs à partir de colonnes déjà
--                extraites (ex. ville/département depuis work_location_label),
--                jamais en repiochant dans raw_json.
--   cleaned : standardise le format des valeurs (ex. casse des villes).

{{
    config(
        materialized='incremental',
        unique_key=['offer_id', 'dbt_valid_from'],
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

WITH source AS (

    SELECT * FROM {{ ref('snap_france_travail__offers') }}

),

snapshot AS (

    {% if is_incremental() %}

        select * from source
        where
            dbt_valid_from > (
                select coalesce(max(dbt_valid_from), timestamp('1970-01-01'))
                from {{ this }}
            )

        union distinct

        select * from source
        where dbt_valid_to > (
            select coalesce(max(dbt_valid_to), timestamp('1970-01-01'))
            from {{ this }}
            where dbt_valid_to is not null
        )

    {% else %}

        select * from source

    {% endif %}

),

parsed AS (

    SELECT
        *,
        parse_json(_raw) AS raw_json
    FROM snapshot

),

extracted AS (

    SELECT
        offer_id,

        SAFE_CAST(json_value(raw_json, '$.dateCreation') AS TIMESTAMP) AS created_at,
        updated_at,

        -- Contenu de l'offre
        json_value(raw_json, '$.intitule') AS title,
        json_value(raw_json, '$.description') AS description,

        -- Entreprise
        json_value(raw_json, '$.entreprise.nom') AS company_name,
        json_value(raw_json, '$.entreprise.description') AS company_description,
        json_value(raw_json, '$.entreprise.url') AS company_url,
        json_value(raw_json, '$.entreprise.logo') AS company_logo,
        SAFE_CAST(
            json_value(raw_json, '$.entreprise.entrepriseAdaptee') AS BOOL
        ) AS company_is_adapted,

        -- Localisation
        json_value(raw_json, '$.lieuTravail.libelle') AS work_location_label,
        json_value(raw_json, '$.lieuTravail.codePostal')
            AS work_location_postal_code,
        json_value(raw_json, '$.lieuTravail.commune')
            AS work_location_commune_code,
        SAFE_CAST(json_value(raw_json, '$.lieuTravail.latitude') AS FLOAT64)
            AS work_location_latitude,
        SAFE_CAST(json_value(raw_json, '$.lieuTravail.longitude') AS FLOAT64)
            AS work_location_longitude,

        -- Métier / classification
        json_value(raw_json, '$.romeCode') AS rome_code,
        json_value(raw_json, '$.romeLibelle') AS rome_label,
        json_value(raw_json, '$.appellationlibelle') AS appellation_label,
        json_value(raw_json, '$.codeNAF') AS naf_code,
        json_value(raw_json, '$.secteurActivite') AS sector_code,
        json_value(raw_json, '$.secteurActiviteLibelle') AS sector_label,
        json_value(raw_json, '$.trancheEffectifEtab') AS company_size_label,

        -- Contrat
        json_value(raw_json, '$.typeContrat') AS contract_type_code,
        json_value(raw_json, '$.typeContratLibelle') AS contract_type_label,
        json_value(raw_json, '$.natureContrat') AS contract_nature,
        json_value(raw_json, '$.dureeTravailLibelle')
            AS working_time_detail_label,
        json_value(raw_json, '$.dureeTravailLibelleConverti')
            AS working_time_label,
        SAFE_CAST(json_value(raw_json, '$.nombrePostes') AS INT64)
            AS position_count,
        SAFE_CAST(json_value(raw_json, '$.alternance') AS BOOL)
            AS is_apprenticeship,

        -- Expérience / qualification
        json_value(raw_json, '$.experienceExige') AS experience_required_code,
        json_value(raw_json, '$.experienceLibelle') AS experience_label,
        json_value(raw_json, '$.experienceCommentaire') AS experience_comment,
        json_value(raw_json, '$.qualificationCode') AS qualification_code,
        json_value(raw_json, '$.qualificationLibelle') AS qualification_label,

        -- Salaire (texte libre ; parsing en min/max numériques prévu en aval :
        -- règles d'interprétation ambiguës — unité, fourchette, "à partir
        -- de"... une vraie logique métier, pas un simple découpage.)
        json_value(raw_json, '$.salaire.libelle') AS salary_label,
        json_value(raw_json, '$.salaire.commentaire') AS salary_comment,
        json_value(raw_json, '$.salaire.complement1') AS salary_complement_1,
        json_value(raw_json, '$.salaire.complement2') AS salary_complement_2,

        -- Divers
        json_value(raw_json, '$.deplacementCode') AS travel_code,
        json_value(raw_json, '$.deplacementLibelle') AS travel_label,
        json_value(raw_json, '$.complementExercice') AS exercise_complement,
        json_value(raw_json, '$.contexteTravail.conditionsExercice')
            AS working_conditions,
        SAFE_CAST(json_value(raw_json, '$.accessibleTH') AS BOOL)
            AS is_disability_accessible,
        SAFE_CAST(json_value(raw_json, '$.entrepriseAdaptee') AS BOOL)
            AS offer_is_adapted,
        SAFE_CAST(json_value(raw_json, '$.employeurHandiEngage') AS BOOL)
            AS employer_disability_committed,
        SAFE_CAST(json_value(raw_json, '$.offresManqueCandidats') AS BOOL)
            AS lacks_candidates,

        -- Origine / lien
        json_value(raw_json, '$.origineOffre.origine') AS source_origin_code,
        json_value(raw_json, '$.origineOffre.urlOrigine') AS source_url,

        -- Contact (donnée personnelle : nom de recruteur possible dans
        -- contact.nom — publié par France Travail pour permettre de
        -- postuler. Gardé pour usage personnel ; à exclure de toute vue
        -- ou dashboard rendu public.)
        json_value(raw_json, '$.contact.nom') AS contact_name,
        json_value(raw_json, '$.contact.courriel') AS contact_email,
        json_value(raw_json, '$.contact.telephone') AS contact_phone,
        json_value(raw_json, '$.contact.commentaire') AS contact_comment,
        json_value(raw_json, '$.contact.coordonnees1') AS contact_address_1,
        json_value(raw_json, '$.contact.coordonnees2') AS contact_address_2,
        json_value(raw_json, '$.contact.coordonnees3') AS contact_address_3,
        json_value(raw_json, '$.contact.urlRecruteur') AS contact_recruiter_url,
        json_value(raw_json, '$.contact.urlPostulation')
            AS contact_application_url,

        -- Agence
        json_value(raw_json, '$.agence.telephone') AS agency_phone,
        json_value(raw_json, '$.agence.courriel') AS agency_email,

        -- Champs composites, laissés en JSON brut : structure variable
        -- (tableaux), pas de valeur à plat évidente sans logique métier
        -- supplémentaire (à traiter en aval si besoin).
        json_query(raw_json, '$.competences') AS competences_json,
        json_query(raw_json, '$.formations') AS formations_json,
        json_query(raw_json, '$.langues') AS langues_json,
        json_query(raw_json, '$.permis') AS permis_json,
        json_query(raw_json, '$.outilsBureautiques')
            AS office_tools_json,
        json_query(raw_json, '$.contexteTravail.conditionsExercice')
            AS working_conditions_json,
        json_query(raw_json, '$.qualitesProfessionnelles')
            AS qualites_professionnelles_json,
        json_query(raw_json, '$.salaire.listeComplements')
            AS salary_complements_json,
        json_query(raw_json, '$.origineOffre.partenaires')
            AS source_origin_partners_json,

        -- raw_json n'est PAS exposé en sortie : déjà disponible une couche
        -- plus haut (snap_france_travail__offers._raw), via PARSE_JSON(_raw)
        -- en cas de besoin ponctuel. Pas de duplication inutile entre couches.
        _extracted_at,
        _ingested_at,
        dbt_valid_from AS _valid_from,
        dbt_valid_to AS _valid_to

    FROM parsed

),

derived AS (

    SELECT
        *,

        -- work_location_label suit le plus souvent "<département> - <ville>"
        -- (ex. "77 - Chessy"), avec le cas particulier de la Corse ("2A"/"2B",
        -- pas des chiffres). Certaines offres sortent du format (ex.
        -- "Montréal, QC, Canada") : les deux colonnes restent alors NULL,
        -- work_location_label garde la valeur brute pour inspection.
        -- Calculé depuis work_location_label (déjà extrait ci-dessus), pas
        -- en repiochant dans raw_json.
        regexp_extract(work_location_label, r'^(2[AB]|\d{2,3})\s*-\s*.+$')
            AS work_location_department_code,
        regexp_extract(work_location_label, r'^(?:2[AB]|\d{2,3})\s*-\s*(.+)$')
            AS work_location_city_raw,

        -- contract_type_label suit le plus souvent "<type> - <N> <unité>"
        -- (ex. "Intérim - 1 Mois") ; le CDI, entre autres, n'a pas de durée
        -- (pas de suffixe). L'unité est capturée telle quelle (pas supposée
        -- "toujours Mois") : si une offre utilise une autre unité un jour,
        -- elle apparaît ici plutôt que d'être silencieusement mal interprétée.
        CASE
            WHEN regexp_contains(contract_type_label, r'^.+-\s*\d+\s*\S+$')
                THEN
                    regexp_extract(
                        contract_type_label, r'^(.+?)\s*-\s*\d+\s*\S+$'
                    )
            ELSE contract_type_label
        END AS contract_type_label_clean,
        SAFE_CAST(
            regexp_extract(contract_type_label, r'-\s*(\d+)\s*\S+$') AS INT64
        ) AS contract_duration_value,
        regexp_extract(contract_type_label, r'-\s*\d+\s*(\S+)$')
            AS contract_duration_unit,

        -- salary_label suit le plus souvent "<périodicité> de <min> Euros
        -- à <max> Euros" (ex. "Annuel de 50000.0 Euros à 55000.0 Euros"),
        -- parfois une valeur unique sans "à" (ex. "Horaire de 12.31 Euros"),
        -- parfois du texte supplémentaire après le montant (ex. "... -
        -- télétravail, participation, mutuelle") : les regex ne sont pas
        -- ancrées en fin de chaîne, ce texte est simplement ignoré. Pas de
        -- conversion vers une périodicité commune ici (ex. horaire ->
        -- mensuel supposerait un nombre d'heures/semaine, une vraie
        -- hypothèse) : periodicity reste explicite, la conversion éventuelle
        -- se fait en aval, en connaissance de cause.
        regexp_extract(salary_label, r'^(\w+)\s+de\s+')
            AS salary_periodicity,
        SAFE_CAST(
            regexp_extract(
                salary_label, r'de\s+([\d]+(?:\.[\d]+)?)\s*Euros'
            ) AS FLOAT64
        ) AS salary_min,
        SAFE_CAST(
            regexp_extract(
                salary_label, r'à\s+([\d]+(?:\.[\d]+)?)\s*Euros'
            ) AS FLOAT64
        ) AS salary_max,

        -- working_time_detail_label contient parfois deux lignes séparées
        -- par un retour à la ligne (ex. "35H/semaine\nTravail en journée"),
        -- parfois une seule (ex. "Travail en journée" seul, sans heures).
        -- On détecte si la première ligne ressemble à une expression
        -- d'heures ("\dH") ; sinon elle est elle-même le type d'horaire.
        -- working_hours_max prévu pour une éventuelle fourchette
        -- ("20H-25H/semaine") : non observée dans l'échantillon à ce jour,
        -- à vérifier. La périodicité ("semaine") est capturée telle
        -- quelle, pas supposée fixe.
        CASE
            WHEN
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                THEN SAFE_CAST(
                    regexp_extract(
                        split(working_time_detail_label, '\n')[safe_offset(0)],
                        r'^(\d+)H'
                    ) AS INT64
                )
        END AS working_hours_min,
        CASE
            WHEN
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                THEN SAFE_CAST(
                    regexp_extract(
                        split(working_time_detail_label, '\n')[safe_offset(0)],
                        r'-(\d+)H'
                    ) AS INT64
                )
        END AS working_hours_max,
        CASE
            WHEN
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                THEN regexp_extract(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'/(\w+)$'
                )
        END AS working_hours_periodicity,
        CASE
            WHEN
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                THEN split(working_time_detail_label, '\n')[safe_offset(1)]
            ELSE split(working_time_detail_label, '\n')[safe_offset(0)]
        END AS working_schedule_type

    FROM extracted

),

cleaned AS (

    SELECT
        * EXCEPT (work_location_city_raw, company_name),

        -- Les villes arrivent tantôt en majuscules, tantôt en minuscules/
        -- casse mixte selon l'offre. INITCAP standardise en "Première
        -- Lettre Majuscule" par mot. À vérifier sur un échantillon réel
        -- pour les noms composés accentués (ex. "Saint-Étienne") : le
        -- comportement de INITCAP sur les caractères accentués n'est pas
        -- garanti à 100% sans test.
        initcap(work_location_city_raw) AS work_location_city,

        -- Attention avec company_name : INITCAP peut dénaturer des sigles
        -- ou des casses volontaires (ex. "SNCF" -> "Sncf", "CIBOX
        -- INTER@CTIVE" -> "Cibox Inter@Ctive"). Accepté comme compromis ;
        -- à vérifier sur un échantillon si ça gêne pour certains cas.
        initcap(company_name) AS company_name

    FROM derived

),

final AS (

    SELECT
        offer_id,

        -- Dates
        created_at,
        updated_at,

        -- Contenu
        title,
        description,

        -- Entreprise
        company_name,
        company_description,
        company_url,
        company_logo,
        company_is_adapted,

        -- Localisation
        work_location_label,
        work_location_city,
        work_location_department_code,
        work_location_postal_code,
        work_location_commune_code,
        work_location_latitude,
        work_location_longitude,

        -- Métier / classification
        rome_code,
        rome_label,
        appellation_label,
        naf_code,
        sector_code,
        sector_label,
        company_size_label,

        -- Contrat
        contract_type_code,
        contract_type_label,
        contract_type_label_clean,
        contract_duration_value,
        contract_duration_unit,
        contract_nature,
        working_time_detail_label,
        working_hours_min,
        working_hours_max,
        working_hours_periodicity,
        working_schedule_type,
        working_time_label,
        position_count,
        is_apprenticeship,

        -- Expérience / qualification
        experience_required_code,
        experience_label,
        experience_comment,
        qualification_code,
        qualification_label,

        -- Salaire
        salary_label,
        salary_periodicity,
        salary_min,
        salary_max,
        salary_comment,
        salary_complement_1,
        salary_complement_2,

        -- Divers
        travel_code,
        travel_label,
        exercise_complement,
        working_conditions,
        is_disability_accessible,
        offer_is_adapted,
        employer_disability_committed,
        lacks_candidates,

        -- Origine / lien
        source_origin_code,
        source_url,

        -- Contact (donnée personnelle, regroupée ici pour une visibilité
        -- claire — facilite une future exclusion/masquage en bloc).
        contact_name,
        contact_email,
        contact_phone,
        contact_comment,
        contact_address_1,
        contact_address_2,
        contact_address_3,
        contact_recruiter_url,
        contact_application_url,
        agency_phone,
        agency_email,

        -- Champs composites (JSON brut)
        competences_json,
        formations_json,
        langues_json,
        permis_json,
        office_tools_json,
        working_conditions_json,
        qualites_professionnelles_json,
        salary_complements_json,
        source_origin_partners_json,

        -- Métadonnées techniques
        _extracted_at,
        _ingested_at,
        _valid_from,
        _valid_to

    FROM cleaned

)

SELECT * FROM final
