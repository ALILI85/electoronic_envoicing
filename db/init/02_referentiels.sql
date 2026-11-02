-- Paramétrage et référentiels, alignés sur les spécifications externes v3.2.
SET search_path = vente, public;

INSERT INTO parametre (cle, valeur, description) VALUES
 ('delai_paiement_jours',   '30',  'Échéance B2B par défaut (BT-9)'),
 ('serie_facture',          'FA',  'Préfixe de la série des factures'),
 ('serie_avoir',            'AV',  'Préfixe de la série des avoirs'),
 ('serie_acompte',          'AC',  'Préfixe de la série des factures d''acompte'),
 ('format_echange_defaut',  'FACTURX', 'Format du socle utilisé en émission'),
 ('adresse_electronique_schema', '0225',
  'Schéma de BT-34 / BT-49 : FRCTC ELECTRONIC ADDRESS (Annexe 7). Format détaillé dans AFNOR XP Z12-012, non fournie'),
 ('conditions_paiement_b2b', 'Paiement à 30 jours date de facture', 'Texte BT-20'),
 ('note_penalites', 'Pénalités de retard : 3 fois le taux d''intérêt légal.', 'Note PMD (BT-22)'),
 ('note_indemnite', 'Indemnité forfaitaire pour frais de recouvrement : 40 EUR.', 'Note PMT (BT-22)'),
 ('note_escompte',  'Pas d''escompte pour paiement anticipé.', 'Note AAB (BT-22, G1.52)'),
 ('note_eco_participation', 'Eco-participation (L. 541-10 du code de l''environnement)', 'Note BLU (BT-127, G1.52)');

INSERT INTO pays (code, nom, membre_ue) VALUES
 ('FR','France',TRUE), ('DE','Allemagne',TRUE), ('BE','Belgique',TRUE),
 ('ES','Espagne',TRUE), ('IT','Italie',TRUE), ('CH','Suisse',FALSE),
 ('GB','Royaume-Uni',FALSE), ('US','États-Unis',FALSE);

INSERT INTO devise (code, nom) VALUES
 ('EUR','Euro'), ('CHF','Franc suisse'), ('GBP','Livre sterling'), ('USD','Dollar américain');

INSERT INTO unite_mesure (code, libelle) VALUES
 ('C62','Unité'), ('HUR','Heure'), ('DAY','Jour'), ('KGM','Kilogramme'),
 ('MTR','Mètre'), ('LTR','Litre');

INSERT INTO mode_paiement (code, libelle, code_uncl4461) VALUES
 ('CB',     'Carte bancaire',          '48'),
 ('VIR',    'Virement SEPA',           '58'),
 ('PRLV',   'Prélèvement SEPA',        '59'),
 ('PAYPAL', 'Service de paiement en ligne', '68');

-- G1.01 : les autres codes UNTDID 1001 ne doivent pas être utilisés
INSERT INTO type_facture (code, libelle, est_avoir) VALUES
 ('380','Facture commerciale',                    FALSE),
 ('389','Facture auto-facturée',                  FALSE),
 ('393','Facture affacturée',                     FALSE),
 ('501','Facture auto-facturée affacturée',       FALSE),
 ('386','Facture d''acompte',                     FALSE),
 ('500','Facture d''acompte auto-facturée',       FALSE),
 ('384','Facture rectificative',                  FALSE),
 ('471','Facture rectificative auto-facturée',    FALSE),
 ('472','Facture rectificative affacturée',       FALSE),
 ('473','Facture rectificative auto-facturée affacturée', FALSE),
 ('381','Avoir',                                  TRUE),
 ('261','Avoir auto-facturé',                     TRUE),
 ('396','Avoir affacturé',                        TRUE),
 ('502','Avoir auto-facturé affacturé',           TRUE),
 ('503','Avoir de facture d''acompte',            TRUE);

-- G1.02. L'Annexe 6 cite aussi S3, absent de cette règle : non retenu.
INSERT INTO cadre_facturation (code, libelle, nature) VALUES
 ('B1','Dépôt d''une facture de bien',                                  'LB'),
 ('S1','Dépôt d''une facture de prestation de service',                 'PS'),
 ('M1','Dépôt d''une facture double',                                   'LBPS'),
 ('B2','Dépôt d''une facture de bien déjà payée',                       'LB'),
 ('S2','Dépôt d''une facture de prestation de service déjà payée',      'PS'),
 ('M2','Dépôt d''une facture double déjà payée',                        'LBPS'),
 ('B4','Dépôt d''une facture définitive (après acompte) de bien',       'LB'),
 ('S4','Dépôt d''une facture définitive (après acompte) de service',    'PS'),
 ('M4','Dépôt d''une facture définitive (après acompte) double',        'LBPS'),
 ('S5','Dépôt par un sous-traitant d''une facture de prestation de service', 'PS'),
 ('S6','Dépôt par un cotraitant d''une facture de prestation de service',    'PS'),
 ('B7','Dépôt d''une facture de bien ayant fait l''objet d''un e-reporting (TVA déjà collectée)',    'LB'),
 ('S7','Dépôt d''une facture de service ayant fait l''objet d''un e-reporting (TVA déjà collectée)', 'PS');

