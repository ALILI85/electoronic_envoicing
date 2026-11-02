-- Données de test FICTIVES. Les SIREN/SIRET/TVA/IBAN ont des clés valides mais
-- n'identifient aucune entité connue ; emails en .example, téléphones dans la
-- plage réservée aux fictions (01 99 00).
SET search_path = vente, public;

INSERT INTO societe (raison_sociale, nom_commercial, forme_juridique, siren, siret, tva_intra,
                     adresse_ligne1, code_postal, ville, pays_code,
                     contact_nom, telephone, email, iban, bic, regime_tva_code)
VALUES ('Demo Commerce', 'DemoShop', 'SAS au capital de 50 000 EUR',
        '990012346', '99001234600013', 'FR64990012346',
        '12 rue de l''Exemple', '75011', 'Paris', 'FR',
        'Service facturation', '+33 1 99 00 10 00', 'facturation@demoshop.example',
        'FR8699999000010000123456782', 'DEMOFRPPXXX', 'REEL_MENSUEL');

INSERT INTO client (numero, type_client, nom, prenom, raison_sociale, siren, siret, tva_intra, code_routage, email, telephone) VALUES
 ('CLI-0001','PARTICULIER',      'Martin',  'Camille', NULL, NULL, NULL, NULL, NULL, 'camille.martin@mail.example',  '+33 1 99 00 11 01'),
 ('CLI-0002','PARTICULIER',      'Bernard', 'Sacha',   NULL, NULL, NULL, NULL, NULL, 'sacha.bernard@mail.example',   '+33 1 99 00 11 02'),
 ('CLI-0003','PARTICULIER',      'Petit',   'Alex',    NULL, NULL, NULL, NULL, NULL, 'alex.petit@mail.example',      '+33 1 99 00 11 03'),
 ('CLI-0004','PARTICULIER',      'Schmidt', 'Robin',   NULL, NULL, NULL, NULL, NULL, 'robin.schmidt@mail.example',   NULL),
 ('CLI-0005','PARTICULIER',      'Durand',  'Noa',     NULL, NULL, NULL, NULL, NULL, 'noa.durand@mail.example',      '+33 1 99 00 11 05'),
 ('CLI-0101','ASSUJETTI_FR',     NULL, NULL, 'Atelier Numérique',   '990023459', '99002345900011', 'FR35990023459', NULL,      'compta@atelier-num.example', '+33 1 99 00 12 01'),
 ('CLI-0102','ASSUJETTI_FR',     NULL, NULL, 'Bureau & Conseil',    '990034563', '99003456300017', 'FR76990034563', 'ACHATS',  'achats@bureau-conseil.example', '+33 1 99 00 12 02'),
 ('CLI-0103','ASSUJETTI_FR',     NULL, NULL, 'Cabinet Horizon',     '990045676', '99004567600014', 'FR47990045676', NULL,      'factures@horizon.example',   '+33 1 99 00 12 03'),
 ('CLI-0104','ASSUJETTI_FR',     NULL, NULL, 'Delta Logistique',    '990056780', '99005678000010', 'FR88990056780', NULL,      'compta@delta-log.example',   '+33 1 99 00 12 04'),
 ('CLI-0201','ASSUJETTI_UE',     NULL, NULL, 'Brussels Trading SA', NULL, NULL, 'BE0999888777', NULL, 'ap@brussels-trading.example', NULL),
 ('CLI-0202','ASSUJETTI_UE',     NULL, NULL, 'Berlin Software GmbH',NULL, NULL, 'DE999888777',  NULL, 'rechnung@berlin-soft.example', NULL),
 ('CLI-0301','ASSUJETTI_HORS_UE',NULL, NULL, 'Genève Services SA',  NULL, NULL, NULL,           NULL, 'compta@geneve-services.example', NULL);

