# Specs techniques — Doodo

Complète `specs_fonctionnelles.md` (règles/produit) et `specs_artistiques.md` (DA/pipeline assets).

*État : décisions de stack actées ; quelques choix fins marqués « À trancher » avec recommandation.*

---

## 1. Stack retenue

| Couche | Choix | Pourquoi |
|---|---|---|
| Client | **Godot 4.7** (GDScript), renderer **Mobile** | Gratuit/MIT, 3D suffisante pour la DA low-poly, exports iOS/Android/Web |
| Assets | **Blender** piloté en script (`--python` / MCP) → `.glb` | Gratuit, pipeline versionné (`assets/*.py`) |
| Backend | **Go** (stdlib + `coder/websocket`) | Un binaire, goroutines par room, idéal temps réel |
| Transport | **WebSocket over TLS** (`wss://`) | Jeu au tour par tour — pas besoin d'UDP |
| Hébergement | **VPS Linux** unique | Caddy pour TLS, systemd pour le service |
| Persistance | **Rien en v1** ; **SQLite** v1.5 (`modernc.org/sqlite`) | V1 sans comptes = pas de BDD nécessaire |

---

## 2. Architecture générale

**Serveur autoritaire.** L'état de chaque partie (dés, enchères, règles, timers) vit uniquement sur le serveur. Les clients sont des **renderer + input** : ils envoient des intentions, le serveur diffuse l'état résultant. Conséquences :

- **Anti-triche naturelle** : les dés adverses ne quittent jamais le serveur ; un client ne connaît que ses propres dés.
- **Mode dieu / spectateurs** : simples variations du payload d'état par rôle (admin voit tout, spectateur voit les comptes, joueur voit ses dés).
- **Reconnexion** : le jeton invité (UUID stocké localement) ré-identifie le joueur dans le handshake WS ; le serveur réinjecte l'état courant.
- **Bots** : tournent côté serveur comme des joueurs internes — même interface que les clients distants, latence simulée 1-3 s.

**Modèle de synchro** : le serveur pousse un **snapshot d'état complet** de la room à chaque changement (petit payload : ≤6 joueurs, ~30 dés, une enchère) plutôt qu'un diff — plus simple, aucune perte de cohérence, bande passante anecdotique.

---

## 3. Structure du repo (monorepo)

```
doodo-reborn/
├── client/            # projet Godot (jeu)
│   ├── scenes/        # main, lobby, room, game3d, hud
│   ├── scripts/       # net/, ui/, game3d/, characters/
│   └── assets/        # .glb générés, textures, sfx
├── assets_src/        # générateurs Blender versionnés (ex. make_mii.py)
├── server/            # module Go
│   ├── cmd/doodo-server/
│   └── internal/
│       ├── game/      # moteur Perudo pur (règles §1), zéro dépendance réseau
│       ├── rules/     # house rules modulaires (§1.5)
│       ├── room/      # cycle de vie d'une table (lobby→partie→fin)
│       ├── hub/       # connexions WS, routage messages
│       ├── matchmaking/
│       ├── bot/       # IA normal (v1)
│       └── store/     # (v1.5) SQLite, comptes, stats
├── shared/            # contrats messages (schémas JSON) partagés client/serveur
├── prototype/         # proto DA actuel (référence, sera absorbé par client/)
└── specs_*.md
```

*Acté : **monorepo** (contrats partagés, refactors atomiques, un seul historique).*

---

## 4. Protocole réseau

