-- Contrôle de conformité : une ligne par règle violée. Première approche du
-- validateur, limitée aux règles exprimables en SQL les plus structurantes ; la
-- référence restera le schematron officiel EN 16931.
SET search_path = vente, public;

WITH lignes AS (
    SELECT facture_id, coalesce(sum(montant_net_ht), 0) AS total, count(*) AS nb
    FROM facture_ligne GROUP BY facture_id
),
ajust AS (
    SELECT facture_id,
           coalesce(sum(montant) FILTER (WHERE sens = 'REMISE'), 0) AS remises,
           coalesce(sum(montant) FILTER (WHERE sens = 'FRAIS'), 0)  AS frais
    FROM facture_ajustement GROUP BY facture_id
),
ventil AS (
    SELECT facture_id, coalesce(sum(base_ht), 0) AS base, coalesce(sum(montant_tva), 0) AS tva
    FROM facture_tva GROUP BY facture_id
),
-- Base attendue par groupe de TVA : lignes + frais - remises de ce groupe
base_attendue AS (
    SELECT facture_id, categorie_tva_code, taux_tva, sum(montant) AS base
    FROM (
        SELECT facture_id, categorie_tva_code, taux_tva, montant_net_ht AS montant FROM facture_ligne
        UNION ALL
        SELECT facture_id, categorie_tva_code, taux_tva,
               CASE sens WHEN 'FRAIS' THEN montant ELSE -montant END
        FROM facture_ajustement
    ) m
    GROUP BY 1, 2, 3
),
f AS (
    SELECT x.*, coalesce(l.total, 0) AS somme_lignes, coalesce(l.nb, 0) AS nb_lignes,
           coalesce(a.remises, 0) AS somme_remises, coalesce(a.frais, 0) AS somme_frais,
           coalesce(v.tva, 0) AS somme_tva
    FROM facture x
    LEFT JOIN lignes l ON l.facture_id = x.id
    LEFT JOIN ajust a  ON a.facture_id = x.id
    LEFT JOIN ventil v ON v.facture_id = x.id
),
violations (facture_id, regle, detail) AS (
    -- Présence
    SELECT id, 'BR-6',  'Nom du vendeur (BT-27) absent' FROM f WHERE vendeur_nom IS NULL
    UNION ALL SELECT id, 'BR-7',  'Nom de l''acheteur (BT-44) absent' FROM f WHERE acheteur_nom IS NULL
    UNION ALL SELECT id, 'BR-9',  'Pays du vendeur (BT-40) absent' FROM f WHERE vendeur_pays_code IS NULL
    UNION ALL SELECT id, 'BR-11', 'Pays de l''acheteur (BT-55) absent' FROM f WHERE acheteur_pays_code IS NULL
    UNION ALL SELECT id, 'BR-16', 'Aucune ligne de facture' FROM f WHERE nb_lignes = 0
    UNION ALL SELECT id, 'BR-CO-26', 'Aucun identifiant vendeur (BT-29, 30, 31)' FROM f
              WHERE vendeur_siret IS NULL AND vendeur_siren IS NULL AND vendeur_tva IS NULL
    UNION ALL SELECT id, 'BR-62', 'Adresse électronique vendeur sans schéma (BT-34-1)' FROM f
              WHERE vendeur_adresse_electronique IS NOT NULL AND vendeur_adresse_electronique_schema IS NULL
    UNION ALL SELECT id, 'BR-63', 'Adresse électronique acheteur sans schéma (BT-49-1)' FROM f
              WHERE acheteur_adresse_electronique IS NOT NULL AND acheteur_adresse_electronique_schema IS NULL
    UNION ALL SELECT facture_id, 'BR-55', 'Référence antérieure sans numéro (BT-25)'
              FROM facture_reference_precedente WHERE numero IS NULL

    -- Arithmétique
    UNION ALL SELECT l.facture_id, 'CALC-LIGNE', 'Ligne ' || l.numero_ligne || ' : BT-131 incohérent'
              FROM facture_ligne l
              LEFT JOIN LATERAL (
                  SELECT coalesce(sum(CASE sens WHEN 'FRAIS' THEN montant ELSE -montant END), 0) AS net
                  FROM facture_ligne_ajustement WHERE facture_ligne_id = l.id
              ) a ON TRUE
              WHERE l.montant_net_ht <> round(l.quantite * l.prix_net_ht / coalesce(l.base_quantite, 1), 2) + a.net
    UNION ALL SELECT id, 'BR-CO-10', 'BT-106 ' || total_lignes_ht || ' <> somme des lignes ' || somme_lignes
              FROM f WHERE total_lignes_ht IS DISTINCT FROM somme_lignes
    UNION ALL SELECT id, 'BR-CO-11', 'BT-107 <> somme des remises' FROM f
              WHERE coalesce(total_remises, 0) <> somme_remises
    UNION ALL SELECT id, 'BR-CO-12', 'BT-108 <> somme des frais' FROM f
              WHERE coalesce(total_frais, 0) <> somme_frais
    UNION ALL SELECT id, 'BR-CO-13', 'BT-109 ' || total_ht || ' <> BT-106 - BT-107 + BT-108'
              FROM f WHERE total_ht IS DISTINCT FROM
                    total_lignes_ht - coalesce(total_remises, 0) + coalesce(total_frais, 0)
    UNION ALL SELECT id, 'BR-CO-14', 'BT-110 <> somme des BT-117' FROM f
              WHERE total_tva IS DISTINCT FROM somme_tva
    UNION ALL SELECT id, 'BR-CO-15', 'BT-112 <> BT-109 + BT-110' FROM f
              WHERE total_ttc IS DISTINCT FROM total_ht + coalesce(total_tva, 0)
    UNION ALL SELECT id, 'BR-CO-16', 'BT-115 <> BT-112 - BT-113 + BT-114' FROM f
              WHERE net_a_payer IS DISTINCT FROM
                    total_ttc - coalesce(montant_paye, 0) + coalesce(arrondi, 0)
    UNION ALL SELECT facture_id, 'BR-CO-17',
                     'BT-117 ' || montant_tva || ' <> base x taux au taux ' || taux_tva
              FROM facture_tva
              WHERE montant_tva IS DISTINCT FROM round(base_ht * coalesce(taux_tva, 0) / 100, 2)
    UNION ALL SELECT coalesce(t.facture_id, b.facture_id), 'BASE-TVA',
                     'BT-116 incohérent pour ' || coalesce(t.categorie_tva_code, b.categorie_tva_code)
              FROM facture_tva t
              FULL JOIN base_attendue b
                ON b.facture_id = t.facture_id
               AND b.categorie_tva_code = t.categorie_tva_code
               AND b.taux_tva IS NOT DISTINCT FROM t.taux_tva
              WHERE t.base_ht IS DISTINCT FROM b.base

    -- Paiement
    UNION ALL SELECT id, 'BR-CO-25', 'Montant dû sans BT-9 ni BT-20' FROM f
              WHERE net_a_payer > 0 AND date_echeance IS NULL AND conditions_paiement IS NULL
    UNION ALL SELECT id, 'BR-61', 'Virement sans IBAN (BT-84)' FROM f
              WHERE code_moyen_paiement IN ('30','58') AND iban_beneficiaire IS NULL

    -- Catégories de TVA
    UNION ALL SELECT DISTINCT f.id, 'BR-' || CASE t.categorie_tva_code WHEN 'K' THEN 'IC' ELSE 'AE' END || '-2',
                     'Catégorie ' || t.categorie_tva_code || ' sans n° de TVA vendeur ou acheteur'
              FROM f JOIN facture_tva t ON t.facture_id = f.id
              WHERE t.categorie_tva_code IN ('K','AE')
                AND (f.vendeur_tva IS NULL OR f.acheteur_tva IS NULL)
    UNION ALL SELECT DISTINCT f.id, 'BR-G-2', 'Export sans n° de TVA vendeur'
              FROM f JOIN facture_tva t ON t.facture_id = f.id
              WHERE t.categorie_tva_code = 'G' AND f.vendeur_tva IS NULL
    UNION ALL SELECT DISTINCT f.id, 'BR-O-2', 'Hors champ avec un n° de TVA (BT-31 ou BT-48)'
              FROM f JOIN facture_tva t ON t.facture_id = f.id
              WHERE t.categorie_tva_code = 'O'
                AND (f.vendeur_tva IS NOT NULL OR f.acheteur_tva IS NOT NULL)
    UNION ALL SELECT DISTINCT f.id, 'BR-IC-11', 'Livraison UE sans date ni période (BT-72, 73, 74)'
              FROM f JOIN facture_tva t ON t.facture_id = f.id
              WHERE t.categorie_tva_code = 'K' AND f.date_livraison IS NULL
                AND f.periode_debut IS NULL AND f.periode_fin IS NULL
    UNION ALL SELECT DISTINCT f.id, 'BR-IC-12', 'Livraison UE sans pays de livraison (BT-80)'
              FROM f JOIN facture_tva t ON t.facture_id = f.id
              WHERE t.categorie_tva_code = 'K' AND f.livraison_pays_code IS NULL
    UNION ALL SELECT t.facture_id,
                     'BR-' || CASE t.categorie_tva_code WHEN 'K' THEN 'IC' ELSE t.categorie_tva_code END || '-10',
                     'Catégorie ' || t.categorie_tva_code || ' sans motif (BT-120, BT-121)'
              FROM facture_tva t
              JOIN categorie_tva c ON c.code = t.categorie_tva_code
              WHERE c.motif_requis AND t.motif IS NULL AND t.code_motif IS NULL

    -- Règles de gestion françaises (Annexe 7 v1.9)
    UNION ALL SELECT id, 'G1.02', 'Cadre de facturation (BT-23) absent' FROM f
              WHERE regime_transmission = 'E_INVOICING' AND cadre_facturation_code IS NULL
    UNION ALL SELECT id, 'G1.05', 'Numéro de facture invalide : ' || numero FROM f
              WHERE numero !~ '^[A-Za-z0-9 +_/-]{1,35}$'
                 OR numero ~ '^ | $|  '
    UNION ALL SELECT id, 'G1.12', 'Devise hors EUR sans BT-111' FROM f
              WHERE devise_code <> 'EUR' AND total_tva_devise_comptable IS NULL
    UNION ALL SELECT t.facture_id, 'G1.24', 'Taux non autorisé : ' || t.taux_tva
              FROM facture_tva t
              WHERE t.taux_tva NOT IN (0, 10, 13, 20, 8.5, 19.6, 2.1, 5.5, 7, 20.6, 1.05, 0.9, 1.75, 9.2, 9.6)
                AND NOT EXISTS (SELECT 1 FROM facture_ereporting e
                                WHERE e.facture_id = t.facture_id
                                  AND e.categorie_ereporting_code = 'TNT1')
    UNION ALL SELECT f.id, 'G1.31', 'Avoir : référence antérieure absente ou en double'
              FROM f
              JOIN type_facture y ON y.code = f.type_code AND y.est_avoir
              CROSS JOIN LATERAL (
                  SELECT (SELECT count(*) FROM facture_reference_precedente r WHERE r.facture_id = f.id) AS entete,
                         count(*) FILTER (WHERE l.facture_anterieure_numero IS NOT NULL) AS lignes_avec,
                         count(*) AS lignes
                  FROM facture_ligne l WHERE l.facture_id = f.id
              ) r
              WHERE (r.entete = 0 AND r.lignes_avec < r.lignes)
                 OR (r.entete > 0 AND r.lignes_avec > 0)
    UNION ALL SELECT id, 'G1.60', 'Cadre après acompte sur une facture d''acompte' FROM f
              WHERE cadre_facturation_code IN ('B4','S4','M4') AND type_code IN ('386','500','503')
    UNION ALL SELECT id, 'G1.63', 'SIREN vendeur ou acheteur absent en e-invoicing' FROM f
              WHERE regime_transmission = 'E_INVOICING'
                AND (vendeur_siren IS NULL OR acheteur_siren IS NULL)
)
SELECT f.numero, v.regle, v.detail
FROM violations v
JOIN facture f ON f.id = v.facture_id
ORDER BY f.numero, v.regle;