-- Une adresse de facturation et une de livraison par client ; Bureau & Conseil
-- se fait livrer ailleurs (l'adresse de livraison est alors obligatoire à
-- partir du 01/09/2027, G6.16).
INSERT INTO adresse (client_id, usage, destinataire, ligne1, code_postal, ville, pays_code)
SELECT k.id, u.usage, coalesce(k.raison_sociale, k.prenom || ' ' || k.nom), v.ligne1, v.cp, v.ville, v.pays
FROM (VALUES
 ('CLI-0001','8 rue des Lilas','69003','Lyon','FR'),
 ('CLI-0002','21 avenue du Parc','33000','Bordeaux','FR'),
 ('CLI-0003','3 place du Marché','59000','Lille','FR'),
 ('CLI-0004','Hauptstrasse 5','10115','Berlin','DE'),
 ('CLI-0005','14 impasse des Pins','31000','Toulouse','FR'),
 ('CLI-0101','5 rue de l''Industrie','44000','Nantes','FR'),
 ('CLI-0102','90 boulevard Central','13001','Marseille','FR'),
 ('CLI-0103','2 allée des Tilleuls','67000','Strasbourg','FR'),
 ('CLI-0104','40 route du Port','76600','Le Havre','FR'),
 ('CLI-0201','Avenue Louise 100','1050','Bruxelles','BE'),
 ('CLI-0202','Friedrichstrasse 50','10117','Berlin','DE'),
 ('CLI-0301','Rue du Rhône 10','1204','Genève','CH')
) v(numero, ligne1, cp, ville, pays)
JOIN client k ON k.numero = v.numero
CROSS JOIN (VALUES ('FACTURATION'), ('LIVRAISON')) u(usage);

UPDATE adresse SET destinataire = 'Bureau & Conseil, agence d''Aix',
                   ligne1 = '7 cours Mirabeau', code_postal = '13100', ville = 'Aix-en-Provence'
WHERE usage = 'LIVRAISON'
  AND client_id = (SELECT id FROM client WHERE numero = 'CLI-0102');

INSERT INTO article (sku, gtin, libelle, description, nature, unite_code, prix_ht, classe_tva_code, eco_participation_ht, stock) VALUES
 ('LIV-0001','9799990000011','Guide de la facture électronique','Livre broché, 320 pages',       'LB','C62',  28.43,'REDUIT',       0,    120),
 ('LIV-0002','9799990000028','Manuel de comptabilité',          'Livre broché, 540 pages',       'LB','C62',  42.65,'REDUIT',       0,     80),
 ('ALI-0001','3999990000014','Thé vert bio 100 g',              'Sachet refermable',             'LB','C62',   6.90,'REDUIT',       0,    300),
 ('PRE-0001',NULL,           'Revue Gestion, numéro d''octobre','Presse mensuelle',              'LB','C62',   5.80,'PARTICULIER',  0,     50),
 ('INF-0001','3999990000021','Ordinateur portable 14 pouces',   '16 Go, SSD 512 Go',             'LB','C62', 749.00,'NORMAL',       0.50,  35),
 ('INF-0002','3999990000038','Écran 27 pouces',                 'Dalle IPS, QHD',                'LB','C62', 229.00,'NORMAL',       0.84,  60),
 ('INF-0003','3999990000045','Clavier sans fil',                'Disposition AZERTY',            'LB','C62',  39.90,'NORMAL',       0,    200),
 ('SRV-0001',NULL,           'Formation en ligne e-facture',    'Session à distance, à l''heure','PS','HUR', 120.00,'NORMAL',       0,   NULL),
 ('SRV-0002',NULL,           'Installation sur site',           'Forfait mise en service',       'PS','C62',  89.00,'NORMAL',       0,   NULL),
 ('SRV-0003',NULL,           'Extension de garantie 2 ans',     'Service après-vente étendu',    'PS','C62',  59.00,'NORMAL',       0,   NULL);

INSERT INTO remise (code, libelle, type_valeur, valeur, portee, montant_min_ht, date_debut, date_fin) VALUES
 ('BIENVENUE10','Code promo bienvenue -10 %',  'POURCENTAGE',10,'COMMANDE', 50,'2026-01-01','2026-12-31'),
 ('FIXE20',     'Bon de réduction 20 EUR',     'MONTANT',    20,'COMMANDE',100,'2026-01-01','2026-12-31'),
 ('VOLUME5',    'Remise volume -5 %',          'POURCENTAGE', 5,'LIGNE',     0,'2026-01-01',NULL),
 ('ETE2026',    'Soldes d''été (expirée)',     'POURCENTAGE',15,'COMMANDE',  0,'2026-06-01','2026-08-31');

