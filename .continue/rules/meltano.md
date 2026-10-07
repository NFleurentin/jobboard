---
paths:
  - "extraction/**"
globs:
  - "extraction/**"
---

# Règles Meltano

Ces règles couvrent l'extraction avec Meltano : configuration, plugins, secrets, state, tap France Travail et commandes à risque. Le code Python du tap suit aussi `python.md`.

## Périmètre

- Le projet Meltano (`extraction/`) lance `tap-francetravail` (tap Singer maison, dans `taps/tap-francetravail/`) vers `target-gcs--francetravail` (hérite de `target-gcs`, variante datateer).
- La réponse de l'API n'est pas interprétée : elle est écrite telle quelle dans un champ `_raw` du fichier JSONL. Ajouter ou typer un champ métier se fait dans le staging dbt, jamais dans le tap.
- Les mappers et `stream_maps` sont réservés au technique (masquer une donnée personnelle, écarter un champ).

## Configuration

- `meltano.yml` ne contient que les paramètres de projet et `include_paths` (`plugins/**/*.meltano.yml` et `environments/*.meltano.yml`). Aucun plugin, job ou environnement n'y est déclaré.
- Un fichier par plugin sous `plugins/taps/` ou `plugins/loaders/`, nommé comme le plugin, avec le suffixe `--<variant>` quand le variant doit être explicite.
- `environments/dev.meltano.yml` et `prod.meltano.yml` ne contiennent que ce qui diffère : le bucket cible et `search_queries` (liste réduite en dev, complète en prod). Garder les deux fichiers symétriques en structure.
- Après une commande qui écrit dans la configuration (`meltano add`, `meltano config ... set`), vérifier avec `git diff` dans quel fichier elle a écrit, et déplacer le contenu au bon endroit si elle a touché `meltano.yml`.
- Les fichiers `.lock` sous `plugins/` sont versionnés et ne se modifient jamais à la main.

## Commandes

```bash
uv sync --frozen && source .venv/bin/activate   # Meltano figé par pyproject.toml et uv.lock
meltano --environment=dev install               # installe le tap en mode éditable (pip_url: -e)
./run.sh                                        # seul point d'entrée d'une extraction
```

Développement du tap seul : `cd taps/tap-francetravail && uv sync`, puis voir `extraction/taps/tap-francetravail/README.md` pour un test avec `config.json` (jamais commité).

## Plugins

- Version fixée dans `pip_url` (numéro, tag ou SHA de commit pour une installation depuis Git), `variant` explicite.
- Dépendances transitives figées par `-c constraints/<plugin>.txt` dans `pip_url`. Ces fichiers sont générés, jamais édités à la main : `uv export --frozen --no-dev --no-emit-project --no-hashes --no-header -o ../../constraints/tap-francetravail.txt` depuis le tap, `uv pip compile` pour un plugin externe. Les régénérer à chaque changement de version.
- Sélection explicite des streams et des champs avec `select`, jamais `*.*`.
- Méthode et clé de réplication dans le fichier du plugin (`metadata`), pas dans les fichiers d'environnement.
- Chaque setting d'un plugin personnalisé déclare son `kind`, et `sensitive: true` pour un secret.

## Secrets

- Aucun secret dans un `*.meltano.yml`. Variables d'environnement `<PLUGIN>_<SETTING>` (`TAP_FRANCETRAVAIL_CLIENT_SECRET`) : `.env` non versionné en local, secrets GitHub en CI. `.env.example` liste les variables attendues, sans valeur.
- Accès à GCS par Application Default Credentials en local et Workload Identity Federation en CI.

## State

L'extraction France Travail est en full-refresh : son state ne sert pas de point de reprise. `run.sh` fixe quand même le backend, pour les futurs streams incrémentaux.

- Le state est sur GCS (`gs://<project_id>-meltano-state/state`), via `MELTANO_STATE_BACKEND_URI` exportée par `run.sh`, et dans aucun `*.meltano.yml`.
- Une commande `meltano` lancée sans cette variable utilise en silence la base SQLite locale sous `.meltano/` : un `meltano run` direct repart de zéro, et `meltano state list` affiche un state vide.
- L'identifiant de state inclut l'environnement, le couple tap-target et `--state-id-suffix` : renommer un plugin ou changer ce suffixe fait repartir l'extraction de zéro.
- Ne jamais modifier le state pour contourner une erreur d'extraction : corriger la cause.

