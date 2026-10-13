#!/usr/bin/env bash
# Vérifie que la configuration GitHub du dépôt correspond aux fichiers
# versionnés : rulesets (ruleset-*.json) et paramètres (settings.json).
# Lecture seule : n'applique rien.
# Code retour : 0 sans dérive, 1 si un élément diffère ou est absent.
set -euo pipefail

REPO=NFleurentin/jobboard
DIR=$(dirname "$0")

# Champs déclaratifs uniquement ; règles triées pour un ordre déterministe.
NORMALIZE='{name, target, enforcement, conditions, rules: (.rules | sort_by(.type)), bypass_actors}'

status=0

# Rulesets : retrouvés par leur nom, l'id changeant si le ruleset est recréé.
for file in "$DIR"/ruleset-*.json; do
  name=$(jq -r '.name' "$file")
  id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")

  if [[ -z "$id" ]]; then
    echo "DÉRIVE : ruleset '$name' absent sur GitHub ($file)" >&2
    status=1
    continue
  fi

  if diff <(jq -S "$NORMALIZE" "$file") \
          <(gh api "repos/$REPO/rulesets/$id" | jq -S "$NORMALIZE"); then
    echo "OK : ruleset '$name'"
  else
    echo "DÉRIVE : ruleset '$name' (< fichier, > GitHub)" >&2
    status=1
  fi
done

# Paramètres : une clé par endpoint (la clé vide désigne le dépôt lui-même).
# Seuls les champs déclarés sont comparés, l'API en renvoyant bien plus.
while IFS= read -r endpoint; do
  label=${endpoint:-dépôt}
  expected=$(jq -S --arg endpoint "$endpoint" '.[$endpoint]' "$DIR/settings.json")

  if diff <(echo "$expected") \
          <(gh api "repos/$REPO${endpoint:+/$endpoint}" \
              | jq -S --argjson expected "$expected" \
                  'with_entries(select(.key as $key | $expected | has($key)))'); then
    echo "OK : paramètres '$label'"
  else
    echo "DÉRIVE : paramètres '$label' (< fichier, > GitHub)" >&2
    status=1
  fi
done < <(jq -r 'keys[]' "$DIR/settings.json")

# Alertes Dependabot : l'API ne renvoie qu'un code HTTP (204 actif, 404 inactif).
if gh api --silent "repos/$REPO/vulnerability-alerts" 2>/dev/null; then
  echo "OK : alertes Dependabot"
else
  echo "DÉRIVE : alertes Dependabot désactivées" >&2
  status=1
fi

exit "$status"
