---
paths:
  - "**/*.sh"
globs:
  - "**/*.sh"
---

# Règles Bash

Ces règles couvrent les scripts shell du dépôt (`extraction/run.sh`, `loading/load.sh`) : structure, variables, robustesse et commandes à risque.

## Périmètre

- Un script Bash est un point d'entrée mince : il vérifie son environnement, puis enchaîne des appels de CLI (`meltano`, `bq`, `gcloud`).
- Dès qu'il faut des boucles sur des données, du parsing ou de la gestion d'erreurs fine, écrire du Python.
- Un même script sert en local et en CI : il ne contient aucune logique propre à l'un des deux.

## En-tête

- Shebang `#!/usr/bin/env bash`, puis `set -euo pipefail` : arrêt à la première erreur (`-e`), erreur sur une variable non définie (`-u`), échec d'un pipeline si l'une de ses commandes échoue (`pipefail`).
- Sans ces options, un script continue après une erreur et se termine avec un code de retour à zéro : la CI affiche un succès sur un chargement raté.

## Variables

- Les variables requises sont vérifiées en tête de script avec `: "${VAR:?message}"`, avant toute action.
- Le contrat des scripts : `GCP_PROJECT_ID`, `INGESTED_AT` et `MELTANO_ENVIRONMENT` sont fournis par l'appelant. Un script ne choisit jamais son environnement et ne donne aucune valeur par défaut à ces variables.
- Toujours entre guillemets doubles (`"$VAR"`), avec accolades quand la variable est accolée à du texte (`"${GCP_PROJECT_ID}-raw"`).
- Majuscules pour les variables d'environnement, minuscules pour les variables internes, `local` dans les fonctions, `readonly` pour les constantes.
- Dans un message entre guillemets doubles, `$(...)` est exécuté. Pour afficher une commande à titre d'exemple, échapper le dollar (`\$(...)`).

## Écriture

- Chemins relatifs au script (`"$(dirname "$0")"`), jamais au répertoire courant.
- Options longues (`--project_id`) plutôt que courtes, une option par ligne quand la commande est longue.
- `$(...)` et non des backticks, `[[ ... ]]` et non `[ ... ]`, pas de `eval`, pas d'analyse de la sortie de `ls`.
- Fichiers temporaires créés avec `mktemp` et supprimés par un `trap ... EXIT`.
- Un message final résume ce qui a été fait (objet, run, projet). Les erreurs vont sur la sortie d'erreur.
- Messages destinés à l'utilisateur en français, comme dans les scripts existants.

## Sécurité

- Aucun secret en argument de commande ni dans un `echo` : les secrets passent par l'environnement.
- Pas de `set -x` dans un script qui manipule des secrets : chaque commande serait écrite dans les logs avec ses valeurs.
- Toute suppression qui dépend d'une variable est protégée contre la valeur vide (`"${DIR:?}"`).

## Qualité

- `shellcheck` passe sans avertissement. Une exclusion (`# shellcheck disable=...`) porte sa justification sur la même ligne.
- Les scripts sont exécutables et portent l'extension `.sh`.

## Garde-fous pour l'agent

Autorisé sans confirmation : `shellcheck`, `bash -n` (vérification de syntaxe sans exécution).

Avant d'exécuter un script : afficher `GCP_PROJECT_ID` et `MELTANO_ENVIRONMENT`, et vérifier qu'ils désignent dev.

Demander une confirmation explicite avant d'exécuter `run.sh` ou `load.sh` sur dev : ils appellent une API externe et écrivent dans GCS et BigQuery.

Interdit :

- exécuter un script avec les variables de production depuis le poste local ;
- retirer `set -euo pipefail`, ou masquer une erreur avec `|| true` ;
- ajouter une valeur par défaut qui désigne un environnement ;
- exécuter un script téléchargé sans relecture (`curl ... | bash`).
