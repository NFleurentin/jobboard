---
paths:
  - "extraction/**"
globs:
  - "extraction/**"
---

# Règles Meltano

Ces règles couvrent l'extraction et le chargement avec Meltano : organisation de la configuration, plugins, secrets, state, tap France Travail et commandes à risque. Le code Python du tap suit aussi `python.md`.

## Périmètre

- Le projet Meltano lance `tap-francetravail` (tap Singer maison, dans `taps/tap-francetravail/`) vers `target-gcs--francetravail` (hérite de `target-gcs`, variante datateer).
- Meltano fait l'extraction et le chargement (EL). La réponse de l'API n'est pas interprétée : elle est écrite telle quelle dans un champ `_raw` du fichier JSONL, accompagnée de champs techniques.
- Le format de sortie est donc stable : ajouter ou typer un champ métier se fait dans le staging dbt, jamais dans le tap.
- Aucune transformation métier dans Meltano : elle se fait dans dbt. Les mappers et `stream_maps` sont réservés au technique (masquer une donnée personnelle, écarter un champ).

## Structure de la configuration

Le projet Meltano est dans `extraction/`.

```text
run.sh                           # point d'entrée unique des extractions
meltano.yml                      # paramètres du projet et include_paths, rien d'autre
environments/
├── dev.meltano.yml
└── prod.meltano.yml
jobs/                            # vide pour l'instant
plugins/
├── taps/<tap>.meltano.yml       # un fichier par plugin
└── loaders/<loader>--<variant>.meltano.yml
taps/
└── tap-francetravail/           # code du tap, avec son propre environnement uv
```

- `meltano.yml` ne contient que les paramètres de projet et `include_paths` (`plugins/**/*.meltano.yml` et `environments/*.meltano.yml`). Aucun plugin, job ou environnement n'y est déclaré.
- Un fichier par plugin, nommé comme le plugin, avec le suffixe `--<variant>` quand le variant doit être explicite.
- Un plugin, un job ou un environnement n'est déclaré qu'une seule fois, dans un seul fichier.
- Les fichiers d'environnement ne contiennent que ce qui diffère entre dev et prod : le bucket cible et les requêtes de recherche (`search_queries`, liste réduite en dev, complète en prod). La configuration commune reste dans le fichier du plugin. Garder les deux fichiers symétriques en structure.
- Après une commande qui écrit dans la configuration (`meltano add`, `meltano config ... set`), vérifier avec `git diff` dans quel fichier elle a écrit, et déplacer le contenu au bon endroit si elle a touché `meltano.yml`.
- Les fichiers `.lock` générés sous `plugins/` sont versionnés et ne se modifient jamais à la main. `.meltano/` n'est jamais versionné.

## Commandes

```bash
pip install "meltano[gcs]"                      # [gcs] requis pour le state distant
meltano --environment=dev install               # installe le tap en mode éditable (pip_url: -e)
./run.sh                                        # seul point d'entrée d'une extraction
```

Développement du tap seul : `cd taps/tap-francetravail && uv sync`, puis voir `extraction/taps/tap-francetravail/README.md` pour un test avec `config.json` (jamais commité).

## Plugins

- Fixer la version de chaque plugin dans `pip_url` : numéro de version, ou tag ou SHA de commit pour une installation depuis Git. Une URL Git sans référence suit la branche par défaut : l'installation n'est plus reproductible et le code exécuté peut changer sans relecture.
- Déclarer `variant` explicitement.
- Sélection explicite des streams et des champs avec `select`. Ne pas tout extraire par défaut (`*.*`) : chaque champ inutile coûte en stockage, en temps et en exposition de données personnelles.
- La méthode de réplication et la clé de réplication se déclarent dans le fichier du plugin (`metadata`), pas dans les fichiers d'environnement.
- Chaque setting d'un plugin personnalisé est déclaré avec son `kind`, et `sensitive: true` pour un secret : Meltano le masque alors dans ses sorties.

## Secrets

- Aucun secret dans un fichier `*.meltano.yml` : le dépôt est public.
- Les secrets passent par des variables d'environnement nommées `<PLUGIN>_<SETTING>` en majuscules (`TAP_FRANCETRAVAIL_CLIENT_SECRET`) : fichier `.env` non versionné en local, secrets GitHub ou Secret Manager en CI.
- Un fichier `.env.example` versionné liste les variables attendues, sans valeur.
- Accès à GCS par Application Default Credentials en local et Workload Identity Federation en CI. Aucun chemin de fichier de clé dans la configuration.

