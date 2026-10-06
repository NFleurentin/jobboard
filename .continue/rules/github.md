# Règles GitHub

Ces règles couvrent les issues, les pull requests, la stratégie de merge, la protection de `main` et les commandes `gh`. Les workflows et le déploiement sont dans `github_actions.md`, les branches et commits dans `git.md`.

## Issues

Une issue = un problème. Les écarts mineurs d'un même outil se regroupent dans une seule issue, avec une case à cocher par écart.

- Titre en anglais, pour partager le vocabulaire de la PR et du commit qui la traiteront. Il décrit le problème, pas la solution : pas de type Conventional Commits, les labels en tiennent lieu.
- Préfixe de scope entre crochets, parmi les scopes de `git.md` (`[dbt] Snapshot run without a new partition closes every offer`). Il est omis si le problème est transverse.
- Description en français, en quatre sections : Constat (fichiers et lignes), Impact, Pistes, Critères de fin (cases à cocher). Ce qui reste à confirmer est signalé comme hypothèse.
- Labels existants uniquement : `bug`, `enhancement`, `documentation`, `question`.
- La PR qui la traite la référence dans sa description (`Closes #<numéro>`).

## Pull requests

Tout changement arrive sur `main` par une pull request, jamais par un push direct.

- Une PR = un sujet, de petite taille. Ouverte en draft tant qu'elle n'est pas prête à être relue.
- Titre en anglais au format Conventional Commits (`git.md`) : avec le squash merge, il devient le message de commit sur `main`.
- Description et commentaires en français. La description comporte quatre sections : Pourquoi, Quoi (sans paraphraser le diff), Comment tester, Impact (changement cassant, coût, migration, ou "Aucun").
- Pas encore de CI : la validation locale décrite dans `AGENTS.md` en tient lieu. Projet à un seul contributeur : aucune approbation requise.
- Répondre à chaque commentaire de relecture, par un commit ou par une réponse. C'est l'auteur du commentaire qui le résout.

## Stratégie de merge

Squash merge uniquement : une PR = un commit sur `main`, annulable par un seul `git revert`.

- Le message du commit de squash se limite au titre de la PR. Vérifier ce titre juste avant la fusion, puis le passer explicitement : `gh pr merge <numéro> --squash --subject "<titre de la PR>" --body "" --delete-branch`. Sans `--body ""`, GitHub peut ajouter la liste des commits ou la description.
- Après un squash merge, `git branch -d` échoue sur la branche locale : `git branch -D` est attendu. Ne pas réutiliser une branche fusionnée.

## Protection de `main`

État attendu, que l'agent ne modifie jamais mais dont il signale tout écart : PR obligatoire, checks de CI obligatoires dès qu'une CI existe, historique linéaire, squash merge seul, push forcé et suppression interdits, aucun contournement pour les administrateurs.

## Garde-fous pour l'agent

Autorisé sans confirmation, en lecture seule : `gh pr view`, `gh pr list`, `gh pr diff`, `gh pr checks`, `gh run list`, `gh run view`, `gh issue view`, `gh issue list`.

Demander une confirmation explicite avant :

- `gh issue create` et `gh pr create` : proposer d'abord le titre et la description ;
- tout commentaire, review ou changement d'état sur une PR ou une issue ;
- `gh pr merge` ;
- `gh workflow run` et `gh run rerun`.

Interdit :

- lire, créer, modifier ou supprimer des secrets et variables (`gh secret`, `gh variable`) ;
- modifier les paramètres du dépôt, la protection de branches, les environments ou les droits d'accès, y compris via `gh api` ;
- `gh pr merge --admin` ou tout contournement des protections ;
- approuver une PR.

Si la CI échoue : lire les logs, expliquer la cause et proposer un correctif. Ne pas relancer en boucle, ni affaiblir un test ou un check pour obtenir du vert.
