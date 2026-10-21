-- Setup du profilage (DuckDB CLI) : définit les vues lues par les requêtes
-- de ce dossier, seul endroit qui connaît l'emplacement et le format du brut.
--
-- Le brut est téléchargé hors du dépôt (il contient des contacts), dans une
-- copie locale qui reproduit l'arborescence du bucket. La racine de cette
-- copie est passée par la variable d'environnement PROFILING_DATA_DIR
-- (getenv n'existe que dans le CLI) ; le sous-chemin de la source est fixé
-- ici.
--
-- Chaque ligne JSONL est l'enveloppe du tap : id, dateActualisation,
-- _extracted_at, _ingested_at, et l'offre complète dans _raw (STRING).
-- _raw est exposé en JSON : les champs se lisent par raw ->> '$.chemin'.

-- Une ligne par offre et par run : sert à mesurer les réouvertures.
CREATE OR REPLACE VIEW raw_offer_runs AS
SELECT
    id AS offer_id,
    _ingested_at AS ingested_at,
    _raw::JSON AS raw
FROM read_json(getenv('PROFILING_DATA_DIR') || '/france-travail/offers/*/*.jsonl');

-- Dernière version de chaque offre : sert aux distributions, pour qu'une
-- offre présente dans N runs ne pèse pas N fois.
CREATE OR REPLACE VIEW raw_offers AS
SELECT *
FROM raw_offer_runs
QUALIFY row_number() OVER (PARTITION BY offer_id ORDER BY ingested_at DESC) = 1;
