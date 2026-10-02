# CLAUDE.md — extraction

Projet Meltano qui lance `tap-francetravail` (tap Singer maison, dans `taps/tap-francetravail/`) vers `target-gcs--francetravail` (hérite de `target-gcs`, variante datateer).

## Commandes

```bash
pip install "meltano[gcs]"                      # [gcs] requis pour le state distant
meltano --environment=dev install               # installe le tap en mode éditable (pip_url: -e)
./run.sh                                        # exige GCP_PROJECT_ID, INGESTED_AT, MELTANO_ENVIRONMENT
```

Développement du tap seul : `cd taps/tap-francetravail && uv sync`, puis voir son [README](taps/tap-francetravail/README.md) pour un test avec `config.json` (jamais commité).

## Configuration

- [meltano.yml](meltano.yml) inclut `plugins/**/*.meltano.yml` et `environments/*.meltano.yml`.
- Les requêtes de recherche (`search_queries`) et le bucket cible sont définis par environnement dans `environments/` : liste réduite en dev, complète en prod. Garder les deux fichiers symétriques en structure.
- Identifiants API : `TAP_FRANCETRAVAIL_CLIENT_ID` / `TAP_FRANCETRAVAIL_CLIENT_SECRET` en variables d'environnement.
- Le state Meltano est stocké dans `gs://<projet>-meltano-state/state` (défini par `run.sh`).

## Points d'attention du tap

- **Full-refresh volontaire** : pas de `replication_key`. L'API ne signale pas les offres fermées ; un instantané complet à chaque run permet au snapshot dbt de déduire les fermetures. Ne pas passer en incrémental.
- **Forme des records figée** : `id`, `dateActualisation`, `_raw` (payload complet sérialisé par `json.dumps`), `_extracted_at`, `_ingested_at`. Émettre `_raw` en objet imbriqué réintroduirait le bug `Decimal` non sérialisable du target. Toute modification de cette forme impose de mettre à jour [offers_raw.json](../loading/schemas/france_travail/offers_raw.json) et la source dbt.
- `_ingested_at` est lu depuis la variable `INGESTED_AT` (format `%Y%m%dT%H%M%SZ`) ; le chemin GCS en dépend aussi : `france-travail/offers/ingested_at=<INGESTED_AT>/part-<timestamp>.jsonl`.
- Pagination par `range` (pages de 150) : HTTP 206 signale qu'il reste des pages, et l'API plafonne à **1 150 résultats par requête**. Une requête trop large est tronquée silencieusement : préférer plusieurs requêtes ciblées.
- Chaque entrée de `search_queries` est une partition exécutée indépendamment ; une même offre peut donc sortir plusieurs fois (le dédoublonnage se fait dans dbt).
