# tap-france-travail

Tap [Meltano](https://meltano.com) / [Singer SDK](https://sdk.meltano.com) qui extrait des données depuis l'API REST de [France Travail](https://francetravail.io).

## Ce que fait ce tap

Le tap interroge l'API REST de France Travail et émet les enregistrements au format [Singer](https://hub.meltano.com/singer/spec) (`SCHEMA`, `RECORD`, `STATE`), utilisables par n'importe quel target Singer (JSONL, Postgres, BigQuery, etc.).

Fonctionnement :

1. **Authentification** : récupération d'un jeton OAuth2 (flux *client credentials*) à partir de `client_id` / `client_secret`.
2. **Appels HTTP** : requêtes `GET` sur les endpoints de l'API avec le jeton en `Authorization: Bearer ...`.
3. **Pagination** : parcours des pages de résultats jusqu'à épuisement.
4. **Émission** : chaque élément retourné est transformé en `RECORD` Singer, selon le schéma de chaque stream.

## Prérequis

- Python 3.9+
- [uv](https://docs.astral.sh/uv/)
- Un compte sur [francetravail.io](https://francetravail.io) avec une application déclarée et souscrite à l'API voulue, pour obtenir un `client_id` et un `client_secret`

## Installation

```bash
uv sync
```

Cette commande crée l'environnement virtuel et installe les dépendances du projet.

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
uv run tap-france-travail --discover
```

Affiche le **catalogue Singer** (JSON) : la liste des streams et le schéma de chacun. Utile pour vérifier que le tap se charge correctement. Pour le sauvegarder :

```bash
uv run tap-france-travail --discover > catalog.json
```

### 3. Lancer une extraction

```bash
uv run tap-france-travail --config config.json
```

Le tap s'authentifie, appelle l'API et écrit les messages Singer (`SCHEMA`, `RECORD`, `STATE`) sur la sortie standard. Pour inspecter le résultat plus facilement :

```bash
uv run tap-france-travail --config config.json > output.jsonl
```