-- =============================================================================
-- Schéma de vente en ligne + facturation conforme EN 16931
-- Cible : PostgreSQL 15+ (UNIQUE NULLS NOT DISTINCT)
--
-- Sources : spécifications externes v3.2 (AIFE, 30/04/2026) dans
-- Refs/specifications-v3.2/. Dans les commentaires :
--   BT-n / BG-n   : terme / groupe métier de la norme EN 16931
--   EXT-FR-FE-n   : extension française (Annexe 1)
--   Gx.y, Sx.y    : règle de gestion de l'Annexe 7 v1.9
--   TT-n          : donnée du flux 10 (Annexe 6)
--   DSE §x.y      : dossier général v3.2
--   cas n°x       : cas d'usage du DSE v2.1 (Refs/). La v3.2 renvoie les cas
--                   d'usage à la norme AFNOR XP Z12-014, non fournie.
--
-- Deux philosophies cohabitent, volontairement :
--   * Partie VENTE : contraintes STRICTES. Une commande incohérente est refusée.
--   * Partie FACTURE : contraintes MINIMALES. La plateforme doit pouvoir stocker
--     une facture non conforme pour la rejeter en citant la règle violée
--     (G7.29). Les règles BR-* relèvent du contrôle (db/controles.sql), pas de
--     contraintes CHECK qui feraient échouer l'INSERT sans explication métier.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA vente;
SET search_path = vente, public;

-- Argent : jamais de float. EN 16931 limite les montants à 2 décimales (BR-DEC)
-- mais pas les prix unitaires (BT-146), d'où deux domaines distincts.
CREATE DOMAIN montant  AS NUMERIC(19,2);
CREATE DOMAIN prix     AS NUMERIC(19,6);
CREATE DOMAIN quantite AS NUMERIC(15,4);
CREATE DOMAIN taux     AS NUMERIC(5,2) CHECK (VALUE BETWEEN 0 AND 100);

-- -----------------------------------------------------------------------------
-- 1. Paramétrage et référentiels
-- -----------------------------------------------------------------------------

CREATE TABLE parametre (
    cle         TEXT PRIMARY KEY,
    valeur      TEXT NOT NULL,
    description TEXT NOT NULL
);

CREATE TABLE pays (
    code      CHAR(2) PRIMARY KEY,               -- ISO 3166-1 alpha-2
    nom       TEXT NOT NULL,
    membre_ue BOOLEAN NOT NULL
);

CREATE TABLE devise (
    code      CHAR(3) PRIMARY KEY,               -- ISO 4217 (BT-5, BT-6)
    nom       TEXT NOT NULL,
    decimales SMALLINT NOT NULL DEFAULT 2
);

CREATE TABLE unite_mesure (
    code    TEXT PRIMARY KEY,                    -- UN/ECE Rec. 20 (BT-130)
    libelle TEXT NOT NULL
);

CREATE TABLE mode_paiement (
    code          TEXT PRIMARY KEY,
    libelle       TEXT NOT NULL,
    code_uncl4461 TEXT NOT NULL                  -- BT-81
);

CREATE TABLE type_facture (
    code     CHAR(3) PRIMARY KEY,                -- UNTDID 1001 (BT-3)
    libelle  TEXT NOT NULL,
    est_avoir BOOLEAN NOT NULL DEFAULT FALSE     -- inverse le signe en e-reporting
);

CREATE TABLE cadre_facturation (
    code    CHAR(2) PRIMARY KEY,                 -- BT-23
    libelle TEXT NOT NULL,
    nature  TEXT NOT NULL CHECK (nature IN ('LB','PS','LBPS'))
);

CREATE TABLE statut_facture (
    code         SMALLINT PRIMARY KEY,           -- DSE §3.6.4, tableau 8
    libelle      TEXT NOT NULL,
    transmission TEXT NOT NULL CHECK (transmission IN ('Obligatoire','Facultatif')),
    producteur   TEXT NOT NULL
);

CREATE TABLE categorie_ereporting (
    code    TEXT PRIMARY KEY,                    -- G1.68 (TT-81)
    libelle TEXT NOT NULL
);

CREATE TABLE categorie_tva (
    code          TEXT PRIMARY KEY,              -- UNTDID 5305 (BT-118, BT-151)
    libelle       TEXT NOT NULL,
    motif_requis  BOOLEAN NOT NULL               -- BT-120 ou BT-121 obligatoire
);

CREATE TABLE motif_exoneration (
    code    TEXT PRIMARY KEY,                    -- liste VATEX (BT-121)
    libelle TEXT NOT NULL                        -- texte repris en BT-120
);

