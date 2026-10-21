# Profilage des sources

Requêtes **DuckDB** (pas BigQuery) qui profilent les fichiers bruts d'une source, avant toute transformation, pour fonder les règles des modèles sur les données réelles. Les conclusions sont reportées dans la documentation de conception ; ces requêtes servent à les rejouer.

Un sous-dossier par source et par flux (`<source>/<flux>/`), avec son propre README : téléchargement, vues, résultats.

| Dossier | Source |
|---|---|
| [france_travail/offers/](france_travail/offers/) | Offres France Travail |

## Données

Les fichiers bruts peuvent contenir des données personnelles : ils sont téléchargés **hors du dépôt**, dans une copie locale qui reproduit l'arborescence du bucket, et supprimés une fois le profilage terminé. Le téléchargement depuis la prod est lancé à la main par le propriétaire du dépôt.

## Lancement

DuckDB tourne en mémoire : les vues disparaissent à la fin de la session, et `-init` rejoue le `00_setup.sql` du dossier à chaque lancement (il ne crée que des vues, sans charger de données).

```bash
export PROFILING_DATA_DIR=~/Documents/data/jobboard
cd ~/GitHub/jobboard/docs/profiling/<source>/<flux>
duckdb -init 00_setup.sql                 # session interactive
duckdb -init 00_setup.sql -f 01_xxx.sql   # une requête
```

`PROFILING_DATA_DIR` désigne la racine de la copie locale, commune à toutes les sources ; chaque `00_setup.sql` y ajoute son sous-chemin.

Les sorties larges se lisent en CSV, écrit hors du dépôt : `duckdb -init 00_setup.sql -csv -f 01_xxx.sql > ~/Documents/data/jobboard/<fichier>.csv`.

## Données personnelles

Les valeurs des champs personnels sont masquées par défaut, seuls leurs motifs s'affichent. `PROFILING_SHOW_SENSITIVE=1` les affiche, pour une lecture locale uniquement : ne pas les recopier dans la documentation.
