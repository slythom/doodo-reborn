# Specs fonctionnelles — Doodo (Perudo en ligne)

**Application mobile iOS/Android** permettant de jouer au **Perudo** (aussi appelé Dudo, Liar's Dice ou « menteur péruvien ») en temps réel, contre d'autres joueurs humains ou des bots.

**V1 :** jeu complet jouable en invité — salles privées/publiques, matchmaking, bots (niveau normal), spectateurs, chat prédéfini, SFX. Pas de comptes ni de stats cumulées.
**V1.5 :** comptes joueurs, stats persistantes, conversion invité → compte, pouvoirs admin/triche.
**V2+ :** ELO, historique détaillé, amis, badges.

*Les choix de stack technique et les specs techniques sont traités dans un document séparé, ultérieur.*

---

## 1. Règles du jeu

### 1.1 Règles de base (toujours actives)

- 2 à 6 joueurs par partie, chacun commence avec N dés (5 par défaut, configurable 3-5).
- Les sièges autour de la table et le premier enchérisseur de la manche 1 sont **tirés au sort** au lancement ; les tours suivent le **sens horaire**.
- Chaque joueur lance ses dés sous son gobelet ; seul lui voit son tirage.
- Le joueur débutant la manche fait une **enchère** : « Il y a au moins **X** dés de valeur **V** sur la table ».
- À son tour, un joueur peut :
  - **Surenchérir** : produire une enchère légale (cf. §1.2).
  - **Dudo !** (« je doute ») : tous les dés sont révélés. Si l'enchère était **strictement surestimée** (moins de X dés de valeur V en comptant les Pacos si joker), l'enchérisseur perd un dé ; sinon c'est celui qui a dit Dudo qui perd un dé.
  - **Calza !** (« exact ! ») : réservé au **joueur dont c'est le tour**. Si l'enchère est **exactement juste** (exactement X dés de valeur V), le calzeur **regagne un dé** (sans dépasser son nombre de dés de départ) ; sinon il en perd un.
- Un joueur à 0 dé est éliminé. La partie se termine quand il ne reste qu'un joueur.

**Qui entame la manche suivante :**
- Dudo → le joueur qui a perdu le dé entame ; s'il a été éliminé, c'est le joueur suivant dans le sens horaire.
- Calza réussi (personne ne perd de dé) → le calzeur entame.
- Calza raté → le calzeur (qui a perdu un dé) entame ; éliminé → suivant horaire.

### 1.2 Enchères valides

Une enchère `(X', V')` est légale après `(X, V)` si et seulement si :

- `X' > X` (valeur libre), **ou**
- `X' = X` et `V' > V`,

avec les transitions Pacos (valeur 1) :

- Passer aux Pacos : nouvelle quantité = `ceil(X / 2)`.
- Quitter les Pacos pour une valeur normale : nouvelle quantité minimum = `2X + 1`.

La **première enchère d'une manche ne peut pas porter sur les Pacos** — sauf en manche Palifico, où le premier enchérisseur fixe librement la valeur (§1.3).

Il n'existe **pas de variante officielle** de la règle de surenchère ; les variantes éventuelles relèvent des règles personnalisées (§1.5).

### 1.3 Options configurables par table

Le créateur de la partie choisit avant le lancement. Les options sont **figées au lancement** (non modifiables en cours de partie).

| Option | Choix | Défaut |
|---|---|---|
| Nombre de dés de départ | 3 à 5 | 5 |
| Paco joker | oui / non | oui |
| Calza autorisé | oui / non | oui |
| Manche Palifico | oui / non | oui |
| Timer par action | 15 s / 30 s / 60 s / off | 30 s |
| Nombre max de joueurs | 2 à 6 | 6 |
| Remplacement par bot après déconnexion | oui / non | oui |
| Spectateurs & chat spectateurs | oui / non | oui |
| Scène / décor 3D | `salon` (défaut) + scènes ajoutées au fil des versions — choisie en salle d'attente, figée au lancement | `salon` |
| Règles personnalisées | toggles individuels (cf. §1.5) | toutes off |
| Mode dieu | oui / non — **salles privées uniquement** | non — rend la partie non classée |

**Manche Palifico** (si activée) : le passage d'un joueur à **exactement 1 dé** « arme » une manche Palifico, jouée à la manche suivante — même si le joueur a regagné des dés entre-temps. Pendant cette manche : les Pacos ne sont **pas** jokers (mais restent enchérissables comme valeur), et la valeur des dés ne peut pas changer (le **premier enchérisseur fixe la valeur**, seule la quantité augmente ensuite). Ne peut survenir qu'**une fois par joueur et par partie** ; si plusieurs joueurs déclenchent en même temps, une seule manche Palifico partagée a lieu ; si le joueur déclencheur est éliminé avant sa manche Palifico, elle n'a pas lieu.

### 1.4 Cas limites à gérer

- Calza quand le calzeur est déjà à son nombre max de dés : le regagner est impossible → le Calza réussi ne fait que valider l'enchère (aucun dé perdu par personne).
- Dudo / Calza hors de son tour : impossible (boutons désactivés côté client, rejet côté serveur).
- **Abandon ou expulsion en cours de partie** : le joueur est éliminé, ses dés retirés immédiatement du comptage ; **l'enchère debout reste valable** pour le décompte et le jeu continue au joueur suivant dans le sens horaire.
- **Expiration du timer** : action automatique = enchère minimale légale, calculée ainsi : si l'enchère debout est sur les Pacos `(X, Paco)` → `(2X+1, valeur 2)` ; sinon → `(X+1, V)` (même valeur, quantité +1). Jamais de Dudo/Calza automatique.
- **Tous les joueurs humains déconnectés** : la partie se met en pause puis est **annulée après ~2 min** (aucune statistique produite).
- Égalité sur enchère exacte → Dudo perdant pour le douteur (règle standard).
- Fin de partie : classement des joueurs par ordre d'élimination (le dernier éliminé finit 2ᵉ, etc.).

### 1.5 Règles personnalisées (house rules)

- Le moteur de règles est **modulaire** : des variantes maison — définies pendant le dev — viennent s'ajouter aux options officielles et sont activables individuellement par le créateur de la table. Les variantes de la règle de surenchère, notamment, vivent ici et non dans les options officielles.
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

### 2.1 Invité (sans compte) — v1

- Un **pseudo** suffit pour jouer (validation : 2-20 caractères, alphanum + quelques symboles).
- **Unicité des pseudos** : un pseudo invité est refusé (avec suggestion alternative) s'il est déjà pris par un compte enregistré ou par un invité actuellement connecté.
- Un jeton invité est stocké en local pour permettre la reconnexion.
- En v1, un invité n'a **aucun cumul de stats** : seul l'écran de fin de partie (§4.4) affiche les statistiques de la partie jouée.

### 2.2 Compte (optionnel) — v1.5

- Inscription : pseudo unique + email + mot de passe ; OAuth Google/Discord envisageable (v2).
- Avec un compte : pseudo réservé, statistiques persistées, avatar.
- **Conversion invité → compte** : un invité peut convertir son pseudo en compte sans perdre ses stats, car celles-ci sont stockées **serveur, indexées sur le jeton** (invité ou compte). Si son pseudo est déjà réservé par un autre compte, le changement de pseudo est obligatoire, avec avertissement explicite.

### 2.3 Stats de base — v1.5

- Parties jouées / gagnées, taux de victoire.
- Affichées sur le profil du joueur (page `/profil`).
- Les parties **non classées** (mode dieu, ou règle perso `ranked_safe: false`) sont **exclues purement** des stats — pas de compartiment séparé.

**V2+ :** ELO calculé selon le placement final et le niveau des adversaires, historique détaillé des parties, liste d'amis + invitations directes, badges/succès.

---

## 3. Rejoindre une partie

Trois points d'entrée, tous disponibles en v1 :

### 3.1 Salle privée (code)

- Un joueur **crée** une table : il choisit les options (§1.3), le système génère un **code à 6 caractères** tirés de `A-Z2-9` privé de `I/O/0/1` (anti-ambiguïté), insensible à la casse — ex. `X4KPD2` — et un lien partageable `doodo.example/join/XXXXXX`.
- La table porte automatiquement le nom **« Table de \<pseudo du créateur\> »**.
- Les amis rejoignent via le code ou le lien.
- Le créateur lance la partie quand il veut, dès **≥ 2 joueurs** — les bots comptant dans le total (minimum donc : 1 humain + 1 bot). La partie démarre avec les joueurs présents ; les places vides ne sont pas recomblées automatiquement (le créateur ajoute les bots manuellement).
- **Salle pleine** (nombre max atteint) : le visiteur reçoit « salle pleine » + bouton « Regarder en spectateur » si la partie est en cours ; sinon simple erreur.
- **Joueurs expulsés** : le code/lien ne fonctionne plus pour eux pour la durée de la table.

### 3.2 Lobby public

- Page à **deux onglets** :
  - « En attente » : tables publiques joignables en joueur (nom « Table de X », nb de joueurs, options principales, bouton « Rejoindre »).
  - « En cours » : parties publiques en jeu, joignables en **spectateur**.
- Filtrage (nb de joueurs, options de règles) — nice to have v1.
- Le créateur d'une salle peut la basculer publique/privée tant qu'elle n'a pas démarré.

### 3.3 Matchmaking automatique

- Bouton « Partie rapide » : file d'attente qui vise une table standard de **6 joueurs**, options standard (5 dés, paco joker, calza, palifico, timer 30 s, remplacement bot et spectateurs activés).
- **6 humains réunis → lancement immédiat.**
- **60 s sans atteindre 6 joueurs → les sièges vides sont remplis automatiquement par des bots** et la partie démarre (même à 1 humain + 5 bots). Pas de proposition ni de vote : le remplissage est automatique.

---

## 4. Déroulé d'une partie

### 4.1 Salle d'attente

- Liste des joueurs présents et options de la table (modifiables par le créateur uniquement, jusqu'au lancement).
- **Chat de salle en texte libre** (salles privées : entre amis, pas de modération en v1).
- Le créateur peut : ajouter/retirer des bots, expulser un joueur (ban pour la durée de la table), basculer publique/privée, **choisir la scène/décor 3D** (§1.3), lancer la partie.
- **Départ du créateur en salle** : l'hosting est transféré au joueur humain le plus ancien ; s'il ne reste que des bots ou plus personne, la salle se ferme.

### 4.2 En jeu

**Ce que chaque joueur voit :**
- Ses propres dés (valeurs réelles) ; pour les autres : uniquement leur **nombre** de dés restants.
- L'enchère courante, l'historique des enchères de la manche.
- Indicateur du joueur dont c'est le tour (avec compte à rebours si timer).
- Boutons d'action contextualisés : Surenchérir (sélecteur quantité/valeur), Dudo, Calza.
- Animation de lancement de dés et de révélation (mobile-first, §7).
- **Pas d'avatars en v1** : les joueurs sont identifiés par leur pseudo (les avatars arrivent avec les comptes en v1.5).

**Révélation :** après un Dudo/Calza, tous les dés sont montrés brièvement, le comptage des dés correspondants (Pacos inclus si joker) est affiché, le perdant de la manche est animé (perte d'un dé). Le **timer est suspendu pendant toute la phase de résolution** (révélation → perte de dé → début de la manche suivante) et repart à zéro à chaque tour.

### 4.3 Fonctionnalités transverses

- **Chat** : texte libre en salle d'attente ; en partie et en matchmaking/public, messages **prédéfinis** (ex. « Bonjour », « Merci »…) + quelques emotes prédéfinies. **Canal unique** : le chat spectateurs est visible des joueurs en cours de partie. Les listes de messages, emotes et SFX sont arrêtées en dev (non spécifiées ici).
- **Mode spectateur** : rejoignable depuis l'onglet « En cours » du lobby (tables publiques) ou via le lien/code (tables privées aussi). Les spectateurs voient le nombre de dés de chaque joueur, pas les valeurs. Activable/désactivable par option de table (§1.3).
- **Reconnexion** : un joueur déconnecté a **60 s** pour revenir (même pseudo/jeton). Pendant ce temps : ses dés restent en jeu, le timer de son tour continue et son expiration déclenche l'enchère automatique (§1.4). Passé le délai : le joueur est éliminé, **ou** remplacé par un bot si l'option de table l'autorise (défaut oui). Un joueur remplacé par un bot **reprend le contrôle** s'il revient avant la fin de la partie ; un joueur éliminé revient en spectateur.
- **Timer de tour** : si activé, à expiration → enchère minimale automatique (formule §1.4).
- **Abandon volontaire** : bouton « Quitter » avec confirmation ; équivaut à une élimination (§1.4). Le départ du créateur en cours de partie est un abandon ordinaire — la table continue sans host.
- **Bruitages** : SFX sur les moments clés — lancer de dés, gobelet soulevé/posé, annonce « Dudo ! », annonce « Calza ! », révélation des dés, dé perdu, élimination, victoire, notification de son tour. Réglage volume/muet dans les paramètres ; sons **embarqués** dans l'app (jouables hors-ligne, pas de latence réseau). Couplage avec retour haptique léger sur les actions importantes (nice to have).

### 4.4 Fin de partie

- Écran de fin : classement, statistiques marquantes de la partie (nb de Calza réussis, dudos réussis). En v1, c'est le **seul** affichage de stats pour un invité.
- Boutons : « Revanche » (retour en salle d'attente avec les mêmes options et les joueurs encore présents ; les places libres peuvent être recomblées par des bots ou de nouveaux joueurs), « Retour au lobby », « Partager ».
- Mise à jour des stats persistées pour les comptes (v1.5).

### 4.5 God mode

Deux déclinaisons distinctes :

**Pouvoirs admin** — **v1.5 uniquement**, attachés au compte admin, utilisables dans n'importe quelle partie, y compris en spectateur :
- Voir le contenu de tous les gobelets en temps réel.
- Fixer le prochain tirage de dés de n'importe quel joueur (y compris soi-même).
- Forcer la résolution d'une manche, expulser un joueur, terminer la partie.
- Panneau d'admin discret en surimpression ; **invisible pour les autres joueurs** ; chaque action admin est journalisée.

**Mode dieu (option de table)** — activable par le créateur d'une **salle privée** uniquement, aucune indication de son activation ou non en jeu, sauf pour le créateur lui-même :
- Le créateur de la partie voit les dés de tous les adversaires en temps réel.
- Le créateur de la partie **choisit** ses dés au lieu de les lancer, à chaque manche.
- Parties en mode dieu automatiquement **non classées** et exclues des stats ; indisponible via le matchmaking et le lobby public.
- Pensé pour le fun entre amis et pour tester les règles personnalisées.

---

## 5. Bots

- Complètent les tables (choix du créateur : nombre de bots) et le matchmaking (remplissage automatique §3.3) et remplacent les joueurs déconnectés (option §1.3).
- **V1 : un seul niveau « normal »**, sans sélecteur de difficulté. L'interface interne prévoit le paramètre difficulté pour le brancher plus tard. Les niveaux envisagés :
  - **Facile** : enchères quasi-aléatoires plausibles, Dudo sur probabilité grossière.
  - **Normal** : raisonnement probabiliste (probabilité que l'enchère soit vraie compte tenu de ses propres dés), bluff léger, Calza quand l'enchère est très probablement exacte.
  - **Difficile** : prend en compte l'historique des enchères des adversaires dans la manche.
- Les bots jouent avec une latence simulée (1-3 s) pour rester naturels.

---

## 6. Parcours utilisateurs

1. **Premier visiteur** : landing → pseudo → choix « Partie rapide » / « Créer une table » / « Voir le lobby » → partie.
2. **Joueur avec lien** : ouvre le lien → pseudo (ou login) → rejoint directement la salle (ou arrive **en spectateur** si la partie est déjà en cours).
3. **Joueur compte (v1.5)** : login → accueil avec son profil/stats → rejoint ou crée une table → stats mises à jour en fin de partie.
4. **Spectateur** : lobby → onglet « En cours » → observe une partie.

---

## 7. UX & interface

- **Application native iOS/Android** (cible principale) : distribuée via Play Store / App Store, retour haptique sur les actions. Une version web navigateur pourra suivre (codebase partagée) mais n'est pas l'objectif de la v1.
- **Mobile-first** : jouable à une main ; actions principales en bas d'écran, pouce-friendly.
- **Rendu 3D, vue première personne** : le joueur est assis à la table et voit les autres joueurs (identifiés par leur pseudo) autour d'elle, leurs gobelets et le nombre de dés restants ; ses propres dés sont visibles sous son gobelet. Animations : lancer de dés, gobelet soulevé, révélation. Fluide sur smartphone milieu de gamme. HUD 2D (boutons d'action, chat) superposé à la scène.
- Orientation : **portrait verrouillé** en v1 (paysage réévalué ultérieurement) ; la caméra et le HUD sont pensés pour le portrait (table et adversaires devant/en haut, propres dés et actions en bas).
- Accessibilité de base : contrastes suffisants, tailles de tap-target ≥ 44 px, indication du tour autre que par la couleur seule.
- Langue : **français uniquement** en v1 (structure i18n prête pour l'anglais en v2).

---

## 8. Hors périmètre (v1)

- **Comptes joueurs, stats persistantes, conversion invité → compte, avatars, pouvoirs admin** → v1.5.
- Monétisation, achats intégrés, cosmétiques payants.
- Tournois, brackets, parties multijoueurs > 6.
- Chat vocal, webcam, chat texte libre en partie (prédéfini uniquement).
- Version web navigateur du client (codebase partagée, chantier ultérieur).
- Notifications push.
- Mode paysage / tablette.
- Signalement de joueurs, modération, pénalité pour abandons répétés (un taux d'abandon pourra entrer dans les stats en v2).
- Anti-triche avancé (multi-comptes, collusion) — hors détection serveur basique.
- Classement ELO, amis, historique détaillé → v2 (spec déjà prévue, cf. §2.3).

---

## 9. Indicateurs de succès (v1)

- Une partie complète 4 joueurs jouable de bout en bout sans bug bloquant.
- Reconnexion fonctionnelle dans les cas courants (délai de grâce de 60 s respecté).
- Bots « normaux » jouant une partie crédible.
- Utilisable confortablement en 4G sur smartphone milieu de gamme (60 fps sur la scène 3D).
