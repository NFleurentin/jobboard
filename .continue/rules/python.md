---
paths:
  - "**/*.py"
  - "**/pyproject.toml"
globs:
  - "**/*.py"
  - "**/pyproject.toml"
---

# Règles Python

Ces règles couvrent le code Python du dépôt (tap Meltano, outillage) et ses tests. Les conventions courantes (PEP 8, idiomes, `logging`, `pytest`) s'appliquent sans être répétées ici.

## Périmètre

- Python sert à l'extraction, à l'orchestration et à l'outillage. Les transformations de données se font en SQL dans dbt, pas en mémoire avec pandas.
- Avant d'écrire un script, vérifier qu'un plugin Meltano, une macro dbt ou une commande CLI ne couvre pas déjà le besoin.

## Environnement et dépendances

- `uv` gère la version de Python, l'environnement virtuel et les dépendances. `pyproject.toml` est la seule source de vérité : pas de `requirements.txt`.
- `uv.lock` et `.python-version` sont versionnés, `.venv/` jamais.
- Ne jamais installer dans le Python du système : sur Fedora, il appartient à `dnf`.
- Préférer la bibliothèque standard, et sinon un paquet maintenu et largement utilisé.

## Style

- `ruff format` et `ruff check`, configurés dans `pyproject.toml`. Type hints sur toutes les signatures, vérifiés par `mypy`.
- Identifiants en anglais, docstrings et commentaires en français. Les commentaires en anglais hérités du template du tap ne sont pas réécrits sans autre raison.
- La configuration vient des variables d'environnement ou des arguments, jamais de valeurs en dur (projet, dataset, chemins).
- Tout script est idempotent, et se termine avec un code de retour non nul en cas d'échec.

## Accès aux données et à GCP

- Requêtes paramétrées, jamais de SQL construit par concaténation ou f-string avec une valeur externe : l'équivalent des bind variables en PL/SQL.
- Authentification par Application Default Credentials, jamais par un fichier de clé.
- Timeout explicite sur tout appel réseau, nouvelle tentative avec attente croissante sur les erreurs transitoires uniquement.
- Dry run avant d'exécuter une requête BigQuery sur un volume inconnu.
- Aucun secret ni donnée personnelle dans les logs.

## Tests

- `pytest`, dans `tests/`. Les tests unitaires n'appellent ni le réseau ni GCP.
- Tout correctif de bug s'accompagne d'un test qui échouait avant et passe après.

## Garde-fous pour l'agent

Autorisé sans confirmation : `uv sync`, `uv run ruff format`, `uv run ruff check`, `uv run mypy`, `uv run pytest`.

Niveau intermédiaire en Python, avancé en PL/SQL :

- écrire du Python idiomatique (compréhensions, unpacking, context managers) sans l'expliquer : ces bases sont acquises ;
- expliquer à leur première utilisation les notions avancées (décorateurs paramétrés, générateurs et `yield`, `async`, typage avancé comme `Protocol` ou les génériques, dataclasses, fixtures `pytest`), avec le parallèle PL/SQL quand il existe et l'endroit où l'analogie casse ;
- expliquer les choix d'outillage et de structure (packaging, `pyproject.toml`, configuration de `ruff` et `mypy`), moins familiers que le langage lui-même ;
- avancer par étapes relisibles : une fonction et son test, pas un script complet d'un bloc.

Demander une confirmation explicite avant :

- d'ajouter, retirer ou mettre à jour une dépendance, en justifiant le choix du paquet ;
- de changer la version de Python ou la configuration de `ruff` et `mypy` ;
- d'exécuter un script qui écrit dans GCP, appelle une API externe ou peut générer un coût.

Interdit :

- `pip install` hors de l'environnement du projet, `sudo pip`, `--break-system-packages` ;
- ajouter `# noqa` ou `# type: ignore`, ou désactiver une règle, sans justification écrite sur la même ligne ;
- supprimer ou affaiblir un test pour le faire passer ;
- `eval`, `exec`, `subprocess` avec `shell=True` sur une valeur variable, `yaml.load`, `pickle` sur une donnée non maîtrisée ;
- exécuter du code téléchargé sans relecture (`curl ... | python`).