-- -----------------------------------------------------------------------------
-- Commandes : chaque commande illustre un cas de la réforme
-- -----------------------------------------------------------------------------
INSERT INTO commande (numero, societe_id, client_id, adresse_facturation_id, adresse_livraison_id,
                      date_commande, date_livraison, statut, mode_paiement_code, reference_client)
SELECT v.numero, (SELECT id FROM societe), k.id, af.id, al.id,
       v.date_cmd::TIMESTAMPTZ, v.date_liv::DATE, v.statut, v.mode, v.ref
FROM (VALUES
 -- B2C France : plusieurs taux, code promo, port
 ('CMD-2026-0001','CLI-0001','2026-09-01 10:12+02','2026-09-04','LIVREE','CB',NULL),
 -- B2C France : service seul, paiement frauduleux annulé puis repayé (cas n°34)
 ('CMD-2026-0002','CLI-0002','2026-09-02 09:30+02','2026-09-08','LIVREE','PAYPAL',NULL),
 -- B2C France : taux 5,5 % et 2,1 %
 ('CMD-2026-0003','CLI-0003','2026-09-03 18:45+02','2026-09-05','LIVREE','CB',NULL),
 -- B2C Allemagne : TVA du pays de destination
 ('CMD-2026-0004','CLI-0004','2026-09-04 20:05+02','2026-09-09','LIVREE','CB',NULL),
 -- B2C France : annulée et remboursée, donc exclue de la facturation
 ('CMD-2026-0005','CLI-0005','2026-09-05 11:00+02',NULL,'ANNULEE','CB',NULL),
 -- B2C France : bien + service (opération mixte)
 ('CMD-2026-0006','CLI-0001','2026-09-06 16:20+02','2026-09-10','LIVREE','CB',NULL),
 -- B2B France : virement à 30 jours, remise de ligne, éco-participation, port
 ('CMD-2026-0007','CLI-0101','2026-09-08 09:00+02','2026-09-14','LIVREE','VIR','BC-2026-118'),
 -- B2B France : bien + service, déjà payé, livraison à une autre adresse
 ('CMD-2026-0008','CLI-0102','2026-09-09 14:10+02','2026-09-15','LIVREE','CB','BC-AIX-77'),
 -- B2B France : acompte puis facture finale (cas n°20 et 21)
 ('CMD-2026-0009','CLI-0103','2026-09-02 10:00+02','2026-09-26','LIVREE','VIR','BC-HZ-2026-09'),
 -- B2B France : retour partiel, donc avoir
 ('CMD-2026-0010','CLI-0104','2026-09-16 08:30+02','2026-09-18','LIVREE','CB','DL-5521'),
 -- B2B UE : livraison intracommunautaire
 ('CMD-2026-0011','CLI-0201','2026-09-17 15:00+02','2026-09-22','LIVREE','VIR','PO-BT-889'),
 -- B2B UE : service, autoliquidation
 ('CMD-2026-0012','CLI-0202','2026-09-18 10:00+02','2026-09-23','LIVREE','VIR','PO-77120'),
 -- B2B hors UE : exportation
 ('CMD-2026-0013','CLI-0301','2026-09-19 09:40+02','2026-09-24','LIVREE','VIR','GS-4410'),
 -- B2B hors UE : service hors champ
 ('CMD-2026-0014','CLI-0301','2026-09-20 11:15+02','2026-09-25','LIVREE','VIR','GS-4418'),
 -- B2B France : en attente, pas encore facturée
 ('CMD-2026-0015','CLI-0101','2026-10-20 09:05+02',NULL,'EN_ATTENTE','VIR','BC-2026-140')
) v(numero, client, date_cmd, date_liv, statut, mode, ref)
JOIN client k ON k.numero = v.client
JOIN adresse af ON af.client_id = k.id AND af.usage = 'FACTURATION'
JOIN adresse al ON al.client_id = k.id AND al.usage = 'LIVRAISON';

INSERT INTO commande_ligne (commande_id, numero_ligne, article_id, libelle, quantite, prix_ht,
                            remise_id, remise_ht, eco_participation_ht,
                            categorie_tva_code, taux_tva, motif_exoneration_code)