CREATE TABLE classe_tva (
    code    TEXT PRIMARY KEY,                    -- classe fiscale d'un article
    libelle TEXT NOT NULL
);

-- Le taux dépend du pays (ventes à distance UE) et de la date : on
-- historise au lieu de modifier, et l'exclusion interdit deux taux simultanés.
CREATE TABLE taux_tva (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pays_code  CHAR(2) NOT NULL REFERENCES pays,
    classe_code TEXT NOT NULL REFERENCES classe_tva,
    taux       taux NOT NULL,
    date_debut DATE NOT NULL,
    date_fin   DATE,                             -- borne exclue ; NULL = en vigueur
    CHECK (date_fin IS NULL OR date_fin > date_debut),
    EXCLUDE USING gist (
        pays_code WITH =,
        classe_code WITH =,
        daterange(date_debut, date_fin) WITH &&
    )
);

-- Le régime TVA fixe les périodes du e-reporting (DSE §3.7.7, tableau 13). Les
-- données de paiement n'ont pas toujours la période des transactions.
CREATE TABLE regime_tva (
    code      TEXT PRIMARY KEY,
    libelle   TEXT NOT NULL,
    frequence_transactions TEXT NOT NULL,
    delai_transactions     TEXT NOT NULL,
    frequence_paiements    TEXT NOT NULL,
    delai_paiements        TEXT NOT NULL
);

-- -----------------------------------------------------------------------------
-- 2. Vendeur, clients, adresses
-- -----------------------------------------------------------------------------

-- Le vendeur (BG-4). Une seule boutique aujourd'hui, mais l'unicité d'une
-- facture se juge par fournisseur (G1.45) : le vendeur est donc une entité.
CREATE TABLE societe (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    raison_sociale  TEXT NOT NULL,               -- BT-27
    nom_commercial  TEXT,                        -- BT-28
    forme_juridique TEXT,                        -- BT-33
    siren           CHAR(9)  NOT NULL UNIQUE CHECK (siren ~ '^[0-9]{9}$'),    -- BT-30
    siret           CHAR(14) NOT NULL CHECK (siret ~ '^[0-9]{14}$'),          -- BT-29
    tva_intra       TEXT NOT NULL,               -- BT-31
    adresse_ligne1  TEXT NOT NULL,               -- BT-35
    adresse_ligne2  TEXT,                        -- BT-36
    code_postal     TEXT NOT NULL,               -- BT-38
    ville           TEXT NOT NULL,               -- BT-37
    pays_code       CHAR(2) NOT NULL REFERENCES pays,  -- BT-40
    contact_nom     TEXT,                        -- BT-41
    telephone       TEXT,                        -- BT-42
    email           TEXT,                        -- BT-43
    iban            TEXT NOT NULL,               -- BT-84
    bic             TEXT,                        -- BT-86
    regime_tva_code TEXT NOT NULL REFERENCES regime_tva,
    option_tva_debits BOOLEAN NOT NULL DEFAULT FALSE,  -- G1.43, porté par BT-8
    CHECK (substr(siret, 1, 9) = siren)
);

-- type_client décide du circuit fiscal (voir facture.regime_transmission).
CREATE TABLE client (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero         TEXT NOT NULL UNIQUE,
    type_client    TEXT NOT NULL CHECK (type_client IN
                     ('PARTICULIER','ASSUJETTI_FR','ASSUJETTI_UE','ASSUJETTI_HORS_UE')),
    nom            TEXT,
    prenom         TEXT,
    raison_sociale TEXT,
    siren          CHAR(9)  CHECK (siren ~ '^[0-9]{9}$'),
    siret          CHAR(14) CHECK (siret ~ '^[0-9]{14}$'),
    tva_intra      TEXT,
    code_routage   TEXT,                         -- BT-46, schéma 0224 (G1.83)
    email          TEXT NOT NULL UNIQUE,
    telephone      TEXT,
    actif          BOOLEAN NOT NULL DEFAULT TRUE,
    date_creation  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (type_client = 'PARTICULIER' OR raison_sociale IS NOT NULL),
    CHECK (type_client <> 'PARTICULIER' OR nom IS NOT NULL),
    CHECK (type_client <> 'ASSUJETTI_FR' OR siren IS NOT NULL),   -- G1.63
    CHECK (type_client <> 'ASSUJETTI_UE' OR tva_intra IS NOT NULL)
);

