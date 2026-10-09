# Configuration du dépôt GitHub

Rulesets et paramètres du dépôt, versionnés pour être relus en PR, réappliqués après une erreur et comparés à l'état réel. GitHub ne lit pas ces fichiers : ils servent de référence, et la configuration s'applique à la main par le propriétaire du dépôt, comme `infra/identity/prod`. Ni la CI ni un agent ne modifient ces paramètres.

| Fichier | Contenu |
|---|---|
| `ruleset-main.json` | Ruleset de `main` : PR obligatoire (0 approbation, conversations résolues, squash seul), historique linéaire, suppression et push forcé interdits, bypass vide |
| `settings.json` | Paramètres attendus, une clé par endpoint de l'API (`repos/<dépôt>/<clé>`, la clé vide désigne le dépôt). Seuls les champs déclarés sont garantis |
| `check.sh` | Compare l'état réel aux fichiers, en lecture seule. Code retour 1 en cas de dérive |

## Vérifier

```bash
infra/github/check.sh
```

Prérequis : `gh` authentifié avec un compte administrateur du dépôt (les endpoints Actions et sécurité l'exigent), `jq`.

À lancer après chaque modification de la configuration, avant une release, et dès qu'une modification non tracée est soupçonnée.

## Modifier

1. Changer le réglage dans l'interface (*Settings*).
2. Mettre à jour le fichier :
   - ruleset : *Settings → Rules → Rulesets → … → Export ruleset*, puis retirer les champs propres à l'instance (`id`, `source`, `source_type`) pour ne garder que `name`, `target`, `enforcement`, `conditions`, `rules` et `bypass_actors` ;
   - paramètres : modifier `settings.json` à la main.
3. `check.sh` ne doit plus signaler de dérive. Committer dans une PR.

## Réappliquer un ruleset depuis le fichier

```bash
REPO=NFleurentin/jobboard
id=$(gh api "repos/$REPO/rulesets" --jq '.[] | select(.name == "main") | .id')
gh api --method PUT "repos/$REPO/rulesets/$id" --input infra/github/ruleset-main.json
# Ruleset absent : création
gh api --method POST "repos/$REPO/rulesets" --input infra/github/ruleset-main.json
```

## En cas de blocage

Le bypass est vide : le propriétaire lui-même ne peut pas contourner le ruleset. Pour débloquer une situation (merge impossible, règle mal réglée), passer le ruleset en *Disabled* dans *Settings → Rules → Rulesets*, corriger, puis le réactiver et relancer `check.sh`.