SELECT c.id, v.no, a.id, a.libelle, v.qte, a.prix_ht, r.id,
       CASE WHEN r.id IS NULL THEN 0
            WHEN r.type_valeur = 'POURCENTAGE' THEN round(v.qte * a.prix_ht * r.valeur / 100, 2)
            ELSE r.valeur END,
       round(v.qte * a.eco_participation_ht, 2),
       t.categorie, t.taux_applique, t.motif
FROM (VALUES
 ('CMD-2026-0001',1,'LIV-0001', 2,NULL),
 ('CMD-2026-0001',2,'INF-0002', 1,NULL),
 ('CMD-2026-0002',1,'SRV-0001', 2,NULL),
 ('CMD-2026-0003',1,'ALI-0001', 3,NULL),
 ('CMD-2026-0003',2,'PRE-0001', 1,NULL),
 ('CMD-2026-0004',1,'INF-0003', 1,NULL),
 ('CMD-2026-0004',2,'LIV-0002', 1,NULL),
 ('CMD-2026-0005',1,'INF-0003', 2,NULL),
 ('CMD-2026-0006',1,'INF-0001', 1,NULL),
 ('CMD-2026-0006',2,'SRV-0003', 1,NULL),
 ('CMD-2026-0007',1,'INF-0001', 5,'VOLUME5'),
 ('CMD-2026-0007',2,'INF-0003', 5,NULL),
 ('CMD-2026-0008',1,'INF-0001', 1,NULL),
 ('CMD-2026-0008',2,'SRV-0002', 1,NULL),
 ('CMD-2026-0009',1,'SRV-0001',40,NULL),
 ('CMD-2026-0010',1,'INF-0002', 3,NULL),
 ('CMD-2026-0011',1,'INF-0002',10,'VOLUME5'),
 ('CMD-2026-0012',1,'SRV-0001', 8,NULL),
 ('CMD-2026-0013',1,'INF-0003',10,NULL),
 ('CMD-2026-0014',1,'SRV-0001', 5,NULL),
 ('CMD-2026-0015',1,'INF-0003', 4,NULL)
) v(cmd, no, sku, qte, code_remise)
JOIN commande c ON c.numero = v.cmd
JOIN client k ON k.id = c.client_id
JOIN adresse al ON al.id = c.adresse_livraison_id
JOIN article a ON a.sku = v.sku
LEFT JOIN remise r ON r.code = v.code_remise
CROSS JOIN LATERAL determiner_tva(k.type_client, al.pays_code, a.classe_tva_code, a.nature,
                                  c.date_commande::DATE) t;

SELECT appliquer_remise_commande(c.id, v.code)
FROM (VALUES ('CMD-2026-0001','BIENVENUE10'), ('CMD-2026-0008','FIXE20')) v(cmd, code)
JOIN commande c ON c.numero = v.cmd;

-- Frais de port : ajoutés après la remise, qui ne porte que sur les articles.
-- Simplification : le port suit le taux normal du pays de livraison, y compris
-- pour un panier à plusieurs taux.
INSERT INTO commande_ajustement (commande_id, sens, code_motif, libelle, montant_ht,
                                 categorie_tva_code, taux_tva, motif_exoneration_code)
SELECT c.id, 'FRAIS', 'FC', 'Frais de port', v.port, t.categorie, t.taux_applique, t.motif
FROM (VALUES ('CMD-2026-0001',5.90), ('CMD-2026-0004',9.90),
             ('CMD-2026-0007',24.00), ('CMD-2026-0011',49.00)) v(cmd, port)
JOIN commande c ON c.numero = v.cmd
JOIN client k ON k.id = c.client_id
JOIN adresse al ON al.id = c.adresse_livraison_id
CROSS JOIN LATERAL determiner_tva(k.type_client, al.pays_code, 'NORMAL', 'LB', c.date_commande::DATE) t;

-- -----------------------------------------------------------------------------
-- Transactions antérieures à la facturation
-- -----------------------------------------------------------------------------

-- Paiement comptant du total de la commande
INSERT INTO transaction_paiement (reference, commande_id, type_operation, statut, mode_paiement_code,
                                  montant, date_transaction, reference_psp)
