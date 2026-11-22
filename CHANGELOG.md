# Changelog

Toutes les modifications notables de Doodo, par version.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [v0.10.15] — 2026-11-22

### Corrigé
- Lag au premier impact d'objet lancé : les shaders des effets
  (particules, splat, gouttes, volutes) sont préchauffés une frame sous
  la table à l'ouverture de la scène au lieu d'être compilés au moment
  de l'impact.

## [v0.10.14] — 2026-11-22

### Ajouté
- **Backend production** : le serveur tourne sur un VPS dédié
  (`doodo.sylvainthomas.fr`) derrière Caddy — TLS automatique,
  service systemd durci. Fini les tunnels éphémères.
- Le client pointe désormais sur ce serveur par défaut : plus rien
  à saisir dans le champ « Serveur » (qui reste un override ; taper
  `localhost:8080` garde `ws://` pour le dev local).

### Corrigé
- Chargement du sprite perroquet en lazy-load : la CI (clone frais)
  repasse au vert — sans changement visible en jeu.

## [v0.10.13] — 2026-11-21

### Modifié
- Audit godot-master : casts `as` + test null dans kaykit, typage du
  dispatch réseau, nommage `_scene_registry` — aucun changement visible.

## [v0.10.12] — 2026-11-21

### Modifié
- Refactoring interne : les scrims des modales passent par un helper
  commun (`UI.open_modal`) et les sons de verdict partagent
  `_reveal_sfx` — aucun changement visible.

## [v0.10.11] — 2026-11-21

### Ajouté
- **#47** — son « win-dice » quand on regagne un dé (calza réussi),
  réservé au joueur concerné et synchronisé sur la fin du compteur vert.
- **#50** — la face 1 (paco/joker) affiche un perroquet pixel-art en
  couleurs à la place du pip (main, sélecteur de faces, enchères,
  révélation, mode dieu).

## [v0.10.10] — 2026-11-21

### Ajouté
- **#48** — tick haptique (15 ms) à chaque pas du stepper de quantité
  (muet aux bornes min/max).
- **#49** — lien « Comment jouer ? » sur l'accueil : modale avec les
  règles de base du Perudo, indépendantes des options de table.

## [v0.10.9] — 2026-11-21

### Ajouté
- **#25** — vibration courte au début de son tour (Android, permission
  `VIBRATE` activée dans l'export).
- **#27** — badge grisé + barre « hors-ligne » sur le compteur de dés
  d'un joueur déconnecté, pendant la fenêtre de reconnexion.
- **#28** — confirmation avant de quitter une partie en cours
  (Rester / Quitter, tap sur le fond = annuler).
- **#35** — bouton « ? » en jeu : rappel des règles de base et des
  options/règles perso actives sur la table.
- **#44** — option « Réduire les animations » : coupe pops, punchs,
  clignotements, shake et animations d'accueil (persistée).

## [v0.10.8] — 2026-11-21

### Ajouté
- **#26** — reconnexion immédiate au retour au premier plan : la socket
  morte pendant la suspension Android est repartie de zéro, ou sondée
  par un `hello` (idempotent + resync serveur).
- **#29** — keep-alive WebSocket : ping serveur toutes les 25 s contre
  les NAT 4G qui coupent les connexions inactives (logs détaillés via
  `DOODO_LOG_LEVEL=debug`).
- **#32** — bots humanisés : délai de réaction variable (0,8–3 s) et
  hésitation supplémentaire avant un dudo/calza.
- **#33** — handshake de version : le serveur envoie sa version de
  protocole dans `welcome` ; le client avertit si elle diffère
  (« mets à jour l'APK »).
- **#34** — options de table persistées : les derniers réglages de
  l'hôte (dés, timer, paco, calza, mode dieu, décor…) sont réappliqués
  à la salle suivante.

## [v0.10.7] — 2026-11-21

### Ajouté
- **#45** — révélation : la mention « X perd/regagne un dé » est agrandie
  (30 px), colorée (rouge/vert) et clignote façon néon jusqu'à la
  fermeture.

### Corrigé
- **#46** — révélation : `de-perdu.mp3` joue désormais au moment où le
  compteur vert se termine, au lieu d'arriver dès l'événement reçu
  (toujours réservé au joueur qui perd le dé).

## [v0.10.6] — 2026-11-20

### Ajouté
- **#36** — effet CRT (scanlines + vignette) partout, menu et partie,
  désactivable dans les options (activé par défaut).
- **#38** — attract mode sur l'accueil : dés flottants en fond et
  flicker néon sur le titre.
- **#39** — bulles de chat au-dessus du Mii de l'émetteur (~2,5 s),
  en plus du toast existant.
- **#40** — safe-area Android : le HUD évite l'encoche et la barre
  gestuelle.
- **#41** — jauge de timer pulsante en rouge sous les 5 s restantes.
- **#42** — micro-shake d'écran à la révélation d'un dudo/calza et
  quand tu perds un dé.

### Corrigé
- **#41** — la jauge repartait pleine à chaque interaction locale
  (stepper, faces) : la deadline était recalée d'après le
  `turn_remaining_ms` périmé du dernier snapshot. Elle n'est recalée
  qu'à l'arrivée d'un nouveau snapshot.

## [v0.10.5] — 2026-11-20

### Modifié
- **#15** — enchère : le stepper de quantité propose par défaut la
  quantité de l'enchère en cours (« 8 » après un 8×5) au lieu de
  repartir à 1. La face choisie reste inchangée ; nouvelle manche
  sans enchère → retour à 1.

### Corrigé
- **#24** — jauge de tour : largeur fixe (180 px, comme en début de
  partie). Elle se rétrécissait après la première manche : sa borne
  droite était calculée d'après la largeur de la main, mesurée pendant
  le rafraîchissement des dés.