-- DSE §3.6.4. Seuls les statuts obligatoires vont au PPF (G7.44).
INSERT INTO statut_facture (code, libelle, transmission, producteur) VALUES
 (200,'Déposée',                'Obligatoire','Plateforme agréée d''émission'),
 (201,'Émise par la plateforme','Facultatif', 'Plateforme agréée d''émission'),
 (202,'Reçue par la plateforme','Facultatif', 'Plateforme agréée de réception'),
 (203,'Mise à disposition',     'Facultatif', 'Plateforme agréée de réception'),
 (204,'Prise en charge',        'Facultatif', 'Destinataire'),
 (205,'Approuvée',              'Facultatif', 'Destinataire'),
 (206,'Approuvée partiellement','Facultatif', 'Destinataire'),
 (207,'En litige',              'Facultatif', 'Destinataire'),
 (208,'Suspendue',              'Facultatif', 'Destinataire'),
 (209,'Complétée',              'Facultatif', 'Fournisseur'),
 (210,'Refusée',                'Obligatoire','Destinataire'),
 (211,'Paiement transmis',      'Facultatif', 'Destinataire ou fournisseur'),
 (212,'Encaissée',              'Obligatoire','Fournisseur'),
 (213,'Rejetée',                'Obligatoire','Plateforme agréée d''émission ou de réception');

-- G1.68. TMX1 (DSE v2.1) a disparu : biens et services se déclarent séparément.
INSERT INTO categorie_ereporting (code, libelle) VALUES
 ('TLB1','Livraisons de biens soumises à la TVA'),
 ('TPS1','Prestations de services soumises à la TVA'),
 ('TNT1','Opérations non soumises à la TVA en France, dont ventes à distance UE'),
 ('TMA1','Opérations soumises au régime de la TVA sur la marge');

-- G2.31 : L et M ne sont pas pertinents en France
INSERT INTO categorie_tva (code, libelle, motif_requis) VALUES
 ('S', 'Taux normal ou réduit',                 FALSE),
 ('Z', 'Taux zéro',                             FALSE),
 ('E', 'Exonérée',                              TRUE),
 ('AE','Autoliquidation',                       TRUE),
 ('K', 'Livraison intracommunautaire',          TRUE),
 ('G', 'Exportation hors UE',                   TRUE),
 ('O', 'Hors champ de la TVA',                  TRUE);

INSERT INTO motif_exoneration (code, libelle) VALUES
 ('VATEX-EU-AE','Autoliquidation'),
 ('VATEX-EU-IC','Livraison intracommunautaire exonérée, article 262 ter I du CGI'),
 ('VATEX-EU-G', 'Exportation exonérée, article 262 I du CGI'),
 ('VATEX-EU-O', 'Hors champ de la TVA');

INSERT INTO classe_tva (code, libelle) VALUES
 ('NORMAL',        'Taux normal'),
 ('INTERMEDIAIRE', 'Taux intermédiaire'),
 ('REDUIT',        'Taux réduit (livres, alimentation)'),
 ('PARTICULIER',   'Taux particulier (presse)');

INSERT INTO taux_tva (pays_code, classe_code, taux, date_debut) VALUES
 ('FR','NORMAL',20.00,'2014-01-01'), ('FR','INTERMEDIAIRE',10.00,'2014-01-01'),
 ('FR','REDUIT',5.50,'2014-01-01'),  ('FR','PARTICULIER',2.10,'2014-01-01'),
 ('DE','NORMAL',19.00,'2021-01-01'), ('DE','REDUIT',7.00,'2021-01-01'),
 ('BE','NORMAL',21.00,'2021-01-01'), ('BE','REDUIT',6.00,'2021-01-01');

-- DSE §3.7.7, tableau 13 : délais de transmission à la plateforme agréée.
-- La fiche e-reporting annonce la suppression du régime simplifié au 01/01/2027.
INSERT INTO regime_tva (code, libelle, frequence_transactions, delai_transactions,
                        frequence_paiements, delai_paiements) VALUES
 ('REEL_MENSUEL',    'Régime réel normal mensuel',
  'Par décade', 'Le 20 du mois, le dernier jour du mois, le 10 du mois suivant',
  'Mensuelle',  'Le 10 du mois suivant'),
 ('REEL_TRIMESTRIEL','Régime réel normal trimestriel',
  'Mensuelle',  'Le 10 du mois suivant',
  'Mensuelle',  'Le 10 du mois suivant'),
 ('SIMPLIFIE',       'Régime simplifié d''imposition',
  'Mensuelle',  'Le dernier jour du mois suivant',
  'Mensuelle',  'Le dernier jour du mois suivant'),
 ('FRANCHISE',       'Franchise en base de TVA',
  'Bimestrielle', 'Le dernier jour du mois suivant la période',
  'Bimestrielle', 'Le dernier jour du mois suivant la période');
