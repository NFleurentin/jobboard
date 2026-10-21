# Profilage des offres France Travail

Profilage des JSONL bruts de prod, pour trancher les règles de [offers_star_schema.md](../../../offers_star_schema.md) (issue #141). Lancement et masquage : voir le [README du dossier parent](../../README.md).

## Données

```bash
gcloud storage cp -r gs://jobboard-prod-3b375b-raw/france-travail/offers \
  ~/Documents/data/jobboard/france-travail/
```

Chaque ligne JSONL est l'enveloppe du tap : l'offre complète est dans `_raw`, sous forme de chaîne. Les champs personnels masqués par défaut sont ceux de `contact` et `agence`.

## Vues

Définies par [00_setup.sql](00_setup.sql) :

| Vue | Grain | Usage |
|---|---|---|
| `raw_offer_runs` | une ligne par offre et par run | réouvertures |
| `raw_offers` | dernière version de chaque offre | distributions |

L'offre complète est dans la colonne `raw` (JSON) : `raw ->> '$.entreprise.nom'`.

## Requêtes

| Fichier | Contenu |
|---|---|
| [01_field_profile.sql](01_field_profile.sql) | Profil de tous les champs, à tous les niveaux : présence, type, valeurs, motifs |
| [02_company.sql](02_company.sql) | Entreprise : normalisation du nom, stabilité, intermédiaires, noms suspects, attributs |
| [03_contract_duration.sql](03_contract_duration.sql) | Type et durée du contrat : libellés, unités, motif de durée, nature et alternance |
