#!/usr/bin/env bash
# Résout la version de prod pointée par deploy/prod-version et affiche le SHA
# du commit à exécuter, seul sur la sortie standard.
# Refuse tout ce qui n'est pas un tag annoté vX.Y.Z dont le commit est un
# ancêtre de origin/main (issue #102) : un tag posé sur une branche non
# fusionnée ne part pas en prod.
# Prérequis : historique complet et tags (git fetch --tags origin).
set -euo pipefail

cd "$(dirname "$0")"
version_file=prod-version

tag=$(<"$version_file")

# Regex sans guillemets : entre guillemets, elle serait comparée littéralement.
if [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version invalide dans ${version_file} : '${tag}' (attendu : vX.Y.Z)" >&2
  exit 1
fi

# Un tag léger renvoie "commit" : seuls les tags annotés sont acceptés.
type=$(git cat-file -t "refs/tags/${tag}" 2>/dev/null) || {
  echo "Tag ${tag} introuvable (lancer git fetch --tags origin)" >&2
  exit 1
}
if [[ $type != tag ]]; then
  echo "Tag ${tag} non annoté (type : ${type}) : créer les releases avec git tag -a" >&2
  exit 1
fi

# ^{commit} : le commit visé, pas l'objet tag lui-même.
sha=$(git rev-parse "refs/tags/${tag}^{commit}")

if ! git merge-base --is-ancestor "$sha" origin/main; then
  echo "Tag ${tag} (${sha}) absent de l'historique de origin/main : refusé" >&2
  exit 1
fi

# Résumé sur la sortie d'erreur : la sortie standard ne porte que le SHA.
echo "Version de prod : ${tag} (${sha})" >&2
echo "$sha"