-- Une adresse utilisée n'est jamais modifiée : on la désactive et on en crée
-- une nouvelle. Les factures, elles, en gardent une copie (voir facture).
CREATE TABLE adresse (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id    BIGINT NOT NULL REFERENCES client,
    usage        TEXT NOT NULL CHECK (usage IN ('FACTURATION','LIVRAISON')),
    destinataire TEXT,
    ligne1       TEXT NOT NULL,
    ligne2       TEXT,
    ligne3       TEXT,
    code_postal  TEXT NOT NULL,
    ville        TEXT NOT NULL,
    subdivision  TEXT,
    pays_code    CHAR(2) NOT NULL REFERENCES pays,
    actif        BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX ON adresse (client_id);

-- -----------------------------------------------------------------------------
-- 3. Catalogue et remises
-- -----------------------------------------------------------------------------

CREATE TABLE article (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku             TEXT NOT NULL UNIQUE,        -- BT-155
    gtin            TEXT,                        -- BT-157
    libelle         TEXT NOT NULL,               -- BT-153
    description     TEXT,                        -- BT-154
    nature          TEXT NOT NULL CHECK (nature IN ('LB','PS')),  -- bien ou service
    unite_code      TEXT NOT NULL REFERENCES unite_mesure,
    prix_ht         prix NOT NULL CHECK (prix_ht >= 0),
    classe_tva_code TEXT NOT NULL REFERENCES classe_tva,
    eco_participation_ht prix NOT NULL DEFAULT 0 CHECK (eco_participation_ht >= 0),
    stock           INTEGER,                     -- NULL pour un service
    actif           BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE remise (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code          TEXT NOT NULL UNIQUE,
    libelle       TEXT NOT NULL,
    type_valeur   TEXT NOT NULL CHECK (type_valeur IN ('POURCENTAGE','MONTANT')),
    valeur        NUMERIC(19,4) NOT NULL CHECK (valeur > 0),
    portee        TEXT NOT NULL CHECK (portee IN ('LIGNE','COMMANDE')),
    article_id    BIGINT REFERENCES article,     -- NULL : tout le panier
    montant_min_ht montant NOT NULL DEFAULT 0,
    code_motif    TEXT NOT NULL DEFAULT '95',    -- UNTDID 5189 (BT-98, BT-140)
    date_debut    DATE NOT NULL,
    date_fin      DATE,
    actif         BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (type_valeur <> 'POURCENTAGE' OR valeur <= 100)
);

-- -----------------------------------------------------------------------------
-- 4. Commandes
-- -----------------------------------------------------------------------------

CREATE TABLE commande (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero                 TEXT NOT NULL UNIQUE,  -- repris en BT-14
    societe_id             BIGINT NOT NULL REFERENCES societe,
    client_id              BIGINT NOT NULL REFERENCES client,
    adresse_facturation_id BIGINT NOT NULL REFERENCES adresse,
    adresse_livraison_id   BIGINT NOT NULL REFERENCES adresse,
    date_commande          TIMESTAMPTZ NOT NULL,
    date_livraison         DATE,                  -- BT-72
    statut                 TEXT NOT NULL CHECK (statut IN
                             ('EN_ATTENTE','PAYEE','EXPEDIEE','LIVREE','ANNULEE')),
    devise_code            CHAR(3) NOT NULL DEFAULT 'EUR' REFERENCES devise,
    mode_paiement_code     TEXT NOT NULL REFERENCES mode_paiement,
    reference_client       TEXT                   -- bon de commande acheteur, BT-13
);
CREATE INDEX ON commande (client_id);
CREATE INDEX ON commande (date_commande);

-- La TVA est figée à la commande : un changement de taux ultérieur ne doit pas
-- modifier une vente passée. taux_tva est NULL pour la catégorie O (hors champ).
CREATE TABLE commande_ligne (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    commande_id     BIGINT NOT NULL REFERENCES commande ON DELETE CASCADE,
    numero_ligne    INTEGER NOT NULL,
    article_id      BIGINT NOT NULL REFERENCES article,
    libelle         TEXT NOT NULL,
    quantite        quantite NOT NULL CHECK (quantite > 0),
    prix_ht         prix NOT NULL CHECK (prix_ht >= 0),
    remise_id       BIGINT REFERENCES remise,
    remise_ht       montant NOT NULL DEFAULT 0 CHECK (remise_ht >= 0),
    eco_participation_ht montant NOT NULL DEFAULT 0 CHECK (eco_participation_ht >= 0),
    montant_net_ht  NUMERIC(19,2) GENERATED ALWAYS AS
                      (round(quantite * prix_ht, 2) - remise_ht + eco_participation_ht) STORED,
    categorie_tva_code TEXT NOT NULL REFERENCES categorie_tva,
    taux_tva        taux,
    motif_exoneration_code TEXT REFERENCES motif_exoneration,
    UNIQUE (commande_id, numero_ligne)
);

-- Remises et frais du panier (futurs BG-20 / BG-21). EN 16931 impose une
-- catégorie et un taux de TVA sur chacun (BT-95/96, BT-102/103) : une remise
-- sur un panier à deux taux donne donc DEUX lignes ici.
CREATE TABLE commande_ajustement (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    commande_id BIGINT NOT NULL REFERENCES commande ON DELETE CASCADE,
    sens        TEXT NOT NULL CHECK (sens IN ('REMISE','FRAIS')),
    remise_id   BIGINT REFERENCES remise,
    code_motif  TEXT NOT NULL,                   -- UNTDID 5189 ou 7161
    libelle     TEXT NOT NULL,
    montant_ht  montant NOT NULL CHECK (montant_ht > 0),
    categorie_tva_code TEXT NOT NULL REFERENCES categorie_tva,
    taux_tva    taux,
    motif_exoneration_code TEXT REFERENCES motif_exoneration
);
CREATE INDEX ON commande_ajustement (commande_id);

-- -----------------------------------------------------------------------------
-- 5. Liste de facturation : les commandes à facturer lors d'un passage
-- -----------------------------------------------------------------------------

CREATE TABLE liste_facturation (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero        TEXT NOT NULL UNIQUE,
    societe_id    BIGINT NOT NULL REFERENCES societe,
    periode_debut DATE NOT NULL,
    periode_fin   DATE NOT NULL,
    statut        TEXT NOT NULL DEFAULT 'BROUILLON'
                    CHECK (statut IN ('BROUILLON','VALIDEE','FACTUREE','ANNULEE')),
    date_creation TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (periode_fin >= periode_debut)
);

-- -----------------------------------------------------------------------------
-- 6. Factures (EN 16931)
-- -----------------------------------------------------------------------------

-- Une SEQUENCE PostgreSQL laisse des trous après un ROLLBACK ; or la
-- numérotation d'une facture doit être continue. Ce compteur transactionnel
-- verrouille la ligne de la série jusqu'au COMMIT.
CREATE TABLE compteur_facture (
    societe_id     BIGINT NOT NULL REFERENCES societe,
    serie          TEXT NOT NULL,
    annee          SMALLINT NOT NULL,
    dernier_numero INTEGER NOT NULL,
    PRIMARY KEY (societe_id, serie, annee)
);

-- La facture est un INSTANTANÉ : vendeur, acheteur et adresses sont recopiés,
-- pas seulement référencés. Un client qui déménage ne change pas une facture
-- déjà émise. Les FK servent à la traçabilité et sont nulles pour une facture
-- déposée sur la plateforme par un tiers.
CREATE TABLE facture (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    societe_id  BIGINT REFERENCES societe,
    commande_id BIGINT REFERENCES commande,
    client_id   BIGINT REFERENCES client,

    -- En-tête
    numero         TEXT NOT NULL,                -- BT-1
    date_emission  DATE NOT NULL,                -- BT-2
    millesime      SMALLINT GENERATED ALWAYS AS (EXTRACT(YEAR FROM date_emission)::SMALLINT) STORED,
    type_code      CHAR(3) NOT NULL REFERENCES type_facture,  -- BT-3
    devise_code    CHAR(3) NOT NULL REFERENCES devise,        -- BT-5
    devise_tva_code CHAR(3) REFERENCES devise,   -- BT-6
    date_exigibilite DATE,                       -- BT-7
    code_date_exigibilite TEXT,                  -- BT-8 : option débits, 5 en CII, 3 en UBL (G1.43)
    date_echeance  DATE,                         -- BT-9 : date de versement pour un acompte
    reference_acheteur TEXT,                     -- BT-10
    reference_contrat  TEXT,                     -- BT-12
    reference_commande_acheteur TEXT,            -- BT-13
    reference_commande_vendeur  TEXT,            -- BT-14
    conditions_paiement TEXT,                    -- BT-20
    cadre_facturation_code CHAR(2) REFERENCES cadre_facturation,  -- BT-23
    profil         TEXT NOT NULL DEFAULT 'urn:cen.eu:en16931:2017',  -- BT-24 (flux 2)

    -- Vendeur (BG-4), adresse (BG-5), contact (BG-6)
    vendeur_nom            TEXT,                 -- BT-27
    vendeur_nom_commercial TEXT,                 -- BT-28
    vendeur_siret          TEXT,                 -- BT-29, schéma 0009
    vendeur_siren          TEXT,                 -- BT-30, schéma 0002
    vendeur_tva            TEXT,                 -- BT-31
    vendeur_forme_juridique TEXT,                -- BT-33
    vendeur_adresse_electronique TEXT,           -- BT-34
    vendeur_adresse_electronique_schema TEXT,    -- BT-34-1
    vendeur_adresse_ligne1 TEXT,                 -- BT-35
    vendeur_adresse_ligne2 TEXT,                 -- BT-36
    vendeur_ville          TEXT,                 -- BT-37
    vendeur_code_postal    TEXT,                 -- BT-38
    vendeur_pays_code      CHAR(2) REFERENCES pays,  -- BT-40
    vendeur_contact_nom    TEXT,                 -- BT-41
    vendeur_contact_telephone TEXT,              -- BT-42
    vendeur_contact_email  TEXT,                 -- BT-43
    assujetti_unique_siren TEXT,                 -- BT-29d, schéma 0231 (G1.76)

    -- Représentant fiscal (BG-11), obligatoire aussi pour un assujetti unique
    representant_fiscal_nom TEXT,                -- BT-62
    representant_fiscal_tva TEXT,                -- BT-63

    -- Acheteur (BG-7), adresse (BG-8)
    acheteur_nom           TEXT,                 -- BT-44
    acheteur_identifiant   TEXT,                 -- BT-46 : SIRET ou code routage
    acheteur_identifiant_schema TEXT,            -- BT-46-1 : 0009 ou 0224 (G1.73)
    acheteur_siren         TEXT,                 -- BT-47, schéma 0002 (G1.63)
    acheteur_tva           TEXT,                 -- BT-48
    acheteur_adresse_electronique TEXT,          -- BT-49
    acheteur_adresse_electronique_schema TEXT,   -- BT-49-1
    acheteur_adresse_ligne1 TEXT,                -- BT-50
    acheteur_adresse_ligne2 TEXT,                -- BT-51
    acheteur_adresse_ligne3 TEXT,                -- BT-163
    acheteur_ville         TEXT,                 -- BT-52
    acheteur_code_postal   TEXT,                 -- BT-53
    acheteur_subdivision   TEXT,                 -- BT-54
    acheteur_pays_code     CHAR(2) REFERENCES pays,  -- BT-55

    -- Livraison (BG-13), adresse (BG-15), période (BG-14)
    livraison_nom          TEXT,                 -- BT-70
    date_livraison         DATE,                 -- BT-72
    periode_debut          DATE,                 -- BT-73
    periode_fin            DATE,                 -- BT-74
    livraison_adresse_ligne1 TEXT,               -- BT-75
    livraison_adresse_ligne2 TEXT,               -- BT-76
    livraison_adresse_ligne3 TEXT,               -- BT-165
    livraison_ville        TEXT,                 -- BT-77
    livraison_code_postal  TEXT,                 -- BT-78
    livraison_pays_code    CHAR(2) REFERENCES pays,  -- BT-80

    -- Paiement (BG-16, BG-17)
    code_moyen_paiement    TEXT,                 -- BT-81
    libelle_moyen_paiement TEXT,                 -- BT-82
    reference_paiement     TEXT,                 -- BT-83
    iban_beneficiaire      TEXT,                 -- BT-84
    bic_beneficiaire       TEXT,                 -- BT-86

    -- Totaux (BG-22). Stockés tels que reçus : les recalculer ici masquerait
    -- précisément les erreurs que le contrôle doit détecter (BR-CO-10 à 16).
    total_lignes_ht  montant,                    -- BT-106
    total_remises    montant,                    -- BT-107
    total_frais      montant,                    -- BT-108
    total_ht         montant,                    -- BT-109
    total_tva        montant,                    -- BT-110
    total_tva_devise_comptable montant,          -- BT-111
    total_ttc        montant,                    -- BT-112
    montant_paye     montant,                    -- BT-113
    arrondi          montant,                    -- BT-114
    net_a_payer      montant,                    -- BT-115

    -- Données propres à la réforme française (hors EN 16931)
    regime_transmission TEXT NOT NULL CHECK (regime_transmission IN
        ('E_INVOICING','E_REPORTING_B2C','E_REPORTING_B2B_INTL')),  -- DSE §2.3
    option_tva_debits BOOLEAN NOT NULL DEFAULT FALSE,
    format_echange TEXT CHECK (format_echange IN ('UBL','CII','FACTURX')),
    -- Le statut 200 atteste que la facture est contrôlée et conforme (DSE
    -- §3.6.4) : NULL = pas encore contrôlée, ou hors cycle de vie (e-reporting).
    statut_code    SMALLINT REFERENCES statut_facture,
    date_creation  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON facture (commande_id);
CREATE INDEX ON facture (client_id);
CREATE INDEX ON facture (date_emission);

-- Contrôle d'unicité G1.45 : numéro + SIREN du fournisseur + millésime. Une
-- facture rejetée en sort, d'où l'index partiel plutôt qu'une contrainte UNIQUE.
-- IS DISTINCT FROM : avec <>, les factures au statut NULL échapperaient à l'index.
CREATE UNIQUE INDEX facture_unicite_idx
    ON facture (vendeur_siren, numero, millesime)
    WHERE statut_code IS DISTINCT FROM 213;

CREATE TABLE facture_ligne (                     -- BG-25
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facture_id      BIGINT NOT NULL REFERENCES facture ON DELETE CASCADE,
    commande_ligne_id BIGINT REFERENCES commande_ligne,
    numero_ligne    INTEGER NOT NULL,            -- BT-126
    note            TEXT,                        -- BT-127 : obligatoire si éco-participation
    note_code_sujet TEXT,                        -- EXT-FR-FE-183 : BLU pour l'écotaxe (G1.52)
    quantite        quantite,                    -- BT-129
    unite_code      TEXT,                        -- BT-130
    montant_net_ht  montant,                     -- BT-131
    periode_debut   DATE,                        -- BT-134
    periode_fin     DATE,                        -- BT-135
    prix_net_ht     prix,                        -- BT-146
    rabais_prix     prix,                        -- BT-147
    prix_brut_ht    prix,                        -- BT-148
    base_quantite   quantite,                    -- BT-149
    categorie_tva_code TEXT,                     -- BT-151
    taux_tva        taux,                        -- BT-152
    libelle         TEXT,                        -- BT-153
    description     TEXT,                        -- BT-154
    reference_vendeur TEXT,                      -- BT-155
    gtin            TEXT,                        -- BT-157
    gtin_schema     TEXT,                        -- BT-157-1 (0160 = GS1)
    nature          TEXT,                        -- LB/PS, hors norme
    motif_exoneration_code TEXT,                 -- alimente BT-120/121 de BG-23

    -- Reprise d'acompte ou avoir en ligne (EXT-FR-FE-BG-06). Pour un avoir, ne
    -- pas renseigner à la fois l'en-tête et les lignes (G1.31).
    facture_anterieure_numero TEXT,              -- EXT-FR-FE-136
    facture_anterieure_date   DATE,              -- EXT-FR-FE-138

    -- Multi-livraison (EXT-FR-FE-BG-10, BG-11), si différent de l'en-tête
    livraison_nom           TEXT,                -- EXT-FR-FE-149
    livraison_adresse_ligne1 TEXT,               -- EXT-FR-FE-151
    livraison_adresse_ligne2 TEXT,               -- EXT-FR-FE-152
    livraison_adresse_ligne3 TEXT,               -- EXT-FR-FE-153
    livraison_ville         TEXT,                -- EXT-FR-FE-154
    livraison_code_postal   TEXT,                -- EXT-FR-FE-155
    livraison_subdivision   TEXT,                -- EXT-FR-FE-156
    livraison_pays_code     CHAR(2),             -- EXT-FR-FE-157
    date_livraison          DATE,                -- EXT-FR-FE-158
    UNIQUE (facture_id, numero_ligne)
);

CREATE TABLE facture_ligne_ajustement (          -- BG-27 / BG-28
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facture_ligne_id BIGINT NOT NULL REFERENCES facture_ligne ON DELETE CASCADE,
    sens             TEXT NOT NULL CHECK (sens IN ('REMISE','FRAIS')),
    montant          montant,                    -- BT-136 / BT-141
    base             montant,                    -- BT-137 / BT-142
    pourcentage      NUMERIC(7,4),               -- BT-138 / BT-143
    motif            TEXT,                       -- BT-139 / BT-144
    code_motif       TEXT                        -- BT-140 / BT-145
);
CREATE INDEX ON facture_ligne_ajustement (facture_ligne_id);

CREATE TABLE facture_ajustement (                -- BG-20 / BG-21
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facture_id  BIGINT NOT NULL REFERENCES facture ON DELETE CASCADE,
    sens        TEXT NOT NULL CHECK (sens IN ('REMISE','FRAIS')),
    montant     montant,                         -- BT-92 / BT-99
    base        montant,                         -- BT-93 / BT-100
    pourcentage NUMERIC(7,4),                    -- BT-94 / BT-101
    categorie_tva_code TEXT,                     -- BT-95 / BT-102
    taux_tva    taux,                            -- BT-96 / BT-103
    motif       TEXT,                            -- BT-97 / BT-104
    code_motif  TEXT,                            -- BT-98 / BT-105
    motif_exoneration_code TEXT                  -- alimente BT-120/121 de BG-23
);
CREATE INDEX ON facture_ajustement (facture_id);

CREATE TABLE facture_tva (                       -- BG-23 : ventilation de TVA
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facture_id  BIGINT NOT NULL REFERENCES facture ON DELETE CASCADE,
    categorie_tva_code TEXT,                     -- BT-118
    taux_tva    taux,                            -- BT-119
    base_ht     montant,                         -- BT-116
    montant_tva montant,                         -- BT-117
    motif       TEXT,                            -- BT-120
    code_motif  TEXT,                            -- BT-121
    UNIQUE NULLS NOT DISTINCT (facture_id, categorie_tva_code, taux_tva)
);

-- Déclaration B2C d'une facture. Une facture double doit distinguer biens et
-- services (Annexe 6, correspondance) : la catégorie ne peut donc pas être une
-- colonne de facture. Une TVA étrangère se déclare avec un taux 0 (DSE §2.3.3).
CREATE TABLE facture_ereporting (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facture_id  BIGINT NOT NULL REFERENCES facture ON DELETE CASCADE,
    categorie_ereporting_code TEXT NOT NULL REFERENCES categorie_ereporting,
    taux_tva    taux NOT NULL,                   -- TT-86
    base_ht     montant NOT NULL,                -- TT-87
    montant_tva montant NOT NULL,                -- TT-88
    UNIQUE (facture_id, categorie_ereporting_code, taux_tva)
);

CREATE TABLE facture_reference_precedente (      -- BG-3
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facture_id  BIGINT NOT NULL REFERENCES facture ON DELETE CASCADE,
    numero      TEXT,                            -- BT-25
    date_facture DATE,                           -- BT-26
    facture_precedente_id BIGINT REFERENCES facture
);
CREATE INDEX ON facture_reference_precedente (facture_id);

CREATE TABLE facture_note (                      -- BG-1
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facture_id BIGINT NOT NULL REFERENCES facture ON DELETE CASCADE,
    code_sujet TEXT,                             -- BT-21 (UNTDID 4451)
    texte      TEXT                              -- BT-22
);
CREATE INDEX ON facture_note (facture_id);

CREATE TABLE liste_facturation_ligne (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    liste_id    BIGINT NOT NULL REFERENCES liste_facturation ON DELETE CASCADE,
    commande_id BIGINT NOT NULL REFERENCES commande,
    facture_id  BIGINT REFERENCES facture,
    statut      TEXT NOT NULL DEFAULT 'A_FACTURER'
                  CHECK (statut IN ('A_FACTURER','FACTUREE','EXCLUE')),
    motif_exclusion TEXT,
    UNIQUE (liste_id, commande_id),
    CHECK (statut <> 'FACTUREE' OR facture_id IS NOT NULL),
    CHECK (statut <> 'EXCLUE'   OR motif_exclusion IS NOT NULL)
);

-- -----------------------------------------------------------------------------
-- 7. Transactions de paiement
-- -----------------------------------------------------------------------------

-- Montant signé : une annulation d'encaissement est un montant négatif, jamais
-- une suppression (P1.17, cas n°34).
CREATE TABLE transaction_paiement (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reference     TEXT NOT NULL UNIQUE,
    commande_id   BIGINT NOT NULL REFERENCES commande,
    facture_id    BIGINT REFERENCES facture,
    type_operation TEXT NOT NULL CHECK (type_operation IN ('PAIEMENT','REMBOURSEMENT','ANNULATION')),
    statut        TEXT NOT NULL CHECK (statut IN ('AUTORISEE','CAPTUREE','ECHOUEE')),
    mode_paiement_code TEXT NOT NULL REFERENCES mode_paiement,
    montant       montant NOT NULL,
    devise_code   CHAR(3) NOT NULL DEFAULT 'EUR' REFERENCES devise,
    date_transaction TIMESTAMPTZ NOT NULL,
    reference_psp TEXT,
    CHECK ((type_operation = 'PAIEMENT' AND montant > 0)
        OR (type_operation <> 'PAIEMENT' AND montant < 0))
);
CREATE INDEX ON transaction_paiement (commande_id);
CREATE INDEX ON transaction_paiement (facture_id);

-- Le statut 212 exige l'encaissement par taux de TVA, sinon le cycle de vie est
-- rejeté (G7.45, REJ_ENCAISSEMENT) : le montant global ne suffit pas.
CREATE TABLE transaction_paiement_tva (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id BIGINT NOT NULL REFERENCES transaction_paiement ON DELETE CASCADE,
    categorie_tva_code TEXT NOT NULL REFERENCES categorie_tva,
    taux_tva       taux,
    montant        montant NOT NULL,
    UNIQUE NULLS NOT DISTINCT (transaction_id, categorie_tva_code, taux_tva)
);

-- -----------------------------------------------------------------------------
-- 8. Vues
-- -----------------------------------------------------------------------------

-- Ventilation d'une commande par taux, calculée comme BG-23 : la TVA s'arrondit
-- par groupe de taux (BR-CO-17), pas ligne à ligne.
CREATE VIEW v_commande_tva AS
SELECT commande_id, categorie_tva_code, taux_tva, motif_exoneration_code,
       sum(base) AS base_ht,
       round(sum(base) * coalesce(taux_tva, 0) / 100, 2) AS montant_tva
FROM (
    SELECT commande_id, categorie_tva_code, taux_tva, motif_exoneration_code,
           montant_net_ht AS base
    FROM commande_ligne
    UNION ALL
    SELECT commande_id, categorie_tva_code, taux_tva, motif_exoneration_code,
           CASE sens WHEN 'FRAIS' THEN montant_ht ELSE -montant_ht END
    FROM commande_ajustement
) m
GROUP BY commande_id, categorie_tva_code, taux_tva, motif_exoneration_code;

CREATE VIEW v_commande_total AS
SELECT commande_id,
       sum(base_ht) AS total_ht,
       sum(montant_tva) AS total_tva,
       sum(base_ht + montant_tva) AS total_ttc
FROM v_commande_tva
GROUP BY commande_id;

-- Flux 10.3 : cumul journalier B2C par catégorie et taux, sans donnée
-- personnelle. Le fait générateur est la date de réalisation de l'opération
-- (DSE §3.7.7). Une facture rejetée n'est pas déclarée.
CREATE VIEW v_ereporting_b2c_jour AS
SELECT f.vendeur_siren,
       coalesce(f.date_livraison, f.date_emission) AS date_transactions,
       e.categorie_ereporting_code,
       f.devise_code,
       e.taux_tva,
       f.option_tva_debits,
       sum(s.signe * e.base_ht) AS base_ht,
       sum(s.signe * e.montant_tva) AS montant_tva,
       count(DISTINCT f.id) AS nb_transactions       -- facultatif (DSE §2.3.3)
FROM facture f
JOIN facture_ereporting e ON e.facture_id = f.id
JOIN type_facture y ON y.code = f.type_code
CROSS JOIN LATERAL (SELECT CASE WHEN y.est_avoir THEN -1 ELSE 1 END AS signe) s
WHERE f.statut_code IS DISTINCT FROM 213
GROUP BY 1, 2, 3, 4, 5, 6;

-- Flux 10.4 : encaissements B2C des prestations de services hors option débits,
-- et des factures d'acompte, dont la TVA est exigible à l'encaissement (DSE
-- §2.3.2). Pour une facture double, seule la part des services est retenue.
CREATE VIEW v_ereporting_paiement_b2c_jour AS
SELECT f.vendeur_siren,
       p.date_transaction::DATE AS date_encaissement,
       p.devise_code,
       v.taux_tva,
       sum(round(v.montant * r.part_declaree, 2)) AS montant_encaisse
FROM transaction_paiement p
JOIN transaction_paiement_tva v ON v.transaction_id = p.id
JOIN facture f ON f.id = p.facture_id
CROSS JOIN LATERAL (
    SELECT sum(e.base_ht) FILTER (WHERE e.categorie_ereporting_code = 'TPS1' OR f.type_code = '386')
           / nullif(sum(e.base_ht), 0) AS part_declaree
    FROM facture_ereporting e
    WHERE e.facture_id = f.id AND e.taux_tva IS NOT DISTINCT FROM v.taux_tva
) r
WHERE p.statut = 'CAPTUREE'
  AND f.regime_transmission = 'E_REPORTING_B2C'
  AND NOT f.option_tva_debits
  AND r.part_declaree > 0
GROUP BY 1, 2, 3, 4;