- **WebSocket**, un canal par joueur/spectateur. Payload **JSON** *(acté)* : lisible, debuggable ; binaire seulement si un problème de perf apparaît (peu probable à cette échelle).
- **Client → serveur (commandes)** : `hello` (pseudo+jeton), `create_room` (options), `join` (code/file), `ready/launch`… en partie : `bid` (X,V), `dudo`, `calza`, `chat` (id message/emote), `leave`, `tap_emote` (cible, type — ex. tomate).
- **Serveur → client (états/événements)** : `room_state` (snapshot), `round_started` (tes dés), `bid_made`, `reveal` (dés de tous + résultat), `dice_lost`, `player_eliminated`, `game_over` (classement), `emote` (auteur, cible, type), `error` (code, message).
- **Règles du protocole** : toute action est validée serveur (tour, légalité d'enchère §1.2) ; le client affiche seulement ce que son rôle autorise.
- Schémas formalisés dans `shared/` (JSON Schema ou simple doc + types Go/generation côté client plus tard).

*Acté : **REST pour auth/profil (v1.5), WS pour le jeu** — séparation propre.*

---

## 5. Serveur — détails

- **Concurrence** : modèle acteur — **une goroutine par room** possède l'état de la partie (aucune serrure dans le moteur) ; une goroutine lecteur + une écrivain par connexion WS ; le hub ne fait que router.
- **Moteur `internal/game`** : machine à états pure — `Apply(action) → (events, error)`. Entrées : actions joueurs ; sorties : événements + nouvel état. **Très testable** : les règles §1 (enchères, Dudo, Calza, Palifico, auto-enchère, cas limites §1.4) sont couvertes en table-driven tests sans aucune couche réseau.
- **House rules `internal/rules`** : chaque règle = interface de hooks (validation d'enchère, décompte, perte de dé, conditions de manche) + métadonnées `nom/description/incompatibilités/ranked_safe` (§1.5).
- **Timer/auto-enchère** : `time.Timer` par tour dans la room ; expiration → action auto (formule §1.4) injectée dans la même machine à états.
- **Déconnexion** : joueur marqué `disconnected` (badge diffusé) + deadline 60 s ; pendant ce délai, remplacement bot ou élimination selon l'option de table ; le jeton invité ré-identifie le joueur au retour → reprise du siège si la partie n'est pas finie.
- **Matchmaking** : file in-memory ; à 60 s → remplissage bots automatique (§3.3).
- **Persistance v1.5** : `internal/store` + SQLite ; schéma : comptes, jetons invités, stats agrégées. Parties non classées (`ranked_safe:false`, mode dieu) exclues.
- **Point ouvert — collision de jetons** : aujourd'hui un `hello` avec un jeton déjà associé à une connexion vivante **vole silencieusement la session** (les deux clients reçoivent alors la même vue / se disputent le routage). Inoffensif en prod (jeton 128 bits aléatoire, un device = un jeton) mais à durcir avant v1.5 : au `hello`, si le jeton a une conn vivante → ping de celle-ci ; si elle répond → nouveau jeton pour le nouvel arrivant (identité distincte), sinon → reprise normale (conn zombie). + garder `conns[token] = c` dans `onClose` sous condition (ne pas effacer l'entrée si la conn a été remplacée). *Dev : tester plusieurs instances locales via `DOODO_PROFILE=<id>` (fichier session séparé).*

---

## 6. Client Godot — détails

- **Scènes** : `Main` (routeur d'écrans) → `Lobby`, `RoomView` (salle d'attente), `Game3D` (table+personnages) + `HUD` (CanvasLayer). Navigation par état serveur, pas par logique locale.
- **`net/`** : `WsClient` (WebSocketPeer, reconnexion + jeton), `GameState` (dernier snapshot, signaux émis vers l'UI/3D).
- **`game3d/`** : scène de table state-driven — les positions/visibilité de gobelets, dés, mains se déduisent du snapshot ; les événements (`bid_made`, `reveal`…) déclenchent les animations.
- **Renderer Mobile**, portrait verrouillé, assets `.glb` générés (cf. specs_artistiques).
- **Exports** : preset Android (SDK requis) ; iOS via Xcode — **nécessite un Mac** (à provisionner avant v1.5 : machine ou CI macos).
- **Absorber le proto** : `prototype/` devient la base de `client/` (Miis, table, interactions déjà validées).

*Acté : révélation Dudo/Calza en **écran 2D dédié** (overlay au-dessus de la scène 3D ; cf. specs_artistiques §7 — lisibilité du décompte, dés alignés).*

---

## 7. Déploiement & exploitation

- **Un seul binaire Go** (`doodo-server`) servi par **Caddy** (TLS auto, reverse-proxy WS) sur le VPS ; **systemd** pour le service. *Acté : **pas de Docker** en v1 (binaire unique = rien à conteneuriser ; à ajouter seulement si infra gérée ou Postgres en v2).*
- État en mémoire → le serveur tolère le redémarrage (parties perdues = retour lobby côté client ; acceptable en v1, à documenter).
- Logs structurés (`slog`) ; métriques basiques plus tard si besoin.
- Pas de scaling horizontal en v1 (un process suffit largement à l'échelle visée).

---

## 8. Qualité / tests

- **Priorité #1 : `internal/game`** — le moteur de règles est le code le plus testable et le plus critique (enchères, Palifico, cas limites §1.4, house rules). Table-driven tests exhaustifs.
- **`internal/room`** : tests de cycle de vie (join/leave/launch/abandon) avec fake WS.
- **Client** : pas de framework de test Godot requis en proto ; smoke test headless (`--quit-after`) déjà utilisé — à garder comme CI minimale.
- **CI** : GitHub Actions — `go test`, `go vet`, `golangci-lint`, import headless du projet Godot.

---

## 9. Ordre de construction suggéré

1. `internal/game` moteur + tests (jouable en CLI de debug)
2. `hub` + `room` + WS (partie jouable via client brut/JSON)
3. `client/` Godot : lobby minimal + Game3D branché sur snapshots (base proto existante)
4. Matchmaking + bots normal
5. Polish : spectateurs, reconnexion, SFX, emotes animées
6. V1.5 : comptes/stats/admin
