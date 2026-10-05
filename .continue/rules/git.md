# Règles Git

Ces règles couvrent Git : branches, commits, historique et commandes à risque. Les pull requests sont dans `github.md`.

## Branches

Modèle trunk-based : `main` toujours stable, branches de travail courtes (quelques jours) créées depuis un `main` à jour (`git switch main && git pull --rebase`).

- Ne jamais committer directement sur `main`. Une branche = un sujet : si le travail déborde, créer une autre branche.
- Nom : `<type>/<description>`, avec un type de commit ci-dessous et 2 à 5 mots en anglais, en kebab-case (`feat/orders-incremental`, `fix/null-customer-id`).

## Messages de commit

Format Conventional Commits : `<type>(<scope>): <sujet>`, une ligne vide, puis un corps qui explique le pourquoi.

- Types : `feat`, `fix`, `refactor` (sans changement de comportement), `perf`, `test`, `docs`, `ci`, `chore` (dépendances, configuration, outillage), `revert`.
- Scopes : `dbt`, `meltano`, `terraform`, `ci`, `docs`. Optionnel si le changement est transverse.
- Sujet en anglais, à l'impératif présent, 72 caractères maximum, sans majuscule initiale ni point final. Il décrit l'effet du changement, pas l'activité (`fix null handling in customer join`, pas `update model`).
- `!` avant les deux-points si le changement casse un contrat pour un consommateur (colonne de mart renommée ou supprimée, variable Terraform modifiée). Le corps décrit alors l'impact.
- Corps obligatoire dès que le pourquoi n'est pas évident à la lecture du diff : la raison et le contexte, pas le détail du code. Lignes de 72 caractères maximum.

## Contenu d'un commit

- Un commit = un changement logique, qui laisse le projet dans un état cohérent. Ne pas mélanger refactoring et changement fonctionnel.
- Ajouter les fichiers explicitement (`git add <chemin>`), jamais `git add .` ni `git add -A`. Relire `git status` et `git diff --staged` avant chaque commit.
- Ne jamais committer : secrets (`.env`, clés, `*.tfvars` sensibles), state Terraform (`*.tfstate`, `.terraform/`), artefacts générés (`target/`, `dbt_packages/`, `logs/`, `.meltano/`).
- `.terraform.lock.hcl` et `package-lock.yml` (dbt) sont versionnés.

## Historique

- Mettre sa branche à jour par rebase sur `origin/main` tant qu'elle n'est pas partagée.
- Ne jamais réécrire un historique partagé. Pour annuler un commit publié : `git revert`.
- Push forcé sur sa propre branche : `--force-with-lease`, jamais `--force`.
- Préférer `git switch` et `git restore` à `git checkout`.

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
- `--no-verify` : si un hook échoue, corriger la cause ;
- modifier la configuration Git (`git config`) ou les hooks du dépôt ;
- ajouter une signature ou une mention d'outil dans les messages de commit.

En cas de conflit de rebase ou de merge : s'arrêter, expliquer l'origine du conflit et proposer une résolution, sans la résoudre seul.