## State

L'extraction France Travail est en full-refresh (voir « Tap France Travail ») : son state ne sert pas de point de reprise. Les règles ci-dessous valent pour tout stream incrémental à venir, et `run.sh` fixe quand même le backend GCS.

Le state mémorise où chaque extraction incrémentale s'est arrêtée. C'est l'équivalent d'un high-water mark de chargement : le perdre force une reprise complète, le fausser fait sauter ou rejouer des données.

- Le state est stocké sur GCS, dans `gs://<project_id>-meltano-state/state`. Chaque environnement a son projet GCP, donc son bucket.
- L'URI est définie par la variable `MELTANO_STATE_BACKEND_URI`, exportée par `run.sh`. Elle n'apparaît dans aucun fichier `*.meltano.yml`.
- Une commande `meltano` lancée sans cette variable utilise en silence la base SQLite locale sous `.meltano/` : un `meltano run` direct repart de zéro, et `meltano state list` affiche un state vide.
- L'identifiant de state inclut l'environnement, le couple tap-target et le suffixe passé par `--state-id-suffix`. Renommer un plugin ou changer ce suffixe change l'identifiant et fait repartir l'extraction de zéro.
- Ne jamais modifier le state pour contourner une erreur d'extraction : corriger la cause.
- `--full-refresh` ignore le state. Avant de l'utiliser, évaluer le volume rechargé, le quota d'API consommé et les doublons créés dans la cible.

## Jobs et exécution

- Toute extraction se lance par `./run.sh`, en local comme en CI. Le script vérifie les variables requises, fixe le backend du state et appelle `meltano run`.
- Ne pas utiliser `meltano elt` ni `meltano el`.
- Aucun job n'est déclaré pour l'instant : `run.sh` appelle `meltano run <tap> <loader>`. Un futur job est nommé `<tap>-to-<target>` et déclaré dans `jobs/jobs.meltano.yml` (à réactiver dans `include_paths`).
- L'environnement est toujours explicite : `run.sh` exige `MELTANO_ENVIRONMENT`, ainsi que `GCP_PROJECT_ID` et `INGESTED_AT`.
- Un job relancé après un échec ne doit pas produire de doublons en aval : la déduplication est assurée dans dbt, avant le snapshot, sur la clé primaire du stream.

## Tap personnalisé

- Deux environnements Python coexistent : celui du tap (`uv`, sous `taps/tap-francetravail/`) sert au développement et aux tests ; celui créé par Meltano sous `.meltano/` sert à l'exécution. Une dépendance ajoutée au tap impose de réinstaller le plugin dans Meltano.
- Chaque stream déclare un schéma typé, ses `primary_keys` et, s'il est incrémental, sa `replication_key`. Un changement de schéma ou de clé est un changement cassant pour dbt.
- Respecter les quotas de l'API : pagination, attente croissante sur les erreurs transitoires et les réponses de limitation de débit, jamais de boucle de nouvelles tentatives sans plafond.
- Aucun secret ni donnée personnelle dans les logs du tap.
- Les tests du tap n'appellent pas l'API réelle : ils s'appuient sur des réponses enregistrées.

## Tap France Travail

- **Full-refresh volontaire** : pas de `replication_key`. L'API ne signale pas les offres fermées ; un instantané complet à chaque run permet au snapshot dbt de déduire les fermetures. Ne pas passer en incrémental.
- **Forme des records figée** : `id`, `dateActualisation`, `_raw` (payload complet sérialisé par `json.dumps`), `_extracted_at`, `_ingested_at`. Émettre `_raw` en objet imbriqué réintroduirait le bug `Decimal` non sérialisable du target. Toute modification de cette forme impose de mettre à jour `loading/schemas/france_travail/offers_raw.json` et la source dbt.
- `_ingested_at` est lu depuis la variable `INGESTED_AT` (format `%Y%m%dT%H%M%SZ`) ; le chemin GCS en dépend aussi : `france-travail/offers/ingested_at=<INGESTED_AT>/part-<timestamp>.jsonl`.
- Pagination par `range` (pages de 150) : HTTP 206 signale qu'il reste des pages, et l'API plafonne à **1 150 résultats par requête**. Une requête trop large est tronquée silencieusement : préférer plusieurs requêtes ciblées.
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