SELECT 'TX-' || substr(c.numero, 5), c.id, 'PAIEMENT', 'CAPTUREE', c.mode_paiement_code,
       t.total_ttc, c.date_commande + INTERVAL '2 minutes', 'PSP-' || md5(c.numero)
FROM commande c
JOIN v_commande_total t ON t.commande_id = c.id
WHERE c.numero IN ('CMD-2026-0001','CMD-2026-0002','CMD-2026-0003','CMD-2026-0004',
                   'CMD-2026-0005','CMD-2026-0006','CMD-2026-0008','CMD-2026-0010');

-- Tentative refusée par la banque : aucun effet comptable ni fiscal
INSERT INTO transaction_paiement (reference, commande_id, type_operation, statut, mode_paiement_code,
                                  montant, date_transaction)
SELECT 'TX-2026-0003-ECHEC', id, 'PAIEMENT', 'ECHOUEE', 'CB', 9.99, date_commande
FROM commande WHERE numero = 'CMD-2026-0003';

-- Commande annulée : remboursement intégral
INSERT INTO transaction_paiement (reference, commande_id, type_operation, statut, mode_paiement_code,
                                  montant, date_transaction)
SELECT 'TX-2026-0005-RMB', c.id, 'REMBOURSEMENT', 'CAPTUREE', 'CB', -t.total_ttc,
       c.date_commande + INTERVAL '1 day'
FROM commande c JOIN v_commande_total t ON t.commande_id = c.id
WHERE c.numero = 'CMD-2026-0005';

-- Paiement partiel avant facture : BT-113 sera non nul
INSERT INTO transaction_paiement (reference, commande_id, type_operation, statut, mode_paiement_code,
                                  montant, date_transaction)
SELECT 'TX-2026-0007-1', id, 'PAIEMENT', 'CAPTUREE', 'VIR', 1000.00, '2026-09-12 10:00+02'
FROM commande WHERE numero = 'CMD-2026-0007';

-- -----------------------------------------------------------------------------
-- Listes de facturation
-- -----------------------------------------------------------------------------
INSERT INTO liste_facturation (numero, societe_id, periode_debut, periode_fin, statut) VALUES
 ('LF-2026-09', (SELECT id FROM societe), '2026-09-01', '2026-09-30', 'FACTUREE'),
 ('LF-2026-10', (SELECT id FROM societe), '2026-10-01', '2026-10-31', 'BROUILLON');

INSERT INTO liste_facturation_ligne (liste_id, commande_id, statut, motif_exclusion)
SELECT l.id, c.id,
       CASE WHEN c.statut = 'ANNULEE' THEN 'EXCLUE' ELSE 'A_FACTURER' END,
       CASE WHEN c.statut = 'ANNULEE' THEN 'Commande annulée et remboursée' END
FROM commande c
JOIN liste_facturation l ON l.numero =
     CASE WHEN c.date_commande < '2026-10-01' THEN 'LF-2026-09' ELSE 'LF-2026-10' END;

-- -----------------------------------------------------------------------------
-- Facture d'acompte (type 386) : TVA exigible à l'encaissement. Elle est déjà
-- payée, donc en cadre S2 : les cadres x4 sont réservés à la facture définitive
-- et interdits à un acompte (G1.60). BT-9 porte la date de versement (G1.18).
-- -----------------------------------------------------------------------------
INSERT INTO transaction_paiement (reference, commande_id, type_operation, statut, mode_paiement_code,
                                  montant, date_transaction)
SELECT 'TX-2026-0009-ACPT', id, 'PAIEMENT', 'CAPTUREE', 'VIR', 1728.00, '2026-09-03 09:00+02'
FROM commande WHERE numero = 'CMD-2026-0009';

DO $$
DECLARE
    v_commande BIGINT;
    v_acompte  BIGINT;