## [v0.10.4] — 2026-11-20

### Ajouté
- **#22** — jauge de tour : barre horizontale au-dessus du panneau
  d'action, à gauche de tes dés, qui se vide de droite à gauche pendant
  le temps imparti à ton action (enchère ou choix de victime Calzone).
  Remplissage bleu clair, visible seulement pendant ton tour ; le
  serveur envoie la durée résiduelle (`turn_remaining_ms`), recalée à
  chaque snapshot — insensible au décalage d'horloge.

## [v0.10.3] — 2026-11-20

### Corrigé
- **#21** — à 2 adversaires, ils étaient placés aux extrémités de
  l'arc (215°/325°) et sortaient du champ. L'arc est maintenant
  proportionnel (~30° par siège, centré) ; il n'atteint sa pleine
  largeur qu'à partir de 5 adversaires.

## [v0.10.2] — 2026-11-20

### Modifié
- **Mode dieu (#20)** : les dés révélés des adversaires ne sont plus
  affichés en permanence au-dessus des Miis. Un tap sur le badge d'un
  siège ouvre une modale nom + dés ; un tap n'importe où la ferme.
  Un liseré ambre sur le compteur indique les sièges « révélables ».
- **Thème (#18)** : le thème sombre est activé par défaut — et réellement
  appliqué dès le premier lancement.
- **Stepper (#19)** : boutons quantité encore plus grands (76 px) et
  retour tactile turquoise.

### Corrigé
- La main du joueur passait sous le panneau d'action (invisible) :
  elle se recale maintenant au-dessus de sa hauteur réelle.
- **APK Android signé** : l'export release sans keystore produisait un
  package refusé par Android (« package non valide »).

## [v0.10.1] — 2026-11-19

Première passe de retours beta sur mobile.

### Corrigé
- **#13** — taps doublés sur mobile : chaque toucher générait aussi un
  événement souris émulé. Les switches (dont mode dieu), les dés du mode
  dieu, Calzone et les émotes basculaient/de déclenchaient deux fois.
- **#14** — contrôles d'enchère trop petits : stepper et faces de dés
  agrandis en vraies cibles tactiles.
- **#11** — écran d'accueil trop petit : cartes en largeur adaptative,
  champs et boutons densifiés.
- **#16** — « INSERT DÉ » plus visible (ambre, plus grand, accentué).
- **#12** — curseur triangle jaune flottant : ne suit plus que les vrais
  widgets et se masque quand le focus disparaît.
- **#17** — badges « i » des règles perso : d'ovales à ronds.
- **Hotfix** — crash au lancement de l'APK (scène principale absente).

## [v0.10.0] — 2026-11-19

**Beta mobile jouable.**

### Ajouté
- Export **Android APK** (arm64, signé debug) avec preset versionné.
- Champ **Serveur** configurable à l'accueil (accepte `hote.fr`,
  normalisé en `wss://…/ws`), version affichée à l'écran.
- `deploy/` : doc tunnel Cloudflare (rapide + nommé), Caddyfile,
  unit systemd — le serveur accepte `DOODO_ADDR`.

### Corrigé
- UI à l'échelle sur mobile (`canvas_items` + `expand`).

## [v0.9.7] — 2026-11-18

- **#10** — CI : actions migrées en runtime Node 24.

## [v0.9.6] — 2026-11-18

- **#5** — salle d'attente : l'hôte peut retirer un bot (croix).

## [v0.9.5] — 2026-11-18

- **#8** — popups des listes déroulantes : fond de survol thémé
  (lisible en sombre).

## [v0.9.4] — 2026-11-18

- **#7** — règles perso : badge « i » par option + modale de description.

## [v0.9.3] — 2026-11-18

- **#9** — direction « rétro arcade » : pixel font, bordures chunky,
  scanlines, palette néon — avec thème clair/sombre.

## [v0.9.2] — 2026-11-17

- Structure du dépôt : `prototype/` → `client/`, `shared/` comme
  contrat de messages.

## [v0.9.1] — 2026-11-17

- Durcissement des collisions de session : ping WebSocket + garde
  à la fermeture.

## [v0.9.0] — 2026-11-17

- CI GitHub Actions : `go test`/`vet`/`golangci-lint` + import Godot
  headless.

## [v0.8.0] — 2026-11-17

- **Règles perso (§1.5)** : Dé public, Double Paco, Salsa, Calzone,
  Pacobye — sélectionnables en options de table.

## [v0.7.0] — 2026-11-17

- Moteur de règles perso côté serveur : hooks de partie + métadonnées
  + activation par options.

## [v0.6.0] — 2026-11-16

- Effets sonores des événements de jeu + réglage volume/mute persisté.

## [v0.5.0] — 2026-11-16

- **Chat** : texte libre en salle d'attente, messages prédéfinis en jeu.

## [v0.4.0] — 2026-11-16

- **Lobby public** + liste des tables ; matchmaking rapide.
- Mode dieu rendu secret pour les non-créateurs et inerte en salle
  publique (§4.5).

## [v0.3.0] — 2026-11-15

- **Mode dieu (§4.5)** : en salle privée, le créateur choisit son
  tirage avant la première enchère et voit les dés de tous.

## [v0.2.0] — 2026-11-15

- **Options de table** configurables dans la salle d'attente
  (dés, minuteur, paco…).

## [v0.1.0] — 2026-11-15

- **Premier prototype jouable** : parties Perudo en ligne, personnages
  3D (Mii / KayKit), salons et forêt, lancers d'objets (tomates, œufs
  pourris, caca), bots, serveur Go/WebSocket autoritaire.
