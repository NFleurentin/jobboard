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

with source as (

    select * from {{ ref('snap_france_travail__offers') }}

),

snapshot as (

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

parsed as (

    select
        *,
        parse_json(_raw) as raw_json
    from snapshot

),

extracted as (

    select
        offer_id,

        json_value(raw_json, '$.dateCreation') as created_at,
        updated_at,

        -- Contenu de l'offre
        json_value(raw_json, '$.intitule') as title,
        json_value(raw_json, '$.description') as description,

        -- Entreprise
        json_value(raw_json, '$.entreprise.nom') as company_name,
        json_value(raw_json, '$.entreprise.description') as company_description,
        json_value(raw_json, '$.entreprise.url') as company_url,
        json_value(raw_json, '$.entreprise.logo') as company_logo,
        safe_cast(
            json_value(raw_json, '$.entreprise.entrepriseAdaptee') as bool
        ) as company_is_adapted,

        -- Localisation
        json_value(raw_json, '$.lieuTravail.libelle') as work_location_label,
        json_value(raw_json, '$.lieuTravail.codePostal')
            as work_location_postal_code,
        json_value(raw_json, '$.lieuTravail.commune')
            as work_location_commune_code,
        safe_cast(json_value(raw_json, '$.lieuTravail.latitude') as float64)
            as work_location_latitude,
        safe_cast(json_value(raw_json, '$.lieuTravail.longitude') as float64)
            as work_location_longitude,

        -- Métier / classification
        json_value(raw_json, '$.romeCode') as rome_code,
        json_value(raw_json, '$.romeLibelle') as rome_label,
        json_value(raw_json, '$.appellationlibelle') as appellation_label,
        json_value(raw_json, '$.codeNAF') as naf_code,
        json_value(raw_json, '$.secteurActivite') as sector_code,
        json_value(raw_json, '$.secteurActiviteLibelle') as sector_label,
        json_value(raw_json, '$.trancheEffectifEtab') as company_size_label,

        -- Contrat
        json_value(raw_json, '$.typeContrat') as contract_type_code,
        json_value(raw_json, '$.typeContratLibelle') as contract_type_label,
        json_value(raw_json, '$.natureContrat') as contract_nature,
        json_value(raw_json, '$.dureeTravailLibelle')
            as working_time_detail_label,
        json_value(raw_json, '$.dureeTravailLibelleConverti')
            as working_time_label,
        safe_cast(json_value(raw_json, '$.nombrePostes') as int64)
            as position_count,
        safe_cast(json_value(raw_json, '$.alternance') as bool)
            as is_apprenticeship,

        -- Expérience / qualification
        json_value(raw_json, '$.experienceExige') as experience_required_code,
        json_value(raw_json, '$.experienceLibelle') as experience_label,
        json_value(raw_json, '$.experienceCommentaire') as experience_comment,
        json_value(raw_json, '$.qualificationCode') as qualification_code,
        json_value(raw_json, '$.qualificationLibelle') as qualification_label,

        -- Salaire (texte libre ; parsing en min/max numériques prévu en aval :
        -- règles d'interprétation ambiguës — unité, fourchette, "à partir
        -- de"... une vraie logique métier, pas un simple découpage.)
        json_value(raw_json, '$.salaire.libelle') as salary_label,
        json_value(raw_json, '$.salaire.commentaire') as salary_comment,
        json_value(raw_json, '$.salaire.complement1') as salary_complement_1,
        json_value(raw_json, '$.salaire.complement2') as salary_complement_2,

        -- Divers
        json_value(raw_json, '$.deplacementCode') as travel_code,
        json_value(raw_json, '$.deplacementLibelle') as travel_label,
        json_value(raw_json, '$.complementExercice') as exercise_complement,
        json_value(raw_json, '$.contexteTravail.conditionsExercice')
            as working_conditions,
        safe_cast(json_value(raw_json, '$.accessibleTH') as bool)
            as is_disability_accessible,
        safe_cast(json_value(raw_json, '$.entrepriseAdaptee') as bool)
            as offer_is_adapted,
        safe_cast(json_value(raw_json, '$.employeurHandiEngage') as bool)
            as employer_disability_committed,
        safe_cast(json_value(raw_json, '$.offresManqueCandidats') as bool)
            as lacks_candidates,

        -- Origine / lien
        json_value(raw_json, '$.origineOffre.origine') as source_origin_code,
        json_value(raw_json, '$.origineOffre.urlOrigine') as source_url,

        -- Contact (donnée personnelle : nom de recruteur possible dans
        -- contact.nom — publié par France Travail pour permettre de
        -- postuler. Gardé pour usage personnel ; à exclure de toute vue
        -- ou dashboard rendu public.)
        json_value(raw_json, '$.contact.nom') as contact_name,
        json_value(raw_json, '$.contact.courriel') as contact_email,
        json_value(raw_json, '$.contact.telephone') as contact_phone,
        json_value(raw_json, '$.contact.commentaire') as contact_comment,
        json_value(raw_json, '$.contact.coordonnees1') as contact_address_1,
        json_value(raw_json, '$.contact.coordonnees2') as contact_address_2,
        json_value(raw_json, '$.contact.coordonnees3') as contact_address_3,
        json_value(raw_json, '$.contact.urlRecruteur') as contact_recruiter_url,
        json_value(raw_json, '$.contact.urlPostulation')
            as contact_application_url,

        -- Agence
        json_value(raw_json, '$.agence.telephone') as agency_phone,
        json_value(raw_json, '$.agence.courriel') as agency_email,

        -- Champs composites, laissés en JSON brut : structure variable
        -- (tableaux), pas de valeur à plat évidente sans logique métier
        -- supplémentaire (à traiter en aval si besoin).
        json_query(raw_json, '$.competences') as competences_json,
        json_query(raw_json, '$.formations') as formations_json,
        json_query(raw_json, '$.langues') as langues_json,
        json_query(raw_json, '$.permis') as permis_json,
        json_query(raw_json, '$.outilsBureautiques')
            as office_tools_json,
        json_query(raw_json, '$.contexteTravail.conditionsExercice')
            as working_conditions_json,
        json_query(raw_json, '$.qualitesProfessionnelles')
            as qualites_professionnelles_json,
        json_query(raw_json, '$.salaire.listeComplements')
            as salary_complements_json,
        json_query(raw_json, '$.origineOffre.partenaires')
            as source_origin_partners_json,

        -- raw_json n'est PAS exposé en sortie : déjà disponible une couche
        -- plus haut (snap_france_travail__offers._raw), via PARSE_JSON(_raw)
        -- en cas de besoin ponctuel. Pas de duplication inutile entre couches.
        _extracted_at,
        _ingested_at,
        dbt_valid_from as _valid_from,
        dbt_valid_to as _valid_to

    from parsed

),

derived as (

    select
        *,

        -- work_location_label suit le plus souvent "<département> - <ville>"
        -- (ex. "77 - Chessy"), avec le cas particulier de la Corse ("2A"/"2B",
        -- pas des chiffres). Certaines offres sortent du format (ex.
        -- "Montréal, QC, Canada") : les deux colonnes restent alors NULL,
        -- work_location_label garde la valeur brute pour inspection.
        -- Calculé depuis work_location_label (déjà extrait ci-dessus), pas
        -- en repiochant dans raw_json.
        regexp_extract(work_location_label, r'^(2[AB]|\d{2,3})\s*-\s*.+$')
            as work_location_department_code,
        regexp_extract(work_location_label, r'^(?:2[AB]|\d{2,3})\s*-\s*(.+)$')
            as work_location_city_raw,

        -- contract_type_label suit le plus souvent "<type> - <N> <unité>"
        -- (ex. "Intérim - 1 Mois") ; le CDI, entre autres, n'a pas de durée
        -- (pas de suffixe). L'unité est capturée telle quelle (pas supposée
        -- "toujours Mois") : si une offre utilise une autre unité un jour,
        -- elle apparaît ici plutôt que d'être silencieusement mal interprétée.
        case
            when regexp_contains(contract_type_label, r'^.+-\s*\d+\s*\S+$')
                then
                    regexp_extract(
                        contract_type_label, r'^(.+?)\s*-\s*\d+\s*\S+$'
                    )
            else contract_type_label
        end as contract_type_label_clean,
        safe_cast(
            regexp_extract(contract_type_label, r'-\s*(\d+)\s*\S+$') as int64
        ) as contract_duration_value,
        regexp_extract(contract_type_label, r'-\s*\d+\s*(\S+)$')
            as contract_duration_unit,

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
            as salary_periodicity,
        safe_cast(
            regexp_extract(
                salary_label, r'de\s+([\d]+(?:\.[\d]+)?)\s*Euros'
            ) as float64
        ) as salary_min,
        safe_cast(
            regexp_extract(
                salary_label, r'à\s+([\d]+(?:\.[\d]+)?)\s*Euros'
            ) as float64
        ) as salary_max,

        -- working_time_detail_label contient parfois deux lignes séparées
        -- par un retour à la ligne (ex. "35H/semaine\nTravail en journée"),
        -- parfois une seule (ex. "Travail en journée" seul, sans heures).
        -- On détecte si la première ligne ressemble à une expression
        -- d'heures ("\dH") ; sinon elle est elle-même le type d'horaire.
        -- working_hours_max prévu pour une éventuelle fourchette
        -- ("20H-25H/semaine") : non observée dans l'échantillon à ce jour,
        -- à vérifier. La périodicité ("semaine") est capturée telle
        -- quelle, pas supposée fixe.
        case
            when
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                then safe_cast(
                    regexp_extract(
                        split(working_time_detail_label, '\n')[safe_offset(0)],
                        r'^(\d+)H'
                    ) as int64
                )
        end as working_hours_min,
        case
            when
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                then safe_cast(
                    regexp_extract(
                        split(working_time_detail_label, '\n')[safe_offset(0)],
                        r'-(\d+)H'
                    ) as int64
                )
        end as working_hours_max,
        case
            when
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                then regexp_extract(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'/(\w+)$'
                )
        end as working_hours_periodicity,
        case
            when
                regexp_contains(
                    split(working_time_detail_label, '\n')[safe_offset(0)],
                    r'^\d+H'
                )
                then split(working_time_detail_label, '\n')[safe_offset(1)]
            else split(working_time_detail_label, '\n')[safe_offset(0)]
        end as working_schedule_type

    from extracted

),

cleaned as (

    select
        * except (work_location_city_raw, company_name),

        -- Les villes arrivent tantôt en majuscules, tantôt en minuscules/
        -- casse mixte selon l'offre. INITCAP standardise en "Première
        -- Lettre Majuscule" par mot. À vérifier sur un échantillon réel
        -- pour les noms composés accentués (ex. "Saint-Étienne") : le
        -- comportement de INITCAP sur les caractères accentués n'est pas
        -- garanti à 100% sans test.
        initcap(work_location_city_raw) as work_location_city,

        -- Attention avec company_name : INITCAP peut dénaturer des sigles
        -- ou des casses volontaires (ex. "SNCF" -> "Sncf", "CIBOX
        -- INTER@CTIVE" -> "Cibox Inter@Ctive"). Accepté comme compromis ;
        -- à vérifier sur un échantillon si ça gêne pour certains cas.
        initcap(company_name) as company_name

    from derived

),

final as (

    select
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

    from cleaned

)

select * from final
