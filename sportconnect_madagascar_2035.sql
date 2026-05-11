-- ==========================================================
--  SportConnect Madagascar 2035
--  Base de données MySQL — v1.0
--  Étudiant : ANDRIANTSIFERANTSOA Tantely Khenny
--  NIE : SE20240122 | ESMIA INNOVATION | L2 Informatique
--  Avril 2026
-- ==========================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE DATABASE IF NOT EXISTS sportconnect_mg2035
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE sportconnect_mg2035;

-- ==========================================================
-- TABLE 1 : Utilisateur
-- Rôles : joueur | coach | vendeur | admin
-- ==========================================================
CREATE TABLE IF NOT EXISTS Utilisateur (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nom           VARCHAR(100)  NOT NULL,
    prenom        VARCHAR(100)  NOT NULL,
    email         VARCHAR(191)  NOT NULL UNIQUE,
    hash_mdp      VARCHAR(255)  NOT NULL,           -- bcrypt
    telephone     VARCHAR(20),
    sport         VARCHAR(50),                       -- sport principal
    niveau        TINYINT UNSIGNED DEFAULT 1         -- niveau 1-5
                  CHECK (niveau BETWEEN 1 AND 5),
    objectif      VARCHAR(100),                      -- fitness / compétition / loisir
    lat           DECIMAL(10, 7),
    lng           DECIMAL(10, 7),
    langue        ENUM('FR','MG') NOT NULL DEFAULT 'FR',
    role          ENUM('joueur','coach','vendeur','admin') NOT NULL DEFAULT 'joueur',
    actif         BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_role   (role),
    INDEX idx_sport  (sport),
    INDEX idx_niveau (niveau)
) ENGINE=InnoDB COMMENT='Tous les utilisateurs de la plateforme (M1-M9)';

-- ==========================================================
-- TABLE 2 : Coach
-- Profil étendu pour les utilisateurs role=coach
-- ==========================================================
CREATE TABLE IF NOT EXISTS Coach (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id         INT UNSIGNED NOT NULL UNIQUE,
    sport           VARCHAR(50)  NOT NULL,
    certifications  TEXT,                            -- JSON liste de certifs
    tarif_heure     DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    bio             TEXT,
    langue_coaching ENUM('FR','MG','FR_MG') NOT NULL DEFAULT 'FR',
    badge_certifie  BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Utilisateur(id) ON DELETE CASCADE,
    INDEX idx_sport   (sport),
    INDEX idx_tarif   (tarif_heure)
) ENGINE=InnoDB COMMENT='Profil coach — matching k-NN (M6)';

-- ==========================================================
-- TABLE 3 : Terrain
-- Gestion des complexes sportifs (M1, M2, M4)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Terrain (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nom         VARCHAR(150)  NOT NULL,
    sport       VARCHAR(50)   NOT NULL,
    adresse     VARCHAR(255),
    ville       VARCHAR(100),
    lat         DECIMAL(10,7),
    lng         DECIMAL(10,7),
    capacite    TINYINT UNSIGNED NOT NULL DEFAULT 2,  -- équipes ou joueurs max
    prix_heure  DECIMAL(8,2)  NOT NULL DEFAULT 0.00,
    statut      ENUM('disponible','maintenance','ferme') NOT NULL DEFAULT 'disponible',
    created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sport  (sport),
    INDEX idx_ville  (ville),
    INDEX idx_statut (statut)
) ENGINE=InnoDB COMMENT='Terrains sportifs — AVL Tree indexation (M1, M4)';

-- ==========================================================
-- TABLE 4 : Creneau
-- Plages horaires par terrain (Priority Queue M1)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Creneau (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    terrain_id   INT UNSIGNED NOT NULL,
    date_creneau DATE         NOT NULL,
    heure_debut  TIME         NOT NULL,
    heure_fin    TIME         NOT NULL,
    statut       ENUM('libre','reserve','complet','annule') NOT NULL DEFAULT 'libre',
    FOREIGN KEY (terrain_id) REFERENCES Terrain(id) ON DELETE CASCADE,
    UNIQUE KEY uq_terrain_creneau (terrain_id, date_creneau, heure_debut),
    INDEX idx_date_statut (date_creneau, statut)
) ENGINE=InnoDB COMMENT='Créneaux horaires — HashMap O(1) + Min-Heap (M1)';

-- ==========================================================
-- TABLE 5 : Reservation
-- Réservations joueur → créneau (M1, M4)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Reservation (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id      INT UNSIGNED NOT NULL,
    creneau_id   INT UNSIGNED NOT NULL,
    date_resa    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    statut       ENUM('en_attente','confirmee','annulee','terminee') NOT NULL DEFAULT 'en_attente',
    type         ENUM('individuelle','groupe','tournoi') NOT NULL DEFAULT 'individuelle',
    montant      DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    ref_paiement VARCHAR(100),                       -- ref Mobile Money
    FOREIGN KEY (user_id)    REFERENCES Utilisateur(id) ON DELETE RESTRICT,
    FOREIGN KEY (creneau_id) REFERENCES Creneau(id)    ON DELETE RESTRICT,
    INDEX idx_user_statut   (user_id, statut),
    INDEX idx_creneau       (creneau_id),
    INDEX idx_date_resa     (date_resa)
) ENGINE=InnoDB COMMENT='Réservations — glouton O(n log n) vs FCFS baseline (M1)';

-- ==========================================================
-- TABLE 6 : FileAttente
-- File d'attente intelligente si créneau complet (M1)
-- Min-Heap géré côté applicatif — enregistrement ici
-- ==========================================================
CREATE TABLE IF NOT EXISTS FileAttente (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id      INT UNSIGNED NOT NULL,
    creneau_id   INT UNSIGNED NOT NULL,
    priorite     TINYINT UNSIGNED NOT NULL DEFAULT 5,  -- 1=haute 10=basse
    date_ajout   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    statut       ENUM('en_attente','promu','expire') NOT NULL DEFAULT 'en_attente',
    FOREIGN KEY (user_id)    REFERENCES Utilisateur(id) ON DELETE CASCADE,
    FOREIGN KEY (creneau_id) REFERENCES Creneau(id)    ON DELETE CASCADE,
    INDEX idx_creneau_priorite (creneau_id, priorite)
) ENGINE=InnoDB COMMENT='File d attente Priority Queue — Min-Heap (M1)';

-- ==========================================================
-- TABLE 7 : Partie
-- Match/partie lié à une réservation (M2, M8)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Partie (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    resa_id          INT UNSIGNED NOT NULL,
    niveau_requis    TINYINT UNSIGNED DEFAULT 1
                     CHECK (niveau_requis BETWEEN 1 AND 5),
    places_restantes TINYINT UNSIGNED DEFAULT 10,
    statut           ENUM('ouverte','en_cours','terminee','annulee') NOT NULL DEFAULT 'ouverte',
    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (resa_id) REFERENCES Reservation(id) ON DELETE CASCADE,
    INDEX idx_statut (statut)
) ENGINE=InnoDB COMMENT='Partie / match — matching adversaires Dijkstra (M8)';

-- ==========================================================
-- TABLE 8 : Participation
-- Association joueur ↔ partie (M2, M8)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Participation (
    id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    partie_id INT UNSIGNED NOT NULL,
    user_id   INT UNSIGNED NOT NULL,
    equipe    TINYINT UNSIGNED DEFAULT 1,            -- 1 ou 2
    statut    ENUM('inscrit','present','absent','forfait') NOT NULL DEFAULT 'inscrit',
    FOREIGN KEY (partie_id) REFERENCES Partie(id)       ON DELETE CASCADE,
    FOREIGN KEY (user_id)   REFERENCES Utilisateur(id)  ON DELETE CASCADE,
    UNIQUE KEY uq_participation (partie_id, user_id),
    INDEX idx_user (user_id)
) ENGINE=InnoDB COMMENT='Joueurs participants à une partie (M2, M8)';

-- ==========================================================
-- TABLE 9 : Match_Live
-- Données temps réel d'un match (WebSocket + Fenwick Tree)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Match_Live (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    partie_id    INT UNSIGNED NOT NULL UNIQUE,
    score_eq1    TINYINT UNSIGNED DEFAULT 0,
    score_eq2    TINYINT UNSIGNED DEFAULT 0,
    mi_temps     TINYINT UNSIGNED DEFAULT 1,         -- 1 ou 2
    statut_live  ENUM('attente','en_jeu','pause','termine') NOT NULL DEFAULT 'attente',
    started_at   DATETIME,
    ended_at     DATETIME,
    FOREIGN KEY (partie_id) REFERENCES Partie(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='Suivi live — WebSocket + Fenwick Tree agrégats (M2)';

-- ==========================================================
-- TABLE 10 : Evenement_Match
-- Événements dans un match live (buts, fautes…)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Evenement_Match (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    match_id    INT UNSIGNED NOT NULL,
    type        ENUM('but','panier','point','faute','carton','temps_mort','fin_mt','fin_match','autre') NOT NULL,
    joueur_id   INT UNSIGNED,
    minute      TINYINT UNSIGNED,
    description VARCHAR(255),
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (match_id)  REFERENCES Match_Live(id)   ON DELETE CASCADE,
    FOREIGN KEY (joueur_id) REFERENCES Utilisateur(id)  ON DELETE SET NULL,
    INDEX idx_match  (match_id),
    INDEX idx_minute (match_id, minute)
) ENGINE=InnoDB COMMENT='Événements live — Sliding Window / Fenwick Tree (M2)';

-- ==========================================================
-- TABLE 11 : Historique_Match
-- Archive des résultats de matchs (M4)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Historique_Match (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id        INT UNSIGNED NOT NULL,
    adversaire_id  INT UNSIGNED,
    terrain_id     INT UNSIGNED,
    sport          VARCHAR(50),
    resultat       ENUM('victoire','defaite','nul') NOT NULL,
    score_joueur   TINYINT UNSIGNED DEFAULT 0,
    score_adversaire TINYINT UNSIGNED DEFAULT 0,
    date_match     DATE NOT NULL,
    FOREIGN KEY (user_id)       REFERENCES Utilisateur(id) ON DELETE CASCADE,
    FOREIGN KEY (adversaire_id) REFERENCES Utilisateur(id) ON DELETE SET NULL,
    FOREIGN KEY (terrain_id)    REFERENCES Terrain(id)     ON DELETE SET NULL,
    INDEX idx_user_date (user_id, date_match),
    INDEX idx_resultat  (resultat)
) ENGINE=InnoDB COMMENT='Historique matchs — AVL + Fenwick Tree requêtes intervalle (M4)';

-- ==========================================================
-- TABLE 12 : Seance_Coaching
-- Séances coach / joueur (M6)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Seance_Coaching (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    coach_id   INT UNSIGNED NOT NULL,
    joueur_id  INT UNSIGNED NOT NULL,
    date_seance DATETIME    NOT NULL,
    duree_min  SMALLINT UNSIGNED DEFAULT 60,
    type       ENUM('individuelle','groupe','visio') NOT NULL DEFAULT 'individuelle',
    statut     ENUM('planifiee','confirmee','terminee','annulee') NOT NULL DEFAULT 'planifiee',
    montant    DECIMAL(8,2) DEFAULT 0.00,
    ref_paiement VARCHAR(100),
    notes      TEXT,
    FOREIGN KEY (coach_id)  REFERENCES Coach(id)        ON DELETE RESTRICT,
    FOREIGN KEY (joueur_id) REFERENCES Utilisateur(id)  ON DELETE RESTRICT,
    INDEX idx_coach_date  (coach_id, date_seance),
    INDEX idx_joueur_date (joueur_id, date_seance)
) ENGINE=InnoDB COMMENT='Séances coaching — k-NN matching + AVL agenda (M6)';

-- ==========================================================
-- TABLE 13 : Programme_Fitness
-- Programme personnalisé généré par l'IA (M7, M3)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Programme_Fitness (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id      INT UNSIGNED NOT NULL,
    objectif     ENUM('force','endurance','perte_poids','prise_masse','flexibilite') NOT NULL,
    niveau       TINYINT UNSIGNED DEFAULT 1
                 CHECK (niveau BETWEEN 1 AND 5),
    contenu_json JSON          NOT NULL,             -- programme généré par arbre décision
    actif        BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Utilisateur(id) ON DELETE CASCADE,
    INDEX idx_user_objectif (user_id, objectif)
) ENGINE=InnoDB COMMENT='Programme IA — Arbre de décision (M3, M7)';

-- ==========================================================
-- TABLE 14 : Journal_Entrainement
-- Séances de musculation enregistrées (M7)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Journal_Entrainement (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id         INT UNSIGNED NOT NULL,
    programme_id    INT UNSIGNED,
    date_seance     DATE         NOT NULL,
    exercices_json  JSON         NOT NULL,           -- [{nom, series, reps, poids_kg}]
    duree_min       SMALLINT UNSIGNED DEFAULT 0,
    calories_est    SMALLINT UNSIGNED DEFAULT 0,
    imc             DECIMAL(5,2),
    notes           TEXT,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id)      REFERENCES Utilisateur(id)     ON DELETE CASCADE,
    FOREIGN KEY (programme_id) REFERENCES Programme_Fitness(id) ON DELETE SET NULL,
    INDEX idx_user_date (user_id, date_seance)
) ENGINE=InnoDB COMMENT='Journal musculation — Fenwick Tree progression (M7)';

-- ==========================================================
-- TABLE 15 : Produit
-- Catalogue e-shop (M5)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Produit (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    vendeur_id  INT UNSIGNED NOT NULL,
    nom         VARCHAR(200) NOT NULL,
    sport       VARCHAR(50),
    categorie   VARCHAR(100),
    description TEXT,
    prix        DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    stock       SMALLINT UNSIGNED DEFAULT 0,
    images_json JSON,                                -- tableau d'URL images
    actif       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (vendeur_id) REFERENCES Utilisateur(id) ON DELETE RESTRICT,
    INDEX idx_sport_cat (sport, categorie),
    INDEX idx_prix      (prix),
    FULLTEXT  ft_nom_desc (nom, description)
) ENGINE=InnoDB COMMENT='Catalogue e-shop — Trie autocomplétion + k-NN CF (M5)';

-- ==========================================================
-- TABLE 16 : Commande
-- Commandes e-shop (M5)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Commande (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id          INT UNSIGNED NOT NULL,
    produits_json    JSON         NOT NULL,          -- [{produit_id, qte, prix_unit}]
    montant_total    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    statut           ENUM('panier','payee','en_livraison','livree','annulee') NOT NULL DEFAULT 'panier',
    adresse_livraison VARCHAR(255),
    ville_livraison  VARCHAR(100),
    ref_paiement     VARCHAR(100),
    created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                     ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Utilisateur(id) ON DELETE RESTRICT,
    INDEX idx_user_statut (user_id, statut),
    INDEX idx_statut      (statut)
) ENGINE=InnoDB COMMENT='Commandes e-shop — Dijkstra livraison 6 villes MG (M5)';

-- ==========================================================
-- TABLE 17 : Notification
-- Notifications push/SMS multi-canal (tous modules)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Notification (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id     INT UNSIGNED NOT NULL,
    message     TEXT         NOT NULL,
    canal       ENUM('push','sms','email','in_app') NOT NULL DEFAULT 'push',
    statut      ENUM('en_attente','envoye','echoue','lu') NOT NULL DEFAULT 'en_attente',
    module_ref  VARCHAR(10),                         -- M1, M2…M9
    date_envoi  DATETIME,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Utilisateur(id) ON DELETE CASCADE,
    INDEX idx_user_statut  (user_id, statut),
    INDEX idx_date_envoi   (date_envoi)
) ENGINE=InnoDB COMMENT='Notifications SMS/Push basse consommation réseau (tous modules)';

-- ==========================================================
-- TABLE 18 : Evaluation
-- Notes et commentaires (terrains, coaches, produits, joueurs)
-- ==========================================================
CREATE TABLE IF NOT EXISTS Evaluation (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    evaluateur_id  INT UNSIGNED NOT NULL,
    cible_id       INT UNSIGNED NOT NULL,
    type_cible     ENUM('terrain','coach','produit','joueur','vendeur') NOT NULL,
    note           TINYINT UNSIGNED NOT NULL
                   CHECK (note BETWEEN 1 AND 5),
    commentaire    TEXT,
    date_eval      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (evaluateur_id) REFERENCES Utilisateur(id) ON DELETE CASCADE,
    INDEX idx_cible (cible_id, type_cible),
    INDEX idx_evaluateur (evaluateur_id)
) ENGINE=InnoDB COMMENT='Évaluations — score pondéré moyenne mobile (M5, M6)';

-- ==========================================================
-- RÉACTIVATION DES CONTRAINTES
-- ==========================================================
SET FOREIGN_KEY_CHECKS = 1;

-- ==========================================================
-- DONNÉES DE TEST — Jeu de données synthétique
-- ==========================================================

-- Utilisateurs (1 admin, 2 coaches, 3 joueurs, 1 vendeur)
INSERT INTO Utilisateur (nom, prenom, email, hash_mdp, telephone, sport, niveau, objectif, lat, lng, langue, role) VALUES
('ANDRIANTSIFERANTSOA', 'Tantely',   'tantely@sportconnect.mg',  '$2b$10$hashAdminXXXXXXXXXXXXXX', '+261341000001', 'football',    5, 'competition', -18.9101, 47.5362, 'FR', 'admin'),
('RAKOTO',             'Aina',      'aina.coach@sportconnect.mg','$2b$10$hashCoach1XXXXXXXXXX',    '+261341000002', 'football',    4, 'loisir',      -18.9150, 47.5400, 'MG', 'coach'),
('RASOA',              'Nirina',    'nirina.c@sportconnect.mg',  '$2b$10$hashCoach2XXXXXXXXXX',    '+261341000003', 'basketball',  4, 'competition', -18.9200, 47.5350, 'FR', 'coach'),
('RAMAROLAHY',         'Toky',      'toky@sportconnect.mg',      '$2b$10$hashJoueur1XXXXXXXXX',   '+261341000004', 'football',    3, 'loisir',      -18.9100, 47.5300, 'MG', 'joueur'),
('RANDRIANASOLO',      'Hery',      'hery@sportconnect.mg',      '$2b$10$hashJoueur2XXXXXXXXX',   '+261341000005', 'basketball',  2, 'endurance',   -18.9250, 47.5450, 'FR', 'joueur'),
('RAZAFIMAHAZO',       'Tiana',     'tiana@sportconnect.mg',     '$2b$10$hashJoueur3XXXXXXXXX',   '+261341000006', 'tennis',      3, 'force',       -18.9080, 47.5380, 'MG', 'joueur'),
('SPORT',              'Malagasy',  'boutique@sportconnect.mg',  '$2b$10$hashVendeurXXXXXXXX',    '+261341000007', NULL,          1, NULL,          -18.9120, 47.5320, 'FR', 'vendeur');

-- Profils coaches
INSERT INTO Coach (user_id, sport, certifications, tarif_heure, bio, badge_certifie) VALUES
(2, 'football',   '["Brevet Fédéral FMF", "Licence UEFA C"]', 25000.00, 'Coach football 8 ans expérience, Antananarivo.',   TRUE),
(3, 'basketball',  '["FIBA Level 1"]',                          20000.00, 'Coach basketball, ancienne joueuse nationale MG.', TRUE);

-- Terrains
INSERT INTO Terrain (nom, sport, adresse, ville, lat, lng, capacite, prix_heure, statut) VALUES
('Stade Municipe Mahamasina',   'football',   'Mahamasina, Antananarivo',        'Antananarivo', -18.9146, 47.5361, 22, 50000.00, 'disponible'),
('Complexe Ankorondrano',        'basketball', 'Ankorondrano, Antananarivo',      'Antananarivo', -18.9020, 47.5450, 10, 30000.00, 'disponible'),
('Court Tennis Ivandry',         'tennis',     'Ivandry, Antananarivo',           'Antananarivo', -18.8950, 47.5500,  4, 20000.00, 'disponible'),
('Terrain Toamasina Centre',     'football',   'Bd Joffre, Toamasina',            'Toamasina',   -18.1433, 49.4012, 22, 35000.00, 'disponible'),
('Salle Omnisports Fianarantsoa','basketball', 'Centre Fianarantsoa',             'Fianarantsoa', -21.4534, 47.0866, 10, 25000.00, 'disponible'),
('Terrain Badminton Mahajanga',  'badminton',  'Mahajanga Ville',                 'Mahajanga',    -15.7171, 46.3163,  4, 15000.00, 'disponible');

