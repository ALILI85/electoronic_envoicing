# Base de données : vente en ligne et facturation EN 16931

Schéma aligné sur les **spécifications externes v3.2 du 30/04/2026** (`Refs/specifications-v3.2/`) : dossier général, Annexe 1 (flux 1) v1.2, Annexe 2 (cycle de vie) v2.3, Annexe 6 (e-reporting) v1.10 et Annexe 7 (règles de gestion) v1.9.

## Lancer la base

Les scripts de `init/` se chargent dans l'ordre au premier démarrage :

```bash
docker run -d --name einvoice-pg -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=einvoice -p 5433:5432 -v "$PWD/init:/docker-entrypoint-initdb.d:ro" postgres:17-alpine
```

Contrôler la conformité des factures (une ligne par règle violée) :

```bash
docker exec -i einvoice-pg psql -U postgres -d einvoice -f - < controles.sql
```

## Fichiers

| Fichier | Contenu |
|---|---|
| `init/01_schema.sql` | 35 tables, index et 4 vues du schéma `vente` |
| `init/02_referentiels.sql` | Paramètres, pays, taux de TVA, codes de la réforme |
| `init/03_fonctions.sql` | 9 fonctions : TVA, numérotation, génération des factures, déclaration B2C |
| `init/04_donnees_test.sql` | Clients, articles, 15 commandes, 16 transactions, 15 factures conformes |
| `init/05_factures_non_conformes.sql` | 14 factures fautives pour tester le validateur |
| `controles.sql` | Contrôle des règles BR principales et des règles de gestion G |

## Tables

| Domaine | Tables |
|---|---|
| Paramétrage | `parametre`, `pays`, `devise`, `unite_mesure`, `mode_paiement`, `regime_tva` |
| TVA | `categorie_tva`, `classe_tva`, `taux_tva`, `motif_exoneration` |
| Codes de la réforme | `type_facture`, `cadre_facturation`, `statut_facture`, `categorie_ereporting` |
| Tiers | `societe`, `client`, `adresse` |
| Catalogue | `article`, `remise` |
| Commandes | `commande`, `commande_ligne`, `commande_ajustement` |
| Facturation | `liste_facturation`, `liste_facturation_ligne`, `compteur_facture` |
| Factures | `facture`, `facture_ligne`, `facture_ligne_ajustement`, `facture_ajustement`, `facture_tva`, `facture_ereporting`, `facture_reference_precedente`, `facture_note` |
| Transactions | `transaction_paiement`, `transaction_paiement_tva` |
| Vues | `v_commande_tva`, `v_commande_total`, `v_ereporting_b2c_jour` (flux 10.3), `v_ereporting_paiement_b2c_jour` (flux 10.4) |

## Cas couverts par les commandes de test

| Commande | Cas | Traitement |
|---|---|---|
| 0001 | B2C France, deux taux, code promo, port | E-reporting TLB1, remise répartie par taux |
| 0002 | B2C service, paiement annulé puis repayé | E-reporting TPS1, encaissement négatif |
| 0003 | B2C taux 5,5 % et 2,1 % | E-reporting TLB1 |
| 0004 | B2C Allemagne, TVA étrangère | TNT1, HT seul déclaré avec un taux 0, mention sur la facture |
| 0005 | Annulée et remboursée | Exclue de la liste de facturation |
| 0006 | B2C bien et service | TLB1 et TPS1 déclarés séparément, paiement limité à la part service |
| 0007 | B2B France à 30 jours, paiement partiel | E-invoicing B1, BT-113 non nul |
| 0008 | B2B France payée, livraison ailleurs | E-invoicing M2 |
| 0009 | Acompte puis facture définitive | Type 386 en S2, puis 380 en S4 avec reprise en ligne |
| 0010 | Retour partiel | Facture puis avoir 381 |
| 0011 | B2B Belgique | Catégorie K, e-reporting B2B international |
| 0012 | B2B Allemagne, service | Catégorie AE, autoliquidation |
| 0013 | B2B Suisse, biens | Catégorie G, exportation |
| 0014 | B2B Suisse, service | Catégorie O, sans n° de TVA vendeur (BR-O-2) |
| 0015 | En attente | Reste à facturer dans la liste d'octobre |

## Limites connues

- Non fournie : les normes AFNOR XP Z12-012, Z12-013 et Z12-014, payantes, ne sont pas dans le ZIP. Elles définissent le flux 2 complet, le format de BT-34 / BT-49 et les cas d'usage. Les renvois « cas n°x » viennent donc du DSE v2.1.
- À confirmer dans XP Z12-012 : le schéma `0225` de l'adresse électronique (paramétré), le traitement de la facture d'acompte et de sa reprise.
- Annexe 6 et G1.02 divergent sur le cadre S3 : seul G1.02 est appliqué.
- BR-O-2 interdit BT-31 sur la facture, alors que G2.33 l'exige en flux 10 : le futur flux devra le reprendre de `societe`.
- Le contrôle SQL couvre une partie des règles ; il ne remplace pas les schematrons officiels.
- Simplifications de TVA : seuil OSS supposé dépassé, port au taux normal du pays de livraison.
- Non couvert à ce stade : flux reçus et transmissions, statuts 250/251, 300/301 et 501/601, historique du cycle de vie, identifiants 0223/0227 du flux 10, motifs de refus, immuabilité technique des factures émises.
