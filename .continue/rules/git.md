# Règles Git

Ces règles précisent, pour ce dépôt, les garde-fous généraux. Elles couvrent uniquement Git : branches, commits, historique et commandes à risque.

## Modèle de branches

Le dépôt suit un modèle trunk-based : une branche `main` toujours stable, et des branches de travail courtes qui en partent et y reviennent.

- `main` est la seule branche longue. Ne jamais committer directement dessus.
- Une branche = un sujet. Si le travail déborde du sujet, créer une autre branche.
- Durée de vie visée : quelques jours. Une branche longue accumule les conflits et rend la relecture difficile.
- Toujours créer la branche depuis un `main` à jour :

```bash
git switch main
git pull --rebase
git switch -c feat/orders-incremental
```

## Nommage des branches

Format : `<type>/<description>`

- `type` : un des types de commit listés plus bas (`feat`, `fix`, `docs`...).
- `description` : 2 à 5 mots en anglais, minuscules, séparés par des tirets (kebab-case).

| Correct | Incorrect | Raison |
|---|---|---|
| `feat/orders-incremental` | `feature_orders` | type non normalisé, underscore |
| `fix/null-customer-id` | `fix/Bug` | majuscule, description vide de sens |
| `chore/upgrade-dbt-1-9` | `nicolas/test` | nom de personne, sujet inconnu |

## Messages de commit

Format Conventional Commits :

```text
<type>(<scope>): <sujet>

<corps : pourquoi ce changement>
```

Types autorisés :

| Type | Usage |
|---|---|
| `feat` | nouvelle fonctionnalité (modèle, source, extracteur, ressource) |
| `fix` | correction d'un comportement incorrect |
| `refactor` | restructuration sans changement de comportement |
| `perf` | amélioration de performance ou de coût |
| `test` | ajout ou correction de tests |
| `docs` | documentation uniquement |
| `ci` | pipelines d'intégration et de déploiement |
| `chore` | maintenance : dépendances, configuration, outillage |
| `revert` | annulation d'un commit précédent |

Scopes : `dbt`, `meltano`, `terraform`, `ci`, `docs`. Le scope est optionnel si le changement est transverse.

Règles du sujet :

- en anglais, à l'impératif présent (`add`, pas `added` ni `adds`) ;
- 72 caractères maximum, sans majuscule initiale ni point final ;
- décrit l'effet du changement, pas l'activité (`fix null handling in customer join`, pas `update model`).
- si le changement casse un contrat (colonne renommée ou supprimée, variable Terraform modifiée), ajouter `!` avant les deux-points : `feat(dbt)!: rename customer_id to customer_key`. Le corps décrit alors l'impact pour les consommateurs.

Règles du corps :

- obligatoire dès que le "pourquoi" n'est pas évident à la lecture du diff ;
- explique la raison et le contexte, pas le détail du code ;
- lignes de 72 caractères maximum, séparé du sujet par une ligne vide.

Exemple complet :

```text
perf(dbt): switch daily orders model to incremental

The full refresh scanned the whole source table on every run and
took 40 minutes. An incremental strategy with a 3-day lookback keeps
late-arriving rows while reducing scanned bytes.
```

## Contenu d'un commit

- Un commit = un changement logique, qui laisse le projet dans un état cohérent. Ne pas mélanger refactoring et changement fonctionnel.
- Ajouter les fichiers explicitement (`git add <chemin>`). Ne pas utiliser `git add .` ni `git add -A`.
- Avant chaque commit, relire `git status` et `git diff --staged`.
- Ne jamais committer : secrets (`.env`, clés de service account, `*.tfvars` contenant des valeurs sensibles), state Terraform (`*.tfstate`, `.terraform/`), artefacts générés (`target/`, `dbt_packages/`, `logs/`, `.meltano/`).
- `.terraform.lock.hcl` et `package-lock.yml` (dbt) sont versionnés : ils garantissent des versions identiques pour tous.

## Historique

- Mettre sa branche à jour par rebase sur `main` tant qu'elle n'est pas partagée : l'historique reste linéaire et lisible.

```bash
git fetch origin
git rebase origin/main
```

- Ne jamais réécrire un historique déjà partagé (`rebase`, `commit --amend`, `reset`) sur `main` ou sur la branche de quelqu'un d'autre.
- Pour annuler un commit déjà publié : `git revert`, qui crée un commit inverse sans toucher à l'historique.
- Si un push forcé est nécessaire sur sa propre branche : `git push --force-with-lease`, jamais `--force`. La première forme échoue si quelqu'un a poussé entre-temps, la seconde écrase son travail.

## Commandes modernes

- Préférer `git switch` à `git checkout` pour changer de branche.
- Préférer `git restore` à `git checkout` pour restaurer des fichiers.

## Garde-fous pour l'agent

Autorisé sans confirmation : les commandes en lecture (`status`, `diff`, `log`, `show`, `branch`, `fetch`), la création de branche et `git add` sur des fichiers nommés.

Demander une confirmation explicite avant :

- `git commit` : proposer d'abord le message et la liste des fichiers ;
- `git push`, sous toutes ses formes ;
- `git rebase`, `git merge`, `git cherry-pick`, `git commit --amend` ;
- toute commande qui détruit du travail non sauvegardé : `git reset --hard`, `git clean`, `git restore` ou `git checkout --` sur des fichiers modifiés, `git stash drop` et `git stash clear`, `git branch -D`.

Interdit, même sur demande implicite :

- committer ou pousser sur `main` ;
- `git push --force` (utiliser `--force-with-lease` après confirmation) ;
- `--no-verify`, qui contourne les hooks : si un hook échoue, corriger la cause ;
- modifier la configuration Git (`git config`) ou les hooks du dépôt ;
- ajouter une signature ou une mention d'outil dans les messages de commit.

En cas de conflit de rebase ou de merge : s'arrêter, expliquer l'origine du conflit et proposer une résolution, sans la résoudre seul.
