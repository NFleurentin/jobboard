# tap-francetravail

Tap [Meltano](https://meltano.com) / [Singer SDK](https://sdk.meltano.com) qui extrait des données depuis l'API REST de [France Travail](https://francetravail.io).

## Ce que fait ce tap

Le tap interroge l'API REST de France Travail et émet les enregistrements au format [Singer](https://hub.meltano.com/singer/spec) (`SCHEMA`, `RECORD`, `STATE`), utilisables par n'importe quel target Singer (JSONL, Postgres, BigQuery, etc.).

Fonctionnement :

1. **Authentification** : récupération d'un jeton OAuth2 (flux *client credentials*) à partir de `client_id` / `client_secret`.
2. **Appels HTTP** : requêtes `GET` sur les endpoints de l'API avec le jeton en `Authorization: Bearer ...`.
3. **Pagination** : parcours des pages de résultats jusqu'à épuisement.
4. **Émission** : chaque élément retourné est transformé en `RECORD` Singer, selon le schéma de chaque stream.

## Prérequis

- Python 3.12 (version fixée par `.python-version`)
- [uv](https://docs.astral.sh/uv/)
- Un compte sur [francetravail.io](https://francetravail.io) avec une application déclarée et souscrite à l'API voulue, pour obtenir un `client_id` et un `client_secret`

## Installation

```bash
uv sync
```

Cette commande crée l'environnement virtuel et installe les dépendances du projet.

## Qualité du code et tests

```bash
uv run ruff format    # formatage
uv run ruff check     # lint (règles dans pyproject.toml)
uv run mypy           # typage, en mode strict
uv run pytest         # tests unitaires
```

Les tests n'appellent pas l'API : ils s'appuient sur des réponses enregistrées dans `tests/fixtures/`. Ces fichiers sont versionnés dans un dépôt public : les coordonnées de contact et d'agence y sont fictives (`example.com`, `00 00 00 00 00`), à remplacer avant tout ajout d'une réponse réelle.

## Tester le tap

### 1. Créer le fichier de configuration

Crée un fichier `config.json` à la racine du projet :

```json
{
  "client_id": "PAR_mon_application_xxxxxxxx",
  "client_secret": "xxxxxxxxxxxxxxxxxxxxxxxx",
  "search_queries": [
        {
            "keywords": "XXX"
        }
    ]
}
```

| Clé | Obligatoire | Description |
|-----|:-----------:|-------------|
| `client_id` | oui | Identifiant de l'application créée sur francetravail.io. |
| `client_secret` | oui | Secret associé. À ne jamais versionner. |
| `search_queries` | oui | Liste des requêtes de recherche pour l'API France Travail. Chaque élément doit contenir un champ `keywords`. |

### 2. Découvrir les streams disponibles

```bash
uv run tap-francetravail --discover
```

Affiche le **catalogue Singer** (JSON) : la liste des streams et le schéma de chacun. Utile pour vérifier que le tap se charge correctement. Pour le sauvegarder :

```bash
uv run tap-francetravail --discover > catalog.json
```

### 3. Lancer une extraction

L'extraction exige la variable `INGESTED_AT`, l'identifiant du run reporté dans `_ingested_at` sur chaque enregistrement. En usage normal, `run.sh` la reçoit de l'appelant ; pour un test du tap seul, la définir à la main (le tap s'arrête avant tout appel à l'API si elle est absente ou mal formée) :

```bash
export INGESTED_AT=$(date -u +%Y%m%dT%H%M%SZ)
uv run tap-francetravail --config config.json
```

Le tap s'authentifie, appelle l'API et écrit les messages Singer (`SCHEMA`, `RECORD`, `STATE`) sur la sortie standard. Pour inspecter le résultat plus facilement :

```bash
uv run tap-francetravail --config config.json > output.jsonl
```