# Specs fonctionnelles — Doodo (Perudo en ligne)

**Application mobile iOS/Android** permettant de jouer au **Perudo** (aussi appelé Dudo, Liar's Dice ou « menteur péruvien ») en temps réel, contre d'autres joueurs humains ou des bots.

**V1 :** jeu complet + comptes + stats de base.
**V1.5 :** comptes + stats de base.
**V2+ :** ELO, historique détaillé, amis.

---

## 1. Règles du jeu

### 1.1 Règles de base (toujours actives)

- 2 à 6 joueurs par partie, chacun commence avec N dés (5 par défaut, configurable).
- Chaque joueur lance ses dés sous son gobelet ; seul lui voit son tirage.
- Le joueur débutant la manche (perdant de la manche précédente, ou joueur aléatoire en début de partie) fait une **enchère** : « Il y a au moins **X** dés de valeur **V** sur la table ».
- À son tour, un joueur peut :
  - **Surenchérir** : augmenter la quantité X, ou augmenter la valeur V, ou passer aux Pacos (cf. règles de calcul d'enchère).
  - **Dudo !** (« je doute ») : tous les dés sont révélés. Si l'enchère était **strictement surestimée** (moins de X dés de valeur V en comptant les Pacos), l'enchérisseur perd un dé ; sinon c'est celui qui a dit Dudo qui perd un dé.
  - **Calza !** (« exact ! ») : si l'enchère est **exactement juste** (exactement X dés de valeur V), le joueur qui a dit Calza **regagne un dé** (sans dépasser son maximum) ; sinon il en perd un.
- Un joueur à 0 dé est éliminé. La partie se termine quand il ne reste qu'un joueur.

### 1.2 Enchères valides

- Passer aux Pacos (valeur 1) : nouvelle quantité = `ceil(X / 2)`.
- Quitter les Pacos pour une valeur normale : nouvelle quantité = `2X + 1` minimum.
- Augmenter la quantité à valeur égale, ou la valeur à quantité égale ou supérieure, selon la variante choisie (voir options).

### 1.3 Options configurables par table

Le créateur de la partie choisit avant le lancement :

| Option | Choix | Défaut |
|---|---|---|
| Nombre de dés de départ | 3 à 5 | 5 |
| Paco joker | oui / non | oui |
| Calza autorisé | oui / non | oui |
| Manche Palifico | oui / non | oui |
| Timer par action | 15 s / 30 s / 60 s / off | 30 s |
| Nombre max de joueurs | 2 à 6 | 6 |
| Règles personnalisées | toggles individuels (cf. §1.5) | toutes off |
| Mode dieu | oui / non | non — rend la partie non classée |
| Partie classée (ELO) | oui / non | non — v2 |

**Manche Palifico** (si activée) : la manche qui suit le passage d'un joueur à 1 dé est jouée en mode spécial — les Pacos ne sont **pas** jokers et la valeur des dés ne peut pas changer pendant la manche (seule la quantité augmente). Ne peut survenir qu'une fois par joueur et par partie.

### 1.4 Cas limites à gérer

- Calza quand un joueur est déjà à son nombre max de dés : le regagner est impossible → le Calza réussi ne fait que valider l'enchère (aucun dé perdu par personne).
- Dudo / Calza hors de son tour : impossible (boutons désactivés côté client, rejet côté serveur).
- Abandon en cours de partie : le joueur est éliminé, ses dés retirés du comptage, la manche reprend.
- Égalité sur enchère exacte → Dudo perdant pour le douter (règle standard).
- Fin de partie : classement des joueurs par ordre d'élimination (le dernier éliminé finit 2ᵉ, etc.).

### 1.5 Règles personnalisées (house rules)

- Le moteur de règles est **modulaire** : des variantes maison — définies pendant le dev — viennent s'ajouter aux options officielles et sont activables individuellement par le créateur de la table.
- Chaque règle perso déclare : un **nom**, une **description courte** (affichée dans les options de table), et ses **incompatibilités** (avec d'autres règles perso ou des options officielles — ex. une règle qui neutralise les Pacos est incompatible avec « Paco joker »).
- Une partie avec règles personnalisées reste éligible aux stats sauf si la règle casse l'équité (déclaré par règle : `ranked_safe: false` → partie non classée).
- La liste exacte sera arrêtée en cours de dev. Candidats d'exemple (à confirmer) :
  - « Dé public » — un dé de chaque joueur est révélé à tous en début de manche
  - « Double Paco » — les Pacos comptent double dans le décompte
  - « Menteur puni » — un joueur surpris en bluff éhonté (enchère très surestimée) perd 2 dés
  - « Survivant » — un joueur à 1 dé éliminé sur un Calza réussi adverse repart avec 1 dé
- Le client affiche les règles actives en partie (icônes + infobulles / panneau « règles de la table »).

---

## 2. Comptes joueurs

### 2.1 Invité (sans compte)

- Un **pseudo** suffit pour jouer (validation : 2-20 caractères, alphanum + quelques symboles).
- Un jeton invité est stocké en local pour permettre la reconnexion.
- Un invité peut **convertir** son pseudo en compte sans perdre ses stats de session (v1.5, optionnel).

### 2.2 Compte (optionnel)

- Inscription : pseudo unique + email + mot de passe (v1) ; OAuth Google/Discord envisageable (v2).
- Avec un compte : pseudo réservé, statistiques de base persistées (parties jouées, victoires, winrate), avatar simple.

### 2.3 Stats de base

- Parties jouées / gagnées, taux de victoire.
- Affichées sur le profil du joueur (page `/profil`).

**V2+ :** ELO calculé selon le placement final et le niveau des adversaires, historique détaillé des parties, liste d'amis + invitations directes, badges/succès.

---

## 3. Rejoindre une partie

Trois points d'entrée, tous disponibles en v1 :

### 3.1 Salle privée (code)

- Un joueur **crée** une table : il choisit les options (§1.3), le système génère un **code à 6 caractères** (ex. `DUDO-42`) et un lien partageable `doodo.example/join/XXXXXX`.
- Les amis rejoignent via le code ou le lien.
- Le créateur lance la partie quand ≥ 2 joueurs sont présents (complétion possible par des bots).

### 3.2 Lobby public

- Page listant les **tables publiques** en attente : nom de la table, nb de joueurs, options principales, bouton « Rejoindre ».
- Filtrable (nb de joueurs, options de règles) — nice to have v1.
- Le créateur d'une salle peut la basculer publique/privée tant qu'elle n'a pas démarré.

### 3.3 Matchmaking automatique

- Bouton « Partie rapide » : file d'attente qui regroupe les joueurs jusqu'à remplir une table (3-6 joueurs, options standard).
- Si la file n'atteint pas le minimum en ~60 s, proposition de compléter avec des bots (acceptation par les joueurs en file).

---

## 4. Déroulé d'une partie

### 4.1 Salle d'attente

- Liste des joueurs présents, indicateur « prêt », options de la table (modifiables par le créateur uniquement).
- Chat de salle.
- Le créateur peut : ajouter/retirer des bots, expulser un joueur, lancer la partie.

### 4.2 En jeu

**Ce que chaque joueur voit :**
- Ses propres dés (valeurs réelles) ; pour les autres : uniquement leur **nombre** de dés restants.
- L'enchère courante, l'historique des enchères de la manche.
- Indicateur du joueur dont c'est le tour (avec compte à rebours si timer).
- Boutons d'action contextualisés : Surenchérir (sélecteur quantité/valeur), Dudo, Calza.
- Animation de lancement de dés et de révélation (mobile-first, §7).

**Révélation :** après un Dudo/Calza, tous les dés sont montrés brièvement, le comptage des dés correspondants (Pacos inclus si joker) est affiché, le perdant de la manche est animé (perte d'un dé).

### 4.3 Fonctionnalités transverses

- **Chat en partie** : messages texte prédéfinis (exemples: "Bonjour", "Merci"...) + quelques emotes prédéfinies (réactions rapides adaptées au mobile).
- **Mode spectateur** : tout le monde peut rejoindre une partie en cours en lecture seule (visible depuis le lobby). Les spectateurs voient le nombre de dés de chaque joueur, pas les valeurs ; ils peuvent chatter (canal séparé si activé).
- **Reconnexion** : un joueur déconnecté a **60 s** pour revenir (même pseudo/jeton). Pendant ce temps : ses dés restent en jeu, le timer de son tour continue, et s'il expire → enchère minimale automatique. Passé le délai : le joueur est éliminé (ou remplacé par un bot si la table l'autorise — option créateur).
- **Timer de tour** : si activé, à expiration → action automatique : surenchère minimale légale (jamais Dudo/Calza auto).
- **Abandon volontaire** : bouton « Quitter » avec confirmation ; équivaut à une élimination.
- **Bruitages** : SFX sur les moments clés — lancer de dés, gobelet soulevé/posé, annonce « Dudo ! », annonce « Calza ! », révélation des dés, dé perdu, élimination, victoire, notification de son tour. Réglage volume/muet dans les paramètres ; sons **embarqués** dans l'app (jouables hors-ligne, pas de latence réseau). Couplage avec retour haptique léger sur les actions importantes (nice to have).

### 4.4 Fin de partie

- Écran de fin : classement, statistiques marquantes de la partie (nb de Calza réussis, dudos réussis).
- Boutons : « Revanche » (mêmes joueurs/options), « Retour au lobby », « Partager ».
- Mise à jour des stats pour les comptes.

### 4.5 God mode

Deux déclinaisons distinctes :

**Pouvoirs admin** — attachés au compte admin (toi), utilisables dans n'importe quelle partie, y compris en spectateur :
- Voir le contenu de tous les gobelets en temps réel.
- Fixer le prochain tirage de dés de n'importe quel joueur (y compris soi-même).
- Forcer la résolution d'une manche, expulser un joueur, terminer la partie.
- Panneau d'admin discret en surimpression ; **invisible pour les autres joueurs** ; chaque action admin est journalisée.

**Mode dieu (option de table)** — activable par le créateur d'une partie dans les options, aucune indication de son activation ou non en jeu, sauf pour le créateur lui-même :
- Le créateur de la partie voit les dés de tous les adversaires en temps réel.
- Le créateur de la partie **choisit** ses dés au lieu de les lancer, à chaque manche.
- Parties en mode dieu automatiquement **non classées** et exclues des stats ; indisponible via le matchmaking et le lobby public.
- Pensé pour le fun entre amis et pour tester les règles personnalisées.

---

## 5. Bots

- Complètent les tables (choix du créateur : nombre de bots, difficulté).
- Trois niveaux envisagés (v1 : un seul niveau « normal » suffit) :
  - **Facile** : enchères quasi-aléatoires plausibles, Dudo sur probabilité grossière.
  - **Normal** : raisonnement probabiliste (probabilité que l'enchère soit vraie compte tenu de ses propres dés), bluff léger, Calza quand l'enchère est très probablement exacte.
  - **Difficile** : prend en compte l'historique des enchères des adversaires dans la manche.
- Les bots jouent avec une latence simulée (1-3 s) pour rester naturels.

---

## 6. Parcours utilisateurs

1. **Premier visiteur** : landing → pseudo → choix « Partie rapide » / « Créer une table » / « Voir le lobby » → partie.
2. **Joueur avec lien** : ouvre le lien → pseudo (ou login) → rejoint directement la salle.
3. **Joueur compte** : login → accueil avec son profil/stats → rejoint ou crée une table → stats mises à jour en fin de partie.
4. **Spectateur** : lobby → onglet « En cours » → observe une partie.

---

## 7. UX & interface

- **Application native iOS/Android** (cible principale) : distribuée via Play Store / App Store, notifications push possibles, retour haptique sur les actions. Une version web navigateur pourra suivre (codebase partagée) mais n'est pas l'objectif de la v1.
- **Mobile-first** : jouable à une main ; actions principales en bas d'écran, pouce-friendly.
- **Rendu 3D, vue première personne** : le joueur est assis à la table et voit les autres joueurs (avatars) autour d'elle, leurs gobelets et le nombre de dés restants ; ses propres dés sont visibles sous son gobelet. Animations : lancer de dés, gobelet soulevé, révélation. Fluide sur smartphone milieu de gamme. HUD 2D (boutons d'action, chat) superposé à la scène.
- Orientation : portrait en priorité ; la caméra et le HUD s'adaptent (table et adversaires devant/en haut, propres dés et actions en bas).
- Accessibilité de base : contrastes suffisants, tailles de tap-target ≥ 44 px, indication du tour autre que par la couleur seule.
- Langue : **français uniquement** en v1 (structure i18n prête pour l'anglais en v2).

---

## 8. Hors périmètre (v1)

- Monétisation, achats intégrés, cosmétiques payants.
- Tournois, brackets, parties multijoueurs > 6.
- Chat vocal, webcam.
- Version web navigateur du client (codebase partagée, chantier ultérieur).
- Anti-triche avancé (multi-comptes, collusion) — hors détection serveur basique.
- Classement ELO, amis, historique détaillé → v2 (spec déjà prévue, cf. §2.3).

---

## 9. Indicateurs de succès (v1)

- Une partie complète 4 joueurs jouable de bout en bout sans bug bloquant.
- Reconnexion fonctionnelle dans les cas courants (perte réseau < 90 s).
- Bots « normaux » jouant une partie crédible.
- Utilisable confortablement en 4G sur smartphone milieu de gamme (60 fps sur la scène 3D).