BEGIN
    SELECT id INTO STRICT v_commande FROM commande WHERE numero = 'CMD-2026-0009';
    v_acompte := creer_entete_facture(v_commande, '386', '2026-09-03', 'AC');

    INSERT INTO facture_ligne (facture_id, numero_ligne, quantite, unite_code, montant_net_ht,
                               prix_net_ht, categorie_tva_code, taux_tva, libelle, nature)
    VALUES (v_acompte, 1, 1, 'C62', 1440.00, 1440.00, 'S', 20.00,
            'Acompte de 30 % sur la formation, commande CMD-2026-0009', 'PS');
    UPDATE facture_ligne SET prix_brut_ht = prix_net_ht WHERE facture_id = v_acompte;

    UPDATE facture SET montant_paye = 1728.00 WHERE id = v_acompte;
    UPDATE transaction_paiement SET facture_id = v_acompte WHERE reference = 'TX-2026-0009-ACPT';
    PERFORM recalculer_facture(v_acompte);
    PERFORM qualifier_facture(v_acompte);
END $$;

-- -----------------------------------------------------------------------------
-- Factures de la liste de septembre, par date de livraison : la numérotation
-- doit suivre l'ordre chronologique
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT c.id, c.date_livraison, l.liste_id
        FROM liste_facturation_ligne l
        JOIN commande c ON c.id = l.commande_id
        WHERE l.statut = 'A_FACTURER' AND c.date_livraison IS NOT NULL
        ORDER BY c.date_livraison, c.numero
    LOOP
        PERFORM facturer_commande(r.id, r.date_livraison, r.liste_id);
    END LOOP;
END $$;

-- Facture définitive, cadre S4 : la base et la TVA sont celles restant dues,
-- donc l'acompte est repris sur une ligne négative, qui cite la facture d'acompte
-- (EXT-FR-FE-BG-06, prévu pour ces reprises). La quantité porte le signe car le
-- prix ne peut pas être négatif (G1.16). BT-113 reste à 0 : la reprise déduit
-- déjà l'acompte, le renseigner le déduirait une seconde fois.
DO $$
DECLARE
    v_finale  BIGINT;
    a         facture;
BEGIN
    SELECT f.id INTO STRICT v_finale
    FROM facture f JOIN commande c ON c.id = f.commande_id
    WHERE c.numero = 'CMD-2026-0009' AND f.type_code = '380';

    SELECT f.* INTO STRICT a
    FROM facture f JOIN commande c ON c.id = f.commande_id
    WHERE c.numero = 'CMD-2026-0009' AND f.type_code = '386';

    INSERT INTO facture_ligne (facture_id, numero_ligne, quantite, unite_code, montant_net_ht,
                               prix_net_ht, prix_brut_ht, categorie_tva_code, taux_tva, libelle,
                               nature, facture_anterieure_numero, facture_anterieure_date)
    VALUES (v_finale, 2, -1, 'C62', -1440.00, 1440.00, 1440.00, 'S', 20.00,
            'Reprise de l''acompte ' || a.numero, 'PS', a.numero, a.date_emission);

    PERFORM recalculer_facture(v_finale);
    PERFORM qualifier_facture(v_finale, '4');
END $$;

-- Avoir pour le retour d'un écran sur trois : les montants d'un avoir restent
-- positifs, c'est le type 381 qui en inverse le sens
DO $$
DECLARE
    v_commande BIGINT;
    v_avoir    BIGINT;
    v_ligne    BIGINT;
    i          facture;
BEGIN
    SELECT c.id, l.id INTO STRICT v_commande, v_ligne
    FROM commande c JOIN commande_ligne l ON l.commande_id = c.id
    WHERE c.numero = 'CMD-2026-0010';

    SELECT * INTO STRICT i FROM facture WHERE commande_id = v_commande AND type_code = '380';

    v_avoir := creer_entete_facture(v_commande, '381', '2026-09-28', 'AV');
    PERFORM ajouter_ligne_facture(v_avoir, 1, v_ligne, 1);

    INSERT INTO facture_reference_precedente (facture_id, numero, date_facture, facture_precedente_id)
    VALUES (v_avoir, i.numero, i.date_emission, i.id);

    PERFORM recalculer_facture(v_avoir);
    PERFORM qualifier_facture(v_avoir, '1');

    INSERT INTO transaction_paiement (reference, commande_id, facture_id, type_operation, statut,
                                      mode_paiement_code, montant, date_transaction)
    SELECT 'TX-2026-0010-RMB', v_commande, v_avoir, 'REMBOURSEMENT', 'CAPTUREE', 'CB',
           -total_ttc, '2026-09-29 11:00+02'
    FROM facture WHERE id = v_avoir;