-- Créneaux
INSERT INTO Creneau (terrain_id, date_creneau, heure_debut, heure_fin, statut) VALUES
(1, '2026-05-10', '08:00:00', '10:00:00', 'libre'),
(1, '2026-05-10', '10:00:00', '12:00:00', 'reserve'),
(1, '2026-05-10', '14:00:00', '16:00:00', 'libre'),
(2, '2026-05-10', '09:00:00', '10:00:00', 'libre'),
(2, '2026-05-10', '15:00:00', '16:00:00', 'libre'),
(3, '2026-05-11', '07:00:00', '08:00:00', 'libre'),
(3, '2026-05-11', '17:00:00', '18:00:00', 'libre');

-- Réservations
INSERT INTO Reservation (user_id, creneau_id, statut, type, montant) VALUES
(4, 2, 'confirmee', 'individuelle', 100000.00),
(5, 4, 'confirmee', 'individuelle',  30000.00);

-- Parties
INSERT INTO Partie (resa_id, niveau_requis, places_restantes, statut) VALUES
(1, 3, 18, 'ouverte'),
(2, 2,  8, 'ouverte');

-- Participations
INSERT INTO Participation (partie_id, user_id, equipe) VALUES
(1, 4, 1),
(2, 5, 1),
(2, 6, 2);

-- Match live
INSERT INTO Match_Live (partie_id, score_eq1, score_eq2, statut_live, started_at) VALUES
(2, 12, 8, 'en_jeu', NOW());

-- Événements match
INSERT INTO Evenement_Match (match_id, type, joueur_id, minute, description) VALUES
(1, 'panier', 5, 5,  'Panier à 2pts Hery'),
(1, 'panier', 6, 12, 'Panier à 3pts Tiana');

-- Historique matchs
INSERT INTO Historique_Match (user_id, adversaire_id, terrain_id, sport, resultat, score_joueur, score_adversaire, date_match) VALUES
(4, 5, 1, 'football',   'victoire', 3, 1, '2026-04-15'),
(5, 4, 1, 'football',   'defaite',  1, 3, '2026-04-15'),
(5, 6, 2, 'basketball', 'victoire', 85, 70, '2026-04-20');

-- Séances coaching
INSERT INTO Seance_Coaching (coach_id, joueur_id, date_seance, duree_min, type, statut, montant) VALUES
(1, 4, '2026-05-12 09:00:00', 60, 'individuelle', 'confirmee', 25000.00),
(2, 5, '2026-05-13 10:00:00', 90, 'individuelle', 'planifiee',  30000.00);

-- Programmes fitness
INSERT INTO Programme_Fitness (user_id, objectif, niveau, contenu_json) VALUES
(4, 'endurance', 3, '[{"semaine":1,"seances":[{"jour":"Lundi","exercices":["Course 30min","Gainage 3x1min"]},{"jour":"Jeudi","exercices":["Vélo 20min","Squats 3x15"]}]}]'),
(5, 'force',     2, '[{"semaine":1,"seances":[{"jour":"Mardi","exercices":["Pompes 4x10","Tractions 3x8"]},{"jour":"Vendredi","exercices":["Soulevé de terre 3x8","Développé couché 3x10"]}]}]');

-- Journaux entraînement
INSERT INTO Journal_Entrainement (user_id, programme_id, date_seance, exercices_json, duree_min, calories_est, imc) VALUES
(4, 1, '2026-05-05', '[{"nom":"Course","duree_min":30,"distance_km":4},{"nom":"Gainage","series":3,"duree_sec":60}]', 45, 380, 22.5),
(5, 2, '2026-05-06', '[{"nom":"Pompes","series":4,"reps":10},{"nom":"Tractions","series":3,"reps":8}]',              40, 290, 23.1);