## Exécution

- Toute extraction se lance par `./run.sh`, en local comme en CI. Il exige `MELTANO_ENVIRONMENT`, `GCP_PROJECT_ID` et `INGESTED_AT`, fixe le backend du state et appelle `meltano run <tap> <loader>`. Pas de `meltano elt` ni `meltano el`.
- Aucun job déclaré pour l'instant. Un futur job est nommé `<tap>-to-<target>` et déclaré dans `jobs/jobs.meltano.yml` (à réactiver dans `include_paths`).
- La déduplication est assurée dans dbt, avant le snapshot : un run relancé après un échec ne crée pas de doublon en aval.

## Tap personnalisé

- Deux environnements Python coexistent : celui du tap (`uv`, sous `taps/tap-francetravail/`) sert au développement et aux tests ; celui créé par Meltano sous `.meltano/` sert à l'exécution. Une dépendance ajoutée au tap impose de réinstaller le plugin dans Meltano.
- Chaque stream déclare un schéma typé et ses `primary_keys`. Un changement de schéma ou de clé est un changement cassant pour dbt.
- Nouvelles tentatives avec attente croissante et plafond. Aucun secret ni donnée personnelle dans les logs.
- Les tests du tap n'appellent pas l'API réelle : ils s'appuient sur des réponses enregistrées.

## Tap France Travail

- **Full-refresh volontaire** : pas de `replication_key`. L'API ne signale pas les offres fermées ; un instantané complet à chaque run permet au snapshot dbt de déduire les fermetures. Ne pas passer en incrémental.
- **Forme des records figée** : `id`, `dateActualisation`, `_raw` (payload complet sérialisé par `json.dumps`), `_extracted_at`, `_ingested_at`. Émettre `_raw` en objet imbriqué réintroduirait le bug `Decimal` non sérialisable du target. Toute modification de cette forme impose de mettre à jour `loading/schemas/france_travail/offers_raw.json` et la source dbt.
- `_ingested_at` est lu depuis la variable `INGESTED_AT` (format `%Y%m%dT%H%M%SZ`) ; le chemin GCS en dépend aussi : `france-travail/offers/ingested_at=<INGESTED_AT>/part-<timestamp>.jsonl`.
- Pagination par `range` (pages de 150) : HTTP 206 signale qu'il reste des pages, et l'API plafonne à **3 150 résultats par requête** (index de début ≤ 3000, index de fin ≤ 3149). Une requête dont le total (`Content-Range`) dépasse ce plafond fait échouer le run (`FatalAPIError`) : la découper en requêtes plus ciblées.
- Chaque entrée de `search_queries` est une partition exécutée indépendamment ; une même offre peut donc sortir plusieurs fois, d'où la déduplication dans dbt.

## Garde-fous pour l'agent

La syntaxe de plusieurs commandes a changé entre les versions majeures de Meltano. Vérifier avec `meltano <commande> --help` avant de proposer une commande, plutôt que de reproduire une syntaxe de mémoire.

Autorisé sans confirmation : `meltano --version`, toute commande avec `--help`, la lecture des fichiers de configuration, et `meltano state list` sur dev avec `MELTANO_STATE_BACKEND_URI` définie.

Demander une confirmation explicite avant :

- `./run.sh` et `meltano invoke` sur dev : ils appellent l'API source, consomment du quota et écrivent dans GCS ;
- `meltano install`, l'ajout, le retrait ou le changement de version d'un plugin ;
- toute commande qui écrit dans la configuration, et toute modification de `select` ou de `metadata` ;
- toute modification de `search_queries` : elle change le périmètre extrait, et le snapshot dbt marque comme closes les offres qui en sortent ;
- `--full-refresh`, et toute modification du state sur dev.

Interdit :

- toute commande visant l'environnement prod depuis le poste local ;
- `meltano run` lancé directement, sans passer par `run.sh` ;
- modifier ou supprimer le state de prod ;
- afficher des secrets : option `--unsafe` de `meltano config`, export de la configuration résolue d'un plugin, contenu de `.env` ;
- écrire un secret dans un fichier versionné ;
- modifier `project_id` ou réactiver l'envoi de statistiques d'usage.

Si une extraction échoue : lire le log, identifier si l'erreur vient du tap, du target ou de la configuration, et expliquer la cause avant de proposer un correctif.
