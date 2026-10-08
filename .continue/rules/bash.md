---
paths:
  - "**/*.sh"
globs:
  - "**/*.sh"
---

# Règles Bash

Ces règles couvrent les scripts shell du dépôt (`extraction/run.sh`). Les bonnes pratiques courantes (guillemets, `[[ ]]`, `$(...)`, `mktemp` et `trap`, pas d'`eval`) s'appliquent sans être répétées ici.

## Principes

- Un script Bash est un point d'entrée mince : il vérifie son environnement, puis enchaîne des appels de CLI (`meltano`, `bq`, `gcloud`). Dès qu'il faut des boucles sur des données ou du parsing, écrire du Python.
- Un même script sert en local et en CI : il ne contient aucune logique propre à l'un des deux.
- Shebang `#!/usr/bin/env bash`, puis `set -euo pipefail`. Sans lui, la CI afficherait un succès sur un chargement raté.

## Variables

- Le contrat des scripts : `GCP_PROJECT_ID`, `INGESTED_AT` et `MELTANO_ENVIRONMENT` sont fournis par l'appelant. Chaque script vérifie en tête, avec `: "${VAR:?message}"`, celles qu'il utilise. Un script ne choisit jamais son environnement et ne donne aucune valeur par défaut à ces variables.
- Dans un message entre guillemets doubles, `$(...)` est exécuté. Pour afficher une commande à titre d'exemple, échapper le dollar (`\$(...)`).
- Pas d'apostrophe dans le message de `"${VAR:?message}"` : Bash y ouvre une chaîne entre guillemets simples, qui avale les lignes suivantes jusqu'à l'apostrophe suivante, et la vérification de la variable suivante disparaît (`shellcheck` SC1011).
- Toute suppression qui dépend d'une variable est protégée contre la valeur vide (`"${DIR:?}"`).

## Écriture

- Chemins relatifs au script (`"$(dirname "$0")"`), jamais au répertoire courant.
- Options longues, une par ligne quand la commande est longue.
- Messages en français, comme dans les scripts existants. Un message final résume ce qui a été fait (objet, run, projet). Les erreurs vont sur la sortie d'erreur.
- Aucun secret en argument de commande ni dans un `echo`, et pas de `set -x` dans un script qui manipule des secrets.
- `shellcheck` passe sans avertissement. Une exclusion porte sa justification sur la même ligne.

## Garde-fous pour l'agent

Autorisé sans confirmation : `shellcheck`, `bash -n` (vérification de syntaxe sans exécution).

Avant d'exécuter un script : afficher `GCP_PROJECT_ID` et `MELTANO_ENVIRONMENT`, et vérifier qu'ils désignent dev.

Demander une confirmation explicite avant d'exécuter `run.sh` sur dev : il appelle une API externe et écrit dans GCS.

Interdit :

- exécuter un script avec les variables de production depuis le poste local ;
- retirer `set -euo pipefail`, ou masquer une erreur avec `|| true` ;
- ajouter une valeur par défaut qui désigne un environnement ;
- exécuter un script téléchargé sans relecture (`curl ... | bash`).