-- Produits e-shop
INSERT INTO Produit (vendeur_id, nom, sport, categorie, description, prix, stock) VALUES
(7, 'Ballon de football Adidas Tiro',   'football',   'Ballon',  'Ballon officiel taille 5, cousu main.',          45000.00, 20),
(7, 'Chaussures Nike Mercurial T42',    'football',   'Chaussure','Crampons terrain naturel, taille 42.',          120000.00, 10),
(7, 'Ballon basketball Spalding NBA',   'basketball', 'Ballon',  'Taille officielle 7, grip supérieur.',            55000.00, 15),
(7, 'Raquette de tennis Wilson Ultra',  'tennis',     'Raquette','Raquette 275g, manche L3.',                      95000.00,  8),
(7, 'Protéine Whey Vanilla 1kg',        NULL,         'Nutrition','Protéine de lactosérum, 25g/dose.',             85000.00, 30);

-- Commandes
INSERT INTO Commande (user_id, produits_json, montant_total, statut, adresse_livraison, ville_livraison) VALUES
(4, '[{"produit_id":1,"qte":1,"prix_unit":45000},{"produit_id":5,"qte":1,"prix_unit":85000}]', 130000.00, 'payee',     'Analakely Lot 12', 'Antananarivo'),
(5, '[{"produit_id":3,"qte":1,"prix_unit":55000}]',                                              55000.00, 'en_livraison','Toamasina Centre', 'Toamasina');

-- Notifications
INSERT INTO Notification (user_id, message, canal, statut, module_ref) VALUES
(4, 'Votre réservation du terrain Mahamasina est confirmée pour le 10/05.', 'sms',  'envoye', 'M1'),
(5, 'Nouvelle recommandation d\'adversaire disponible : Tiana (niveau 3).',  'push', 'envoye', 'M3'),
(6, 'Séance coaching avec Coach Aina planifiée le 12/05 à 09h00.',          'push', 'envoye', 'M6');

-- Évaluations
INSERT INTO Evaluation (evaluateur_id, cible_id, type_cible, note, commentaire) VALUES
(4, 1, 'terrain', 5, 'Excellent terrain, bien entretenu.'),
(5, 2, 'coach',   5, 'Coach très professionnel, à recommander !'),
(4, 1, 'produit', 4, 'Bon ballon, livraison rapide à Tana.');

-- ==========================================================
-- VUES UTILES
-- ==========================================================

-- Vue disponibilités terrains
CREATE OR REPLACE VIEW v_disponibilites AS
SELECT
    t.id AS terrain_id,
    t.nom AS terrain,
    t.sport,
    t.ville,
    t.prix_heure,
    c.id AS creneau_id,
    c.date_creneau,
    c.heure_debut,
    c.heure_fin,
    c.statut
FROM Terrain t
JOIN Creneau c ON c.terrain_id = t.id
WHERE t.statut = 'disponible'
ORDER BY c.date_creneau, c.heure_debut;

-- Vue statistiques joueur
CREATE OR REPLACE VIEW v_stats_joueur AS
SELECT
    u.id,
    CONCAT(u.prenom,' ',u.nom) AS joueur,
    u.sport,
    u.niveau,
    COUNT(r.id)                              AS total_reservations,
    SUM(r.montant)                           AS total_depense_ariary,
    COUNT(hm.id)                             AS matchs_joues,
    SUM(hm.resultat = 'victoire')            AS victoires,
    SUM(hm.resultat = 'defaite')             AS defaites,
    SUM(hm.resultat = 'nul')                 AS nuls
FROM Utilisateur u
LEFT JOIN Reservation r     ON r.user_id = u.id AND r.statut = 'confirmee'
LEFT JOIN Historique_Match hm ON hm.user_id = u.id
WHERE u.role = 'joueur'
GROUP BY u.id;

-- Vue taux occupation terrains
CREATE OR REPLACE VIEW v_occupation_terrain AS
SELECT
    t.id,
    t.nom,
    t.sport,
    t.ville,
    COUNT(c.id)                             AS total_creneaux,
    SUM(c.statut IN ('reserve','complet'))  AS creneaux_occupes,
    ROUND(100 * SUM(c.statut IN ('reserve','complet')) / COUNT(c.id), 1) AS taux_occupation_pct
FROM Terrain t
LEFT JOIN Creneau c ON c.terrain_id = t.id
GROUP BY t.id;

-- ==========================================================
-- FIN DU SCRIPT
-- SportConnect Madagascar 2035 — NIE SE20240122
-- ==========================================================
