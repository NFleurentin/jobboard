# Règles GitHub

Ces règles couvrent ce qui relève de GitHub : pull requests, stratégie de merge, protection de `main`, GitHub Actions et secrets. Les règles Git (branches, commits, historique) sont dans `git.md`.

## Pull requests

Tout changement arrive sur `main` par une pull request, jamais par un push direct.

- Une PR = un sujet, de petite taille. Une PR relue en 15 minutes est mieux relue qu'une PR de 2 000 lignes.
- Ouvrir la PR en draft tant que le travail n'est pas prêt à être relu.
- Le titre suit le format Conventional Commits défini dans `git.md`. Avec le squash merge, ce titre devient le message de commit sur `main`.
- Langue : le titre est en anglais, comme les commits. La description et les commentaires sont en français.
- La description comporte quatre sections : Pourquoi (le besoin), Quoi (les changements principaux, sans paraphraser le diff), Comment tester, Impact (changement cassant, coût, migration, ou "Aucun").
- Fusionner avec une CI verte dès qu'une CI existe. En attendant, la validation locale décrite dans `AGENTS.md` en tient lieu.
- Projet à un seul contributeur : aucune approbation n'est requise.
- Répondre à chaque commentaire de relecture, par un commit ou par une réponse. C'est l'auteur du commentaire qui le résout.

## Stratégie de merge

Seul le squash merge est utilisé : tous les commits de la branche deviennent un seul commit sur `main`.

- Pourquoi : un historique de `main` linéaire, une PR par commit, et un `git revert` unique pour annuler une fonctionnalité entière.
- Contrepartie : le détail des commits de la branche disparaît de `main`. C'est acceptable tant que les PR restent petites.
- Le message du commit de squash se limite au titre de la PR, sans reprendre la description : l'historique de `main` reste en anglais. Vérifier ce titre juste avant la fusion, puis le passer explicitement : `gh pr merge <numéro> --squash --subject "<titre de la PR>" --body "" --delete-branch`. Sans `--body ""`, GitHub peut ajouter la liste des commits ou la description.
- Supprimer la branche distante après la fusion.
- Après un squash merge, Git ne reconnaît pas la branche locale comme fusionnée : `git branch -d` échoue et il faut `git branch -D`. C'est le comportement attendu.
- Ne pas réutiliser une branche déjà fusionnée. Repartir d'un `main` à jour.

## Protection de `main`

État attendu de la configuration du dépôt. L'agent ne la modifie jamais, mais signale tout écart constaté.

- Pull request obligatoire.
- Checks de CI obligatoires dès qu'une CI existe, et branche à jour avant fusion.
- Historique linéaire, squash merge comme seule méthode autorisée.
- Push forcé et suppression de la branche interdits.
- Aucun contournement, y compris pour les administrateurs.

## GitHub Actions : sécurité

Un workflow exécute du code avec accès aux secrets et au cloud. Il se traite comme du code de production.

### Épingler les actions par SHA

- Référencer chaque action par son SHA de commit complet (40 caractères), avec le tag en commentaire : `uses: actions/checkout@<sha-complet> # v4.x.y`.
- Pourquoi : un tag comme `v4` est mobile. Si le dépôt de l'action est compromis, le tag peut être déplacé vers du code malveillant qui s'exécutera avec nos secrets. Un SHA est immuable.
- Obtenir le SHA avec `git ls-remote <url-du-depot> 'refs/tags/<tag>*'`, sans jamais l'inventer ni le recopier d'un exemple. Si une ligne se termine par `^{}`, prendre son SHA : c'est le commit visé par un tag annoté.
- Dependabot (`package-ecosystem: github-actions` dans `.github/dependabot.yml`) tient les SHA à jour. Sans lui, les actions épinglées ne reçoivent plus de correctifs.

### Permissions minimales du `GITHUB_TOKEN`

- Déclarer `permissions: contents: read` au niveau de chaque workflow.
- N'élever les droits que sur le job qui en a besoin (par exemple `id-token: write` pour l'authentification OIDC).

