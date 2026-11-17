# Protocole WebSocket — Doodo

Contrat de messages échangés entre le client Godot (`client/net.gd`) et le
serveur Go (`server/internal/`). Source de vérité côté serveur :
`server/internal/protocol/protocol.go`. Specs : `specs_techniques.md` §4.

- Transport : **WebSocket**, un canal par joueur/spectateur, chemin `/ws`.
- Encodage : **JSON**.
- Le serveur est **autoritaire** : le client n'envoie que des intentions et
  ne reçoit que ce que son rôle l'autorise à voir (ses dés, jamais ceux des
  autres hors reveal/mode dieu/règle « Dé public »).

## Enveloppes

**Client → serveur** : message unique, discriminé par `type` ; les champs
inutilisés sont omis.

```json
{ "type": "<commande>", "...": "..." }
```

**Serveur → client** :

```json
{ "type": "<message>", "data": { ... } }
```

---

## Client → serveur

Premier message obligatoire après connexion : `hello` — tout autre type
ferme la connexion.

| `type` | Champs | Effet |
|---|---|---|
| `hello` | `token`, `name` | Identifie/ré-identifie le client. `token` vide ou inconnu → jeton neuf. Jeton déjà lié à une conn **vivante** → ping de celle-ci : si elle répond → jeton neuf pour l'arrivant (collision, §5) ; si zombie → reprise de la session |
| `create` | — | Crée une salle privée, l'auteur devient hôte/créateur |
| `join` | `code` | Rejoint une salle en attente (joueur ou spectateur si pleine/en jeu) |
| `quick` | — | Matchmaking : file publique, bots après 60 s |
| `list_rooms` | — | Liste les salles publiques (`room_list`) |
| `launch` | — | Démarre la partie (hôte uniquement, salle en attente) |
| `add_bot` | — | Ajoute un bot à la table (hôte, salle en attente) |
| `remove_bot` | `bot` | Retire un bot |
| `kick` | `target` | Exclut un joueur (hôte, salle en attente) |
| `set_options` | `options` | Modifie les options de table (hôte, salle en attente ; validé serveur) |
| `set_scene` | `scene` | Choisit le décor 3D (hôte ; id inconnu → `salon`) |
| `god_dice` | `dice` | Mode dieu (§4.5, salles privées) : le créateur impose son tirage |
| `action` | `action`, `quantity`, `value`, `seat` | Action de jeu : `bid` (`quantity`, `value`), `dudo`, `calza`, `steal` (`seat` = victime, règle Calzone) |
| `chat` | `text` | Chat : texte libre en salle d'attente ; **id prédéfini** en jeu |
| `emote` | `target`, `text` | Emote : `target` = siège cible (texte), `text` = id d'emote |
| `rematch` | — | Revanche après `game_over` (retour en salle d'attente) |
| `leave` | — | Quitte la salle (≠ déconnexion : pas de grace period) |

### `options` (objet `set_options`, présent dans `room_state`)

```json
{
  "game": {
    "dice_per_player": 5,         // 3-5
    "paco_joker": true,
    "calza_enabled": true,
    "palifico_enabled": true,
    "rules": ["salsa", "calzone"] // ids de règles perso (§1.5), omis si vide
  },
  "timer_seconds": 30,            // 0, 15, 30 ou 60
  "max_players": 6,               // 2-6
  "bot_replacement": true,        // bot remplace un déconnecté
  "spectators": true,
  "god_mode": false,              // inerte si la salle est publique (§4.5)
  "public": false,
  "scene": "salon"                // salon | cimetiere | foret
}
```

Règles perso connues (`rules`) : `de_public`, `double_paco` (requiert
`paco_joker`), `salsa`, `calzone` (requiert `calza_enabled`), `pacobye`.
Ids inconnus, incompatibles ou sans leur dépendance → rejetés à la
validation (`error`).

---

## Serveur → client

| `type` | `data` | Quand |
|---|---|---|
| `welcome` | `{token, name}` | Après `hello` — **le client doit persister `token`** (il peut différer de celui envoyé : collision ou jeton neuf) |
| `room_state` | `View` | Snapshot **complet** de la salle, à chaque changement (jointure, options, manche, enchère…) |
| `events` | `{events: [Event]}` | Événements de partie (enchère, révélation, perte de dé, fin) — déclenchent animations/SFX |
| `room_list` | `{rooms: [RoomSummary]}` | Réponse à `list_rooms` |
| `notice` | `{kind, from?, text?, target?, from_seat?}` | Annonces : `kicked`, `room_closed`, `chat`, `emote`, `info` |
| `error` | `{code, message}` | Action refusée/invalide |

### `View` (`room_state`) — champs notables

```json
{
  "code": "A6WE3R", "name": "Table de sly", "state": "waiting|playing|finished",
  "options": { "...": "voir ci-dessus" },
  "host": "<id membre>", "spectators": 0,
  "players": [{
    "seat": 0, "name": "sly", "bot": false, "connected": true,
    "dice_count": 5,
    "dice": [1,3,4,4,6],      // présent seulement pour soi (ou tous en god mode)
    "pub_dice": [3]           // dés dévoilés à tous (règle « Dé public »)
  }],
  "round": 2, "turn": 1, "bid": {"quantity":4,"value":5}, "bidder": 1,
  "has_bid": true, "palifico": false,
  "over": false, "winner": -1, "ranking": [],
  "your_seat": 0,             // -1 pour les spectateurs
  "creator": true, "god": false,
  "steal_pending": -1         // siège du calzeur devant choisir (Calzone), -1 sinon
}
```

### `Event` (dans `events`)

| `type` | Champs significatifs | Sens |
|---|---|---|
| `bid` | `player`, `bid` | Enchère posée |
| `round_start` | `player` | Nouvelle manche, joueur entamant |
| `palifico` | — | La manche qui commence est palifico |
| `reveal` | `player`, `bid`, `count`, `dice` (tous), `calza`, `bidder` | Révélation après dudo/calza — écran dédié côté client |
| `die_lost` | `player` | Dé perdu |
| `die_gained` | `player` | Dé regagné (calza réussi) ou volé (Calzone) |
| `steal_pending` | `player` | Calzone : le calzeur doit désigner sa victime (`action:steal`) |
| `eliminated` | `player` | Joueur éliminé (dont Pacobye au tirage) |
| `game_over` | `ranking` | Fin de partie, classement du 1er au dernier |

---

## Cycle de vie d'une connexion

1. WS ouvert → `hello` (token persisté si présent) → `welcome`.
2. `create`/`join`/`quick` → `room_state` (salle d'attente).
3. `launch` → `room_state` (`state:playing`) + `events`.
4. Déconnexion réseau : le joueur est marqué `connected:false`, grace
   period **60 s** ; reconnexion via `hello` + même token → reprise du
   siège (resync `room_state`). Option `bot_replacement` : un bot joue
   à sa place pendant l'absence.
5. `leave` : sortie volontaire immédiate.
