# Changelog

Toutes les modifications notables de Doodo, par version.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [Non publié]

### Modifié
- **#15** — enchère : le stepper de quantité propose par défaut la
  quantité de l'enchère en cours (« 8 » après un 8×5) au lieu de
  repartir à 1. La face choisie reste inchangée ; nouvelle manche
  sans enchère → retour à 1.

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
