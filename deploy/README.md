# Release et promotion en prod

La prod n'exécute pas le dernier commit de `main`, mais une **release** : un tag annoté `vX.Y.Z`, choisi explicitement dans `prod-version`. Merger une PR ne déploie donc rien ; publier une release non plus. La mise en prod est une PR qui modifie `prod-version` (#102).

| Fichier | Contenu |
|---|---|
| `prod-version` | Tag de la version de prod, sur une seule ligne. Modifié uniquement par PR |
| `resolve-prod-ref.sh` | Vérifie le tag pointé et affiche le SHA du commit à exécuter. Appelé par le job `resolve` du pipeline et de `terraform-prod.yml` |

## Fonctionnement

Le schedule et le lancement manuel en prod exécutent toujours le workflow de `main` : c'est ce qui garde valides les GitHub Environments `prod-collect` / `prod-load` et la condition Workload Identity Federation, limités à `main`. Le job `resolve`, sans credentials, lance `resolve-prod-ref.sh` depuis `main`, puis `extract` et `load` font leur checkout sur le SHA obtenu. Le script refuse :

- un nom qui n'est pas au format `vX.Y.Z` ;
- un tag absent ou léger (non annoté) ;
- un tag dont le commit n'est pas un ancêtre de `origin/main` (tag posé sur une branche non fusionnée).

Le contrôle vient de `main`, jamais du tag : une ancienne version ne peut pas affaiblir son propre contrôle. Les versions d'outils qui dépendent du code (`transformation/dbt-fusion.env`) sont lues dans le code extrait et suivent donc la version déployée.

En dev (`-f environment=dev`), rien ne change : le pipeline exécute la branche lancée.

## Numérotation

SemVer, en version 0.x tant que les marts ne sont pas stabilisés (le passage en `1.0.0` les fige) :

| Depuis la release précédente | Version suivante |
|---|---|
| au moins un commit `!` (changement cassant) | mineure : `0.1.0` → `0.2.0` |
| `feat` ou `fix` uniquement | patch : `0.1.0` → `0.1.1` |

## Publier une release

Les tags `v*` sont protégés par le ruleset `release-tags` (`.github/settings/`) : une fois poussé, un tag ne peut être ni supprimé ni déplacé.

```bash
git switch main && git pull --rebase
git tag -a vX.Y.Z -m "vX.Y.Z" origin/main     # tag annoté, sur main publié
git cat-file -t vX.Y.Z                        # doit afficher "tag"
git push origin vX.Y.Z                        # définitif à partir d'ici
gh release create vX.Y.Z --verify-tag --generate-notes --title "vX.Y.Z"
```

`gh release create --target` seul crée un tag léger, refusé par `resolve-prod-ref.sh` : toujours créer le tag avant la release, et passer `--verify-tag`.

Une release ne contient que des changements d'infra compatibles avec la version précédente (règle expand/contract, `.continue/rules/github_actions.md`) : une ressource se supprime dans une release ultérieure à celle qui a cessé de l'utiliser.

Les notes de release signalent tout changement de schéma (snapshot, marts, state Meltano) : ces données ne sont pas versionnées, et un retour à une version antérieure peut échouer après un tel changement.

## Promouvoir et revenir en arrière

- **Promotion** : PR qui remplace la version dans `prod-version` (`ci: promote vX.Y.Z to prod`). Son merge lance `terraform-prod.yml`, qui applique l'infra de la release (`infra/envs/prod`) en deux approbations de l'environment `prod` : la première lance le plan, la seconde l'applique après lecture du résumé du job (pas de seconde approbation si le plan est vide). Le code prend effet au run suivant du pipeline (schedule de 05:00 UTC ou lancement manuel en prod) : approuver l'apply avant ce run.
- **Retour arrière** : `git revert` de la PR de promotion, ou nouvelle PR vers la version précédente.

Avant de créer le tag, le commit visé peut être validé en dev : `gh workflow run pipeline-france-travail.yml --ref main -f environment=dev`.

## Vérifier en local

```bash
git fetch --tags origin
deploy/resolve-prod-ref.sh     # affiche le SHA, ou la raison du refus (code retour 1)
```

## Limite

Le workflow lui-même est lu depuis `main`, pas depuis le tag. Une PR qui modifie les étapes du pipeline doit rester compatible avec la version en prod (par exemple, ne pas appeler un script que le tag ne contient pas encore). Si cette contrainte devient gênante : workflow réutilisable épinglé au tag.
