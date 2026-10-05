---
paths:
  - "**/*.py"
  - "**/pyproject.toml"
globs:
  - "**/*.py"
  - "**/pyproject.toml"
---

# Règles Python

Ces règles couvrent le code Python du dépôt : scripts d'outillage, extracteurs ou utilitaires autour de Meltano et dbt, et leurs tests.

## Périmètre

- Python sert à l'extraction, à l'orchestration et à l'outillage. Les transformations de données se font en SQL dans dbt.
- Ne pas charger des données en mémoire (pandas) pour faire ce que BigQuery fait en SQL : le traitement doit rester au plus près des données.
- Avant d'écrire un script, vérifier qu'un plugin Meltano, une macro dbt ou une commande CLI ne couvre pas déjà le besoin.

## Environnement et dépendances

- `uv` gère la version de Python, l'environnement virtuel et les dépendances. `pyproject.toml` est la seule source de vérité : pas de `requirements.txt` maintenu à la main.
- `uv.lock` et `.python-version` sont versionnés : mêmes versions pour tous et pour la CI. `.venv/` ne l'est jamais.
- Commandes : `uv add <paquet>` pour ajouter, `uv add --dev <paquet>` pour un outil de développement, `uv sync` pour installer, `uv run <commande>` pour exécuter dans l'environnement du projet.
- Ne jamais installer dans le Python du système (`pip install` hors environnement, `sudo pip`) : sur Fedora, il appartient à `dnf` et des outils système en dépendent.
- Chaque dépendance ajoutée est une surface d'attaque et une charge de maintenance. Préférer la bibliothèque standard, et sinon un paquet maintenu et largement utilisé.

## Style

- `ruff format` pour la mise en forme et `ruff check` pour le lint, configurés dans `pyproject.toml`. On ne discute pas le style, on applique l'outil.
- Nommage PEP 8 : `snake_case` pour les fonctions, variables et modules, `PascalCase` pour les classes, `UPPER_SNAKE_CASE` pour les constantes.
- Identifiants en anglais, docstrings et commentaires en français. Un commentaire explique pourquoi, pas ce que fait la ligne. Les commentaires en anglais hérités du template du tap ne sont pas réécrits sans autre raison.
- Type hints sur toutes les signatures de fonctions, vérifiés par `mypy`. Ils documentent le contrat et détectent des erreurs avant l'exécution.
- Docstring sur chaque fonction publique : ce qu'elle fait, ses arguments, ce qu'elle retourne, les exceptions levées.
- Préférer `pathlib` à `os.path`, les f-strings aux concaténations, et `with` pour toute ressource à fermer (fichier, connexion).
- Pièges classiques à éviter : argument par défaut mutable (`def f(items=[])`), `except:` nu, `import *`.

## Structure du code

- La logique vit dans des fonctions importables et testables. Le point d'entrée se limite à `if __name__ == "__main__":`, qui lit les arguments et appelle ces fonctions.
- Aucun effet de bord à l'import d'un module : pas de connexion, de requête ni de lecture de fichier au niveau global.
- Séparer la logique (fonctions pures : données en entrée, données en sortie) des entrées-sorties (réseau, fichiers, BigQuery). La première se teste sans infrastructure.
- La configuration vient des variables d'environnement ou des arguments, jamais de valeurs en dur (projet, dataset, chemins).
- Tout script est idempotent : le relancer après un échec ne duplique pas les données et ne laisse pas un état partiel.

## Accès aux données et à GCP

- Requêtes paramétrées, jamais de SQL construit par concaténation ou f-string avec une valeur externe. C'est l'équivalent des bind variables en PL/SQL, pour les mêmes raisons : injection et lisibilité.
- Authentification par Application Default Credentials, jamais par un fichier de clé référencé dans le code.
- Timeout explicite sur tout appel réseau, et nouvelle tentative avec attente croissante sur les erreurs transitoires uniquement.
- Estimer le coût d'une requête BigQuery (dry run) avant de l'exécuter depuis un script sur un volume inconnu.

## Erreurs et journalisation

- Intercepter des exceptions précises, au niveau où l'on sait quoi en faire. Ne jamais avaler une exception en silence.
- Un script en échec se termine avec un code de retour non nul : c'est ce que lisent la CI et l'orchestrateur.
- Utiliser le module `logging`, pas `print`. Les niveaux (`INFO`, `WARNING`, `ERROR`) permettent de filtrer sans modifier le code.
- Aucun secret ni donnée personnelle dans les logs.

## Tests

- `pytest`, dans un répertoire `tests/` qui reprend l'arborescence du code. Nom des tests : `test_<comportement_attendu>`.
- Les tests unitaires n'appellent ni le réseau ni GCP : ils portent sur la logique, avec des données d'exemple.
- Tout correctif de bug s'accompagne d'un test qui échouait avant et passe après.
- La couverture est un indicateur, pas un objectif : un test sans assertion utile ne vaut rien.

## Sécurité

- Aucun secret dans le code ni dans les valeurs par défaut. Les lire depuis l'environnement ou Secret Manager. `.env` n'est jamais versionné.
- Pas de `eval` ni `exec`. Pas de `subprocess` avec `shell=True` sur une valeur variable : passer la commande sous forme de liste.
- `yaml.safe_load` et jamais `yaml.load`. Ne jamais désérialiser avec `pickle` une donnée d'origine non maîtrisée.

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
- exécuter du code téléchargé sans relecture (`curl ... | python`).
