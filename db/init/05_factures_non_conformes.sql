-- Jeu d'essai négatif pour le futur validateur : des factures reçues et pas encore
-- contrôlées (statut NULL, car 200 attesterait leur conformité), chacune sciemment
-- fautive. La note AAI annonce la ou les règles attendues par db/controles.sql, ce
-- qui permet de vérifier le contrôle lui-même.
-- Série KO séparée : elles n'entament pas la numérotation réelle.
SET search_path = vente, public;

CREATE FUNCTION pg_temp.cloner(p_commande TEXT, p_regles TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_commande BIGINT;
    v_id BIGINT;
BEGIN
    SELECT id INTO STRICT v_commande FROM commande WHERE numero = p_commande;
    v_id := creer_entete_facture(v_commande, '380', '2026-10-15', 'KO');

    PERFORM ajouter_ligne_facture(v_id, numero_ligne, id, quantite)
    FROM commande_ligne WHERE commande_id = v_commande ORDER BY numero_ligne;

    INSERT INTO facture_ajustement (facture_id, sens, montant, categorie_tva_code, taux_tva,
                                    motif, code_motif, motif_exoneration_code)
    SELECT v_id, sens, montant_ht, categorie_tva_code, taux_tva, libelle, code_motif,
           motif_exoneration_code
    FROM commande_ajustement WHERE commande_id = v_commande;

    PERFORM recalculer_facture(v_id);
    PERFORM qualifier_facture(v_id);
    INSERT INTO facture_note (facture_id, code_sujet, texte) VALUES (v_id, 'AAI', 'KO attendu : ' || p_regles);
    RETURN v_id;
END $$;

DO $$
DECLARE
    v BIGINT;
BEGIN
    -- Total HT faux : le détail ne redonne pas BT-109, et BT-112 ne suit plus
    v := pg_temp.cloner('CMD-2026-0007', 'BR-CO-13,BR-CO-15');
    UPDATE facture SET total_ht = total_ht + 10 WHERE id = v;

    -- TVA mal calculée, totaux cohérents entre eux
    v := pg_temp.cloner('CMD-2026-0007', 'BR-CO-17');
    UPDATE facture_tva SET montant_tva = montant_tva + 0.50 WHERE facture_id = v;
    UPDATE facture SET total_tva = total_tva + 0.50, total_ttc = total_ttc + 0.50,
                       net_a_payer = net_a_payer + 0.50 WHERE id = v;

    -- Livraison intracommunautaire sans n° de TVA de l'acheteur
    v := pg_temp.cloner('CMD-2026-0011', 'BR-IC-2');
    UPDATE facture SET acheteur_tva = NULL WHERE id = v;

    -- Autoliquidation sans motif d'exonération
    v := pg_temp.cloner('CMD-2026-0012', 'BR-AE-10');
    UPDATE facture_tva SET motif = NULL, code_motif = NULL WHERE facture_id = v;

    -- Montant dû sans échéance ni conditions de paiement
    v := pg_temp.cloner('CMD-2026-0007', 'BR-CO-25');
    UPDATE facture SET date_echeance = NULL, conditions_paiement = NULL WHERE id = v;

    -- Virement sans IBAN
    v := pg_temp.cloner('CMD-2026-0007', 'BR-61');
    UPDATE facture SET iban_beneficiaire = NULL WHERE id = v;

    -- E-invoicing domestique sans SIREN client
    v := pg_temp.cloner('CMD-2026-0007', 'G1.63');
    UPDATE facture SET acheteur_siren = NULL WHERE id = v;

    -- Taux de TVA hors de la liste autorisée, totaux cohérents
    v := pg_temp.cloner('CMD-2026-0007', 'G1.24');
    UPDATE facture_ligne SET taux_tva = 21 WHERE facture_id = v;
    UPDATE facture_ajustement SET taux_tva = 21 WHERE facture_id = v;
    PERFORM recalculer_facture(v);

    -- Facture d'acompte portant un cadre de facture définitive
    v := pg_temp.cloner('CMD-2026-0007', 'G1.60');
    UPDATE facture SET type_code = '386', cadre_facturation_code = 'B4' WHERE id = v;

    -- Avoir sans référence à la facture d'origine
    v := pg_temp.cloner('CMD-2026-0007', 'G1.31');
    UPDATE facture SET type_code = '381' WHERE id = v;

    -- Numéro de facture avec un caractère interdit
    v := pg_temp.cloner('CMD-2026-0007', 'G1.05');
    UPDATE facture SET numero = numero || '#1' WHERE id = v;

    -- Devise hors EUR sans TVA en euros
    v := pg_temp.cloner('CMD-2026-0007', 'G1.12');
    UPDATE facture SET devise_code = 'USD' WHERE id = v;

    -- Hors champ de la TVA mais n° de TVA vendeur présent
    v := pg_temp.cloner('CMD-2026-0014', 'BR-O-2');
    UPDATE facture SET vendeur_tva = 'FR64990012346' WHERE id = v;

    -- Référence à une facture antérieure sans numéro
    v := pg_temp.cloner('CMD-2026-0010', 'BR-55');
    INSERT INTO facture_reference_precedente (facture_id, numero, date_facture)
    VALUES (v, NULL, '2026-09-18');
END $$;
