# Profilage du brut France Travail

Requêtes **DuckDB** (pas BigQuery) qui profilent les JSONL bruts du bucket, avant toute transformation, pour trancher les règles de [offers_star_schema.md](../offers_star_schema.md) (issue #141). Les conclusions sont reportées dans ce document ; ces requêtes servent à les rejouer.

## Données

Les JSONL contiennent des coordonnées de contact : ils sont téléchargés **hors du dépôt** et supprimés une fois le profilage terminé. Le téléchargement depuis la prod est lancé à la main par le propriétaire du dépôt.

```bash
gcloud storage cp -r gs://jobboard-prod-3b375b-raw/france-travail/offers \
  ~/Documents/data/jobboard/france-travail/
```

## Lancement

DuckDB tourne en mémoire : les vues disparaissent à la fin de la session, et `-init` rejoue [00_setup.sql](00_setup.sql) à chaque lancement (il ne crée que des vues, sans charger de données).

```bash
export PROFILING_DATA_DIR=~/Documents/data/jobboard/france-travail/offers
cd ~/GitHub/jobboard/docs/profiling
duckdb -init 00_setup.sql                 # session interactive
duckdb -init 00_setup.sql -f 01_xxx.sql   # une requête
```

`PROFILING_DATA_DIR` désigne le dossier qui contient les `ingested_at=<run>/`, pas un run isolé.

## Vues

| Vue | Grain | Usage |
|---|---|---|
| `raw_offer_runs` | une ligne par offre et par run | réouvertures |
| `raw_offers` | dernière version de chaque offre | distributions |

L'offre complète est dans la colonne `raw` (JSON) : `raw ->> '$.entreprise.nom'`.