### Authentification GCP sans clé

- Utiliser Workload Identity Federation (OIDC) via `google-github-actions/auth`, jamais une clé JSON de service account stockée en secret. Une clé est un secret longue durée qui peut fuiter ; un jeton OIDC est émis pour un job et expire rapidement.
- Côté GCP, restreindre le provider à ce dépôt et, pour la production, à la branche `main`.

### Injection de script

Ne jamais interpoler une donnée contrôlée par un tiers (titre de PR, nom de branche, message de commit, corps d'issue) directement dans un bloc `run` : l'expression est remplacée avant l'exécution du shell, donc un titre de PR bien choisi exécute des commandes. Passer par une variable d'environnement :

```yaml
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "$PR_TITLE"
```

### Déclencheurs à risque

- Ne pas utiliser `pull_request_target` ni `workflow_run` pour exécuter le code d'une PR : ces déclencheurs donnent accès aux secrets à du code non relu. Utiliser `pull_request`.
- Les workflows déclenchés par `pull_request` n'ont pas besoin des secrets de production. S'ils en demandent, c'est un défaut de conception.

### Secrets et environnements

- Stocker les secrets dans GitHub (secrets de dépôt ou d'environment), jamais dans le code ni en clair dans un workflow.
- Les secrets de production sont rattachés à des environments restreints à `main` : `prod` (déploiements et dbt, approbation manuelle) et `prod-collect` (collecte planifiée, `sa-extract` seul, sans approbation).
- Ne jamais afficher un secret dans les logs (`echo`, `set -x`, mode debug), ni le passer en argument de ligne de commande.

### Hygiène des workflows

- Définir `timeout-minutes` sur chaque job : un job bloqué consomme des minutes jusqu'à la limite par défaut de 6 heures.
- Utiliser `concurrency` pour annuler les exécutions obsolètes sur une même PR, et pour empêcher deux déploiements simultanés.
- Limiter les actions tierces à celles d'éditeurs identifiés. Pour une tâche simple, préférer quelques lignes de shell à une action inconnue.

## Déploiement

- Les déploiements (`terraform apply`, exécutions dbt et Meltano en production) passent uniquement par la CI, depuis `main`, via l'environment protégé. Jamais depuis un poste local. Seules exceptions, faute de CI possible : `bootstrap.sh` et `identity/prod` (la CI ne modifie pas sa propre porte d'entrée), appliqués à la main par le propriétaire du dépôt, jamais par un agent.
- Sur une PR, la CI (à venir) se limite à la validation : lint, `terraform plan`, build et tests dbt dans un dataset dédié à la CI.

## Garde-fous pour l'agent

Autorisé sans confirmation, en lecture seule : `gh pr view`, `gh pr list`, `gh pr diff`, `gh pr checks`, `gh run list`, `gh run view`, `gh issue view`, `gh issue list`.

Demander une confirmation explicite avant :

- `gh pr create` : proposer d'abord le titre et la description ;
- tout commentaire, review ou changement d'état sur une PR ou une issue ;
- `gh pr merge` ;
- `gh workflow run` et `gh run rerun` ;
- toute création ou modification d'un fichier sous `.github/` : exposer le plan et les impacts de sécurité avant d'écrire.

Interdit :

- lire, créer, modifier ou supprimer des secrets et variables (`gh secret`, `gh variable`) ;
- modifier les paramètres du dépôt, la protection de branches, les environments ou les droits d'accès, y compris via `gh api` ;
- contourner les protections : `gh pr merge --admin`, désactivation d'un check, ajout de `continue-on-error` pour faire passer une CI ;
- approuver une PR ;
- déclencher un déploiement en production ;
- référencer une action par un tag ou une branche, ou écrire un SHA non vérifié.

Si la CI échoue : lire les logs, expliquer la cause et proposer un correctif. Ne pas relancer en boucle, ni affaiblir un test ou un check pour obtenir du vert.
