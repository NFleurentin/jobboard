---
paths:
  - ".github/**"
globs:
  - ".github/**"
---

# Règles GitHub Actions

Ces règles couvrent l'écriture des workflows et le déploiement par la CI. Les pull requests et les garde-fous `gh` sont dans `github.md`.

Un workflow exécute du code avec accès aux secrets et au cloud. Il se traite comme du code de production.

## Épingler les actions par SHA

- Référencer chaque action par son SHA de commit complet (40 caractères), avec le tag en commentaire : `uses: actions/checkout@<sha-complet> # v4.x.y`.
- Pourquoi : un tag comme `v4` est mobile. Si le dépôt de l'action est compromis, le tag peut être déplacé vers du code malveillant qui s'exécutera avec nos secrets. Un SHA est immuable.
- Obtenir le SHA avec `git ls-remote <url-du-depot> 'refs/tags/<tag>*'`, sans jamais l'inventer ni le recopier d'un exemple. Si une ligne se termine par `^{}`, prendre son SHA : c'est le commit visé par un tag annoté.
- Dependabot (`package-ecosystem: github-actions` dans `.github/dependabot.yml`) tient les SHA à jour. Sans lui, les actions épinglées ne reçoivent plus de correctifs.

## Permissions minimales du `GITHUB_TOKEN`

- Déclarer `permissions: contents: read` au niveau de chaque workflow.
- N'élever les droits que sur le job qui en a besoin (par exemple `id-token: write` pour l'authentification OIDC).

## Authentification GCP sans clé

- Utiliser Workload Identity Federation (OIDC) via `google-github-actions/auth`, jamais une clé JSON de service account stockée en secret.
- Côté GCP, restreindre le provider à ce dépôt et, pour la production, à la branche `main`.

## Injection de script

Ne jamais interpoler une donnée contrôlée par un tiers (titre de PR, nom de branche, message de commit, corps d'issue) directement dans un bloc `run` : l'expression est remplacée avant l'exécution du shell, donc un titre de PR bien choisi exécute des commandes. Passer par une variable d'environnement :

```yaml
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "$PR_TITLE"
```

## Déclencheurs à risque

- Ne pas utiliser `pull_request_target` ni `workflow_run` pour exécuter le code d'une PR : ces déclencheurs donnent accès aux secrets à du code non relu. Utiliser `pull_request`.
- Les workflows déclenchés par `pull_request` n'ont pas besoin des secrets de production. S'ils en demandent, c'est un défaut de conception.

## Secrets et environnements

- Les secrets de production sont rattachés à des environments restreints à `main` : `prod` (déploiements, approbation manuelle), `prod-collect` (collecte planifiée, `sa-extract` seul, sans approbation) et `prod-load` (chargement quotidien par `loading/load.py`, `sa-dbt` seul, sans approbation).
- Ne jamais afficher un secret dans les logs (`echo`, `set -x`, mode debug), ni le passer en argument de ligne de commande.

## Hygiène des workflows

- `runs-on` avec une version d'image explicite (`ubuntu-26.04`), jamais `ubuntu-latest` : comme un tag d'action, ce label est mobile et change l'image sans PR. Dependabot ne le met pas à jour : la montée de version se fait par une PR dédiée, validée par un run manuel en dev, avant le retrait annoncé de l'image.
- `timeout-minutes` sur chaque job : un job bloqué consomme des minutes jusqu'à la limite par défaut de 6 heures.
- `concurrency` pour annuler les exécutions obsolètes sur une même PR, et pour empêcher deux déploiements simultanés.
- Actions tierces limitées aux éditeurs identifiés. Pour une tâche simple, préférer quelques lignes de shell à une action inconnue.
- La logique va dans `run.sh` et `load.sh`, pas dans le YAML (voir `AGENTS.md`).

## Déploiement

- Les déploiements (`terraform apply`, exécutions dbt et Meltano en production) passent uniquement par la CI, depuis `main`, via l'environment protégé. Seules exceptions, faute de CI possible : `bootstrap.sh` et `identity/prod` (la CI ne modifie pas sa propre porte d'entrée), appliqués à la main par le propriétaire du dépôt, jamais par un agent.
- Sur une PR, la CI (à venir) se limite à la validation : lint, `terraform plan`, build et tests dbt dans un dataset dédié à la CI.

## Garde-fous pour l'agent

Toute création ou modification d'un fichier sous `.github/` : exposer le plan et les impacts de sécurité avant d'écrire.

Interdit :

- référencer une action par un tag ou une branche, ou écrire un SHA non vérifié ;
- ajouter `continue-on-error` ou désactiver un check pour faire passer une CI ;
- déclencher un déploiement en production.