END $$;

UPDATE liste_facturation_ligne SET statut = 'FACTUREE',
    facture_id = (SELECT f.id FROM facture f WHERE f.commande_id = liste_facturation_ligne.commande_id
                  AND f.type_code = '380')
WHERE statut = 'A_FACTURER'
  AND EXISTS (SELECT 1 FROM facture f WHERE f.commande_id = liste_facturation_ligne.commande_id);

-- -----------------------------------------------------------------------------
-- Transactions postérieures à la facturation
-- -----------------------------------------------------------------------------

-- Solde partiel de la commande 0007
INSERT INTO transaction_paiement (reference, commande_id, facture_id, type_operation, statut,
                                  mode_paiement_code, montant, date_transaction)
SELECT 'TX-2026-0007-2', f.commande_id, f.id, 'PAIEMENT', 'CAPTUREE', 'VIR', 1000.00, '2026-10-10 10:00+02'
FROM facture f JOIN commande c ON c.id = f.commande_id
WHERE c.numero = 'CMD-2026-0007';

-- Cas n°34 : encaissement annulé après fraude, en montant négatif, puis repaiement
INSERT INTO transaction_paiement (reference, commande_id, facture_id, type_operation, statut,
                                  mode_paiement_code, montant, date_transaction, reference_psp)
SELECT v.reference, f.commande_id, f.id, v.op, 'CAPTUREE', 'PAYPAL', v.signe * f.total_ttc,
       v.date_tx::TIMESTAMPTZ, v.psp
FROM facture f
JOIN commande c ON c.id = f.commande_id
CROSS JOIN (VALUES
  ('TX-2026-0002-ANN','ANNULATION',-1,'2026-09-20 09:00+02','PSP-CHARGEBACK-1'),
  ('TX-2026-0002-BIS','PAIEMENT',   1,'2026-09-21 14:00+02','PSP-REPAIEMENT-1')
) v(reference, op, signe, date_tx, psp)
WHERE c.numero = 'CMD-2026-0002';

-- Ventilation de chaque transaction par taux de TVA, au prorata du TTC. Le
-- dernier taux absorbe l'arrondi pour que la somme égale le montant.
INSERT INTO transaction_paiement_tva (transaction_id, categorie_tva_code, taux_tva, montant)
SELECT id, categorie_tva_code, taux_tva,
       CASE WHEN rang = nb
            THEN montant - coalesce(sum(part) OVER (PARTITION BY id ORDER BY rang
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
            ELSE part END
FROM (
    SELECT p.id, p.montant, v.categorie_tva_code, v.taux_tva,
           round(p.montant * (v.base_ht + v.montant_tva) / t.total_ttc, 2) AS part,
           row_number() OVER (PARTITION BY p.id ORDER BY v.base_ht DESC) AS rang,
           count(*) OVER (PARTITION BY p.id) AS nb
    FROM transaction_paiement p
    JOIN v_commande_tva v ON v.commande_id = p.commande_id
    JOIN v_commande_total t ON t.commande_id = p.commande_id
    WHERE p.statut = 'CAPTUREE'
) g;

-- -----------------------------------------------------------------------------
-- Avancement dans le cycle de vie (DSE §3.6.4). Seule la bulle e-invoicing porte
-- ces statuts : le e-reporting suit les siens, avec la transmission du flux 10.
-- -----------------------------------------------------------------------------
UPDATE facture f SET statut_code = v.statut
FROM (VALUES
 ('CMD-2026-0007','380',205),   -- approuvée, partiellement payée
 ('CMD-2026-0008','380',212),   -- encaissée
 ('CMD-2026-0009','386',212),   -- acompte encaissé
 ('CMD-2026-0009','380',203),   -- mise à disposition
 ('CMD-2026-0010','380',205),   -- approuvée
 ('CMD-2026-0010','381',204)    -- avoir pris en charge
) v(cmd, type_facture, statut)
JOIN commande c ON c.numero = v.cmd
WHERE f.commande_id = c.id AND f.type_code = v.type_facture;
