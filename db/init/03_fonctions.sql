-- Fonctions métier : détermination de la TVA, numérotation et génération des
-- factures. Les données de test passent par elles pour que leurs montants
-- soient calculés, et non saisis à la main.
SET search_path = vente, public;

-- Règle de TVA d'une vente, selon l'acheteur et la destination.
-- Simplification : le seuil OSS de 10 000 EUR est supposé dépassé, donc une
-- vente à un particulier de l'UE porte toujours le taux du pays de destination.
CREATE FUNCTION determiner_tva(
    p_type_client TEXT, p_pays_livraison CHAR(2), p_classe TEXT, p_nature TEXT, p_date DATE,
    OUT categorie TEXT, OUT taux_applique NUMERIC, OUT motif TEXT
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_ue BOOLEAN;
BEGIN
    SELECT membre_ue INTO STRICT v_ue FROM pays WHERE code = p_pays_livraison;

    IF p_type_client = 'ASSUJETTI_UE' AND p_nature = 'LB' THEN
        categorie := 'K';  taux_applique := 0;  motif := 'VATEX-EU-IC';
    ELSIF p_type_client = 'ASSUJETTI_UE' THEN
        categorie := 'AE'; taux_applique := 0;  motif := 'VATEX-EU-AE';
    ELSIF NOT v_ue AND p_nature = 'LB' THEN
        categorie := 'G';  taux_applique := 0;  motif := 'VATEX-EU-G';
    ELSIF NOT v_ue THEN
        categorie := 'O';  taux_applique := NULL; motif := 'VATEX-EU-O';
    ELSE
        categorie := 'S';
        SELECT t.taux INTO STRICT taux_applique
        FROM taux_tva t
        WHERE t.pays_code = p_pays_livraison
          AND t.classe_code = p_classe
          AND p_date <@ daterange(t.date_debut, t.date_fin);
    END IF;
END $$;

CREATE FUNCTION prochain_numero_facture(p_societe BIGINT, p_serie TEXT, p_annee INTEGER)
RETURNS TEXT LANGUAGE sql AS $$
    INSERT INTO compteur_facture AS c (societe_id, serie, annee, dernier_numero)
    VALUES (p_societe, p_serie, p_annee, 1)
    ON CONFLICT (societe_id, serie, annee)
    DO UPDATE SET dernier_numero = c.dernier_numero + 1
    RETURNING p_serie || '-' || p_annee || '-' || lpad(dernier_numero::TEXT, 6, '0');
$$;

-- Répartit une remise de panier entre les taux, au prorata de leur base, car
-- EN 16931 impose un taux par remise (BT-96). Le dernier taux absorbe l'écart
-- d'arrondi pour que la somme des parts égale exactement le montant total.
CREATE FUNCTION appliquer_remise_commande(p_commande BIGINT, p_code TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_remise remise;
    v_total  NUMERIC;
    v_a_repartir NUMERIC;
    v_reste  NUMERIC;
    v_part   NUMERIC;
    g        RECORD;
BEGIN
    SELECT * INTO STRICT v_remise FROM remise WHERE code = p_code;
    SELECT total_ht INTO STRICT v_total FROM v_commande_total WHERE commande_id = p_commande;

    v_a_repartir := CASE v_remise.type_valeur
                      WHEN 'POURCENTAGE' THEN round(v_total * v_remise.valeur / 100, 2)
                      ELSE v_remise.valeur END;
    v_reste := v_a_repartir;

    FOR g IN
        SELECT *, row_number() OVER (ORDER BY base_ht DESC) AS rang, count(*) OVER () AS nb
        FROM v_commande_tva WHERE commande_id = p_commande
    LOOP
        v_part := CASE WHEN g.rang = g.nb THEN v_reste
                       ELSE round(v_a_repartir * g.base_ht / v_total, 2) END;
        v_reste := v_reste - v_part;
        INSERT INTO commande_ajustement
            (commande_id, sens, remise_id, code_motif, libelle, montant_ht,
             categorie_tva_code, taux_tva, motif_exoneration_code)
        VALUES (p_commande, 'REMISE', v_remise.id, v_remise.code_motif, v_remise.libelle,
                v_part, g.categorie_tva_code, g.taux_tva, g.motif_exoneration_code);
    END LOOP;
END $$;

-- Crée l'en-tête d'une facture : la copie des données de la commande, du vendeur
-- et du client constitue l'instantané qui ne bougera plus.
CREATE FUNCTION creer_entete_facture(
    p_commande BIGINT, p_type CHAR(3), p_date DATE, p_serie TEXT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    c commande; s societe; k client; af adresse; al adresse; mp mode_paiement;
    v_id BIGINT;
    v_nom TEXT;
    v_regime TEXT;
    v_b2b BOOLEAN;
    v_schema TEXT;
BEGIN
    SELECT * INTO STRICT c  FROM commande WHERE id = p_commande;
    SELECT * INTO STRICT s  FROM societe WHERE id = c.societe_id;
    SELECT * INTO STRICT k  FROM client  WHERE id = c.client_id;
    SELECT * INTO STRICT af FROM adresse WHERE id = c.adresse_facturation_id;
    SELECT * INTO STRICT al FROM adresse WHERE id = c.adresse_livraison_id;
    SELECT * INTO STRICT mp FROM mode_paiement WHERE code = c.mode_paiement_code;
    SELECT valeur INTO STRICT v_schema FROM parametre WHERE cle = 'adresse_electronique_schema';

    v_nom := coalesce(k.raison_sociale, trim(coalesce(k.prenom, '') || ' ' || k.nom));
    v_b2b := k.type_client <> 'PARTICULIER';
    v_regime := CASE k.type_client
                  WHEN 'PARTICULIER'  THEN 'E_REPORTING_B2C'
                  WHEN 'ASSUJETTI_FR' THEN 'E_INVOICING'
                  ELSE 'E_REPORTING_B2B_INTL' END;

    INSERT INTO facture (
        societe_id, commande_id, client_id,
        numero, date_emission, type_code, devise_code, code_date_exigibilite,
        reference_commande_acheteur, reference_commande_vendeur,
        vendeur_nom, vendeur_nom_commercial, vendeur_siret, vendeur_siren, vendeur_tva,
        vendeur_forme_juridique, vendeur_adresse_electronique, vendeur_adresse_electronique_schema,
        vendeur_adresse_ligne1, vendeur_adresse_ligne2, vendeur_ville, vendeur_code_postal,
        vendeur_pays_code, vendeur_contact_nom, vendeur_contact_telephone, vendeur_contact_email,
        acheteur_nom, acheteur_identifiant, acheteur_identifiant_schema, acheteur_siren,
        acheteur_tva, acheteur_adresse_electronique, acheteur_adresse_electronique_schema,
        acheteur_adresse_ligne1, acheteur_adresse_ligne2, acheteur_adresse_ligne3,
        acheteur_ville, acheteur_code_postal, acheteur_subdivision, acheteur_pays_code,
        livraison_nom, date_livraison,
        livraison_adresse_ligne1, livraison_adresse_ligne2, livraison_adresse_ligne3,
        livraison_ville, livraison_code_postal, livraison_pays_code,
        code_moyen_paiement, libelle_moyen_paiement, reference_paiement,
        iban_beneficiaire, bic_beneficiaire,
        regime_transmission, option_tva_debits, format_echange)
    VALUES (
        c.societe_id, c.id, c.client_id,
        prochain_numero_facture(c.societe_id, p_serie, EXTRACT(YEAR FROM p_date)::INT),
        p_date, p_type, c.devise_code, CASE WHEN s.option_tva_debits THEN '5' END,
        c.reference_client, c.numero,
        s.raison_sociale, s.nom_commercial, s.siret, s.siren, s.tva_intra,
        s.forme_juridique, s.siren, v_schema,
        s.adresse_ligne1, s.adresse_ligne2, s.ville, s.code_postal,
        s.pays_code, s.contact_nom, s.telephone, s.email,
        v_nom, coalesce(k.code_routage, k.siret),
        CASE WHEN k.code_routage IS NOT NULL THEN '0224'
             WHEN k.siret IS NOT NULL THEN '0009' END,
        k.siren, k.tva_intra,
        k.siren, CASE WHEN k.siren IS NOT NULL THEN v_schema END,
        af.ligne1, af.ligne2, af.ligne3, af.ville, af.code_postal, af.subdivision, af.pays_code,
        al.destinataire, c.date_livraison,
        al.ligne1, al.ligne2, al.ligne3, al.ville, al.code_postal, al.pays_code,
        mp.code_uncl4461, mp.libelle, c.numero,
        CASE WHEN c.mode_paiement_code = 'VIR' THEN s.iban END,
        CASE WHEN c.mode_paiement_code = 'VIR' THEN s.bic END,
        v_regime, s.option_tva_debits,
        CASE WHEN v_regime <> 'E_REPORTING_B2C' THEN
            (SELECT valeur FROM parametre WHERE cle = 'format_echange_defaut') END)
    RETURNING id INTO v_id;

    -- Mentions obligatoires entre professionnels
    IF v_b2b THEN
        INSERT INTO facture_note (facture_id, code_sujet, texte)
        SELECT v_id, n.code, p.valeur
        FROM (VALUES ('PMD','note_penalites'), ('PMT','note_indemnite'), ('AAB','note_escompte')) n(code, cle)
        JOIN parametre p ON p.cle = n.cle;
    END IF;

    RETURN v_id;
END $$;

-- Copie une ligne de commande en ligne de facture (avec sa remise et son
-- éco-participation en BG-27 / BG-28), pour une quantité donnée.
CREATE FUNCTION ajouter_ligne_facture(
    p_facture BIGINT, p_numero INTEGER, p_ligne BIGINT, p_quantite NUMERIC
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    l commande_ligne; a article;
    v_ligne BIGINT;
    v_ratio NUMERIC;
    v_remise NUMERIC;
    v_eco NUMERIC;
    v_note TEXT;
BEGIN
    SELECT * INTO STRICT l FROM commande_ligne WHERE id = p_ligne;
    SELECT * INTO STRICT a FROM article WHERE id = l.article_id;

    v_ratio  := p_quantite / l.quantite;
    v_remise := round(l.remise_ht * v_ratio, 2);
    v_eco    := round(l.eco_participation_ht * v_ratio, 2);
    SELECT valeur INTO STRICT v_note FROM parametre WHERE cle = 'note_eco_participation';

    INSERT INTO facture_ligne (
        facture_id, commande_ligne_id, numero_ligne, note, note_code_sujet,
        quantite, unite_code, montant_net_ht, prix_net_ht, prix_brut_ht, categorie_tva_code, taux_tva, libelle, description,
        reference_vendeur, gtin, gtin_schema, nature, motif_exoneration_code)
    VALUES (
        p_facture, l.id, p_numero,
        CASE WHEN v_eco > 0 THEN v_note END, CASE WHEN v_eco > 0 THEN 'BLU' END,
        p_quantite, a.unite_code,
        round(p_quantite * l.prix_ht, 2) - v_remise + v_eco,
        l.prix_ht, l.prix_ht, l.categorie_tva_code, l.taux_tva, l.libelle, a.description,
        a.sku, a.gtin, CASE WHEN a.gtin IS NOT NULL THEN '0160' END, a.nature,
        l.motif_exoneration_code)
    RETURNING id INTO v_ligne;

    IF v_remise > 0 THEN
        INSERT INTO facture_ligne_ajustement (facture_ligne_id, sens, montant, motif, code_motif)
        SELECT v_ligne, 'REMISE', v_remise, r.libelle, r.code_motif
        FROM remise r WHERE r.id = l.remise_id;
    END IF;
    IF v_eco > 0 THEN
        INSERT INTO facture_ligne_ajustement (facture_ligne_id, sens, montant, motif, code_motif)
        VALUES (v_ligne, 'FRAIS', v_eco, 'Éco-participation', 'AEO');
    END IF;
END $$;

-- Reconstruit BG-23 et BG-22 à partir des lignes et des ajustements.
CREATE FUNCTION recalculer_facture(p_facture BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM facture_tva WHERE facture_id = p_facture;

    INSERT INTO facture_tva (facture_id, categorie_tva_code, taux_tva, base_ht, montant_tva, motif, code_motif)
    SELECT p_facture, m.categorie, m.taux, sum(m.base),
           round(sum(m.base) * coalesce(m.taux, 0) / 100, 2),
           x.libelle, m.motif
    FROM (
        SELECT categorie_tva_code AS categorie, taux_tva AS taux,
               motif_exoneration_code AS motif, montant_net_ht AS base
        FROM facture_ligne WHERE facture_id = p_facture
        UNION ALL
        SELECT categorie_tva_code, taux_tva, motif_exoneration_code,
               CASE sens WHEN 'FRAIS' THEN montant ELSE -montant END
        FROM facture_ajustement WHERE facture_id = p_facture
    ) m
    LEFT JOIN motif_exoneration x ON x.code = m.motif
    GROUP BY m.categorie, m.taux, m.motif, x.libelle;

    UPDATE facture f SET
        total_lignes_ht = t.lignes,
        total_remises   = t.remises,
        total_frais     = t.frais,
        total_ht        = t.lignes - t.remises + t.frais,
        total_tva       = t.tva,
        total_ttc       = t.lignes - t.remises + t.frais + t.tva,
        montant_paye    = coalesce(f.montant_paye, 0),
        net_a_payer     = t.lignes - t.remises + t.frais + t.tva
                          - coalesce(f.montant_paye, 0) + coalesce(f.arrondi, 0)
    FROM (
        SELECT
          (SELECT coalesce(sum(montant_net_ht), 0) FROM facture_ligne WHERE facture_id = p_facture) AS lignes,
          (SELECT coalesce(sum(montant), 0) FROM facture_ajustement
            WHERE facture_id = p_facture AND sens = 'REMISE') AS remises,
          (SELECT coalesce(sum(montant), 0) FROM facture_ajustement
            WHERE facture_id = p_facture AND sens = 'FRAIS') AS frais,
          (SELECT coalesce(sum(montant_tva), 0) FROM facture_tva WHERE facture_id = p_facture) AS tva
    ) t
    WHERE f.id = p_facture;
END $$;

-- Ventile une facture B2C par catégorie e-reporting. Pour chaque taux, base et
-- TVA se répartissent au prorata des lignes de biens et de services, le dernier
-- groupe absorbant l'arrondi. Un taux sans ligne (port seul) reste en bien. Une
-- TVA étrangère ne déclare que le HT, avec un taux 0 (DSE §2.3.3).
CREATE FUNCTION declarer_facture_b2c(p_facture BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_etranger BOOLEAN;
BEGIN
    SELECT livraison_pays_code <> 'FR' INTO STRICT v_etranger FROM facture WHERE id = p_facture;
    DELETE FROM facture_ereporting WHERE facture_id = p_facture;

    INSERT INTO facture_ereporting (facture_id, categorie_ereporting_code, taux_tva, base_ht, montant_tva)
    SELECT p_facture, categorie, taux_declare, sum(base), sum(tva)
    FROM (
        SELECT CASE WHEN v_etranger THEN 'TNT1'
                    WHEN nature = 'PS' THEN 'TPS1' ELSE 'TLB1' END AS categorie,
               CASE WHEN v_etranger THEN 0 ELSE coalesce(taux_tva, 0) END AS taux_declare,
               CASE WHEN rang = nb
                    THEN base_ht - coalesce(sum(part_base) OVER w, 0) ELSE part_base END AS base,
               CASE WHEN v_etranger THEN 0
                    WHEN rang = nb THEN montant_tva - coalesce(sum(part_tva) OVER w, 0)
                    ELSE part_tva END AS tva
        FROM (
            SELECT t.id, t.taux_tva, t.base_ht, t.montant_tva, n.nature,
                   round(t.base_ht * n.base / sum(n.base) OVER g, 2) AS part_base,
                   round(t.montant_tva * n.base / sum(n.base) OVER g, 2) AS part_tva,
                   row_number() OVER (PARTITION BY t.id ORDER BY n.nature) AS rang,
                   count(*) OVER (PARTITION BY t.id) AS nb
            FROM facture_tva t
            LEFT JOIN (
                SELECT categorie_tva_code, taux_tva, nature, sum(montant_net_ht) AS base
                FROM facture_ligne WHERE facture_id = p_facture
                GROUP BY 1, 2, 3
            ) n ON n.categorie_tva_code = t.categorie_tva_code
               AND n.taux_tva IS NOT DISTINCT FROM t.taux_tva
            WHERE t.facture_id = p_facture
            WINDOW g AS (PARTITION BY t.id)
        ) r
        WINDOW w AS (PARTITION BY id ORDER BY rang ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
    ) d
    GROUP BY categorie, taux_declare;
END $$;

-- Renseigne BT-23, BT-20, BT-9 et, pour le B2C, la déclaration e-reporting : ces
-- données dépendent du contenu final de la facture.
CREATE FUNCTION qualifier_facture(p_facture BIGINT, p_suffixe_cadre TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    f facture;
    v_nature CHAR(1);
    v_suffixe TEXT;
BEGIN
    SELECT * INTO STRICT f FROM facture WHERE id = p_facture;

    SELECT CASE WHEN bool_and(nature = 'LB') THEN 'B'
                WHEN bool_and(nature = 'PS') THEN 'S' ELSE 'M' END
    INTO v_nature FROM facture_ligne WHERE facture_id = p_facture AND nature IS NOT NULL;

    v_suffixe := coalesce(p_suffixe_cadre, CASE WHEN f.net_a_payer = 0 THEN '2' ELSE '1' END);

    UPDATE facture SET
        -- Hors champ de la TVA : pas de n° de TVA vendeur (BR-O-2)
        vendeur_tva = CASE WHEN EXISTS (SELECT 1 FROM facture_ligne
                                        WHERE facture_id = p_facture AND categorie_tva_code = 'O')
                           THEN NULL ELSE vendeur_tva END,
        cadre_facturation_code = v_nature || v_suffixe,
        conditions_paiement = CASE WHEN regime_transmission <> 'E_REPORTING_B2C' AND net_a_payer > 0
            THEN (SELECT valeur FROM parametre WHERE cle = 'conditions_paiement_b2b') END,
        -- Facture déjà payée : l'échéance est la date de paiement (cas n°2)
        date_echeance = CASE
            WHEN net_a_payer = 0 THEN coalesce(
                (SELECT max(date_transaction)::DATE FROM transaction_paiement
                  WHERE facture_id = p_facture AND statut = 'CAPTUREE'), date_emission)
            WHEN regime_transmission <> 'E_REPORTING_B2C' THEN
                date_emission + (SELECT valeur::INT FROM parametre WHERE cle = 'delai_paiement_jours')
            ELSE date_emission END
    WHERE id = p_facture;

    IF f.regime_transmission = 'E_REPORTING_B2C' THEN
        PERFORM declarer_facture_b2c(p_facture);
    END IF;

    -- Une TVA étrangère doit être clairement désignée sur la facture (DSE §2.3.3)
    IF f.livraison_pays_code <> 'FR'
       AND EXISTS (SELECT 1 FROM facture_tva WHERE facture_id = p_facture AND categorie_tva_code = 'S')
       AND NOT EXISTS (SELECT 1 FROM facture_note WHERE facture_id = p_facture AND texte LIKE 'TVA facturée%')
    THEN
        INSERT INTO facture_note (facture_id, code_sujet, texte)
        SELECT p_facture, 'AAI', 'TVA facturée : TVA du pays de livraison, ' || nom
        FROM pays WHERE code = f.livraison_pays_code;
    END IF;
END $$;

-- Facture une commande entière. Les paiements déjà capturés et non rattachés
-- à une facture sont imputés en BT-113.
CREATE FUNCTION facturer_commande(p_commande BIGINT, p_date DATE, p_liste BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_id BIGINT;
    v_serie TEXT;
    v_paye NUMERIC;
BEGIN
    SELECT valeur INTO STRICT v_serie FROM parametre WHERE cle = 'serie_facture';
    v_id := creer_entete_facture(p_commande, '380', p_date, v_serie);

    PERFORM ajouter_ligne_facture(v_id, numero_ligne, id, quantite)
    FROM commande_ligne WHERE commande_id = p_commande ORDER BY numero_ligne;

    INSERT INTO facture_ajustement (facture_id, sens, montant, categorie_tva_code, taux_tva,
                                    motif, code_motif, motif_exoneration_code)
    SELECT v_id, sens, montant_ht, categorie_tva_code, taux_tva, libelle, code_motif,
           motif_exoneration_code
    FROM commande_ajustement WHERE commande_id = p_commande;

    SELECT coalesce(sum(montant), 0) INTO v_paye
    FROM transaction_paiement
    WHERE commande_id = p_commande AND facture_id IS NULL AND statut = 'CAPTUREE'
      AND date_transaction::DATE <= p_date;

    UPDATE facture SET montant_paye = v_paye WHERE id = v_id;
    UPDATE transaction_paiement SET facture_id = v_id
    WHERE commande_id = p_commande AND facture_id IS NULL AND statut = 'CAPTUREE'
      AND date_transaction::DATE <= p_date;

    PERFORM recalculer_facture(v_id);
    PERFORM qualifier_facture(v_id);

    IF p_liste IS NOT NULL THEN
        UPDATE liste_facturation_ligne SET facture_id = v_id, statut = 'FACTUREE'
        WHERE liste_id = p_liste AND commande_id = p_commande;
    END IF;

    RETURN v_id;
END $$;
