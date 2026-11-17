# Roadmap — Doodo

Découpage de la **beta** (releases 0.x, Android only, jeu complet en invité) en
milestones livrables et testables de bout en bout. Le périmètre détaillé est
dans `specs_fonctionnelles.md`, l'architecture dans `specs_techniques.md`.

Chaque milestone = une version mineure (`v0.x.0`) ; les correctifs suivent en
patch (`v0.x.y`). Convention : **patch = même périmètre** (fix, sous-tâche du
milestone — ex. `v0.9.1` = durcissement jetons), **mineur = nouveau périmètre**
(ex. une règle perso supplémentaire = `v0.11.0`, pas `v0.9.4`). La v1 (comptes,
stats persistantes, ELO, avatars, admin, anglais, iOS…) est hors scope de ce
document.

| Tag | Milestone | Contenu | Critère de sortie |
|---|---|---|---|
| **v0.1** | Socle jouable | Moteur Perudo + tests, rooms/hub/WS, matchmaking + bots « normal », client Godot jouable : salles privées par code, reconnexion 60 s, reveal 2D, émotes, game over | *Atteint* — partie complète jouable en privé |
| **v0.2** | Options de table | Message `set_options` validé serveur (options figées au lancement) + panneau éditable par l'hôte en salle d'attente : dés de départ, paco joker, calza, palifico, timer, max joueurs, remplacement bot, spectateurs. Lecture seule pour les autres (§1.3, §4.1) | Une partie privée entièrement configurable |
| **v0.3** | Mode dieu | Toggle réservé aux salles privées ; vision de tous les gobelets pour le créateur (déjà fait) + **choix de ses dés** à chaque manche (hook moteur + UI discrète) (§4.5) | Partie en mode dieu jouable, invisible pour les autres |
| **v0.4** | Lobby public | `list_rooms` côté serveur + écran lobby deux onglets « En attente / En cours » ; bascule publique/privée en salle ; spectate depuis « En cours » (§3.2) | Les trois portes d'entrée du §3 fonctionnelles |
| **v0.5** | Chat prédéfini | Texte libre restreint à la salle d'attente (validation serveur) ; messages prédéfinis + emotes prédéfinis en partie et en public (§4.3) | Aucun chat libre en jeu ; canal unique joueurs+spectateurs |
| **v0.6** | SFX | Sons embarqués : lancer de dés, gobelet, « Dudo ! », « Calza ! », révélation, dé perdu, élimination, victoire, notification de son tour ; réglage volume/muet (§4.3) | SFX audibles hors-ligne sur les moments clés |
| **v0.7** | House rules — moteur | `internal/rules` : interface de hooks (validation d'enchère, décompte, perte de dé, conditions de manche) + métadonnées `nom`/`description`/`incompatibilités`/`ranked_safe` (§1.5) | Framework testé, zéro règle implémentée ne change rien au jeu |
| **v0.8** | House rules — contenu | 5 règles implémentées (§1.5) : Dé public, Double Paco, Salsa, Calzone, Pacobye — toggles dans le panneau d'options + pills en jeu | Parties à règles perso jouables, dépendances/incompatibilités respectées |
| **v0.9** | Structure & qualité | Découpé en sous-tags : ~~`v0.9.0` = CI GitHub Actions (`go test`, `go vet`, `golangci-lint`, import headless Godot)~~ *livré* ; ~~`v0.9.1` = durcissement collision de jetons (§5, point ouvert)~~ *livré* — ping WS sur jeton déjà connecté : conn vivante → jeton neuf pour l'arrivant, zombie → reprise ; garde `onClose` ; `v0.9.2` = `prototype/` → `client/` + `shared/` (specs_techniques §3, §6) | Repo aligné sur l'architecture cible, CI verte |
| **v0.10** | Prod & playtest | Déploiement VPS : Caddy + systemd + `wss://` ; preset export Android ; playtest multi-appareils contre les indicateurs §9 (partie 4 joueurs sans bug bloquant, reconnexion, bots crédibles, 60 fps mid-range en 4G) | **Release beta publique** (Play Store, track beta) |

Notes :

- v0.9 est volontairement tardif (il ne livre rien de jouable) mais la CI peut
  être avancée à tout moment — elle profite à tous les milestones suivants.
- Les dépendances principales : v0.2 → v0.3 (le mode dieu est une option),
  v0.2 → v0.4 (bascule publique/privée dans le panneau d'options),
  v0.2 → v0.8 (toggles des règles). v0.5 et v0.6 sont indépendants.
- Après v0.10 : lancement v1 (périmètre complet de `specs_fonctionnelles.md`),
  releases 1.x/2.0 selon l'ampleur des évolutions.
