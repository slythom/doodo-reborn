// Package protocol définit les contrats de messages échangés entre le client
// Godot et le serveur (specs_techniques §4). JSON, enveloppe {type, data}.
package protocol

import "doodo/internal/game"

// ---- Client -> serveur ----

// ClientMsg est l'enveloppe unique des commandes entrantes.
type ClientMsg struct {
	Type string `json:"type"`
	// hello
	Token string `json:"token,omitempty"` // jeton invité (vide = nouveau)
	Name  string `json:"name,omitempty"`
	// create
	Public  bool     `json:"public,omitempty"`
	Options *Options `json:"options,omitempty"`
	// join / spectate
	Code string `json:"code,omitempty"`
	// action
	Action   string `json:"action,omitempty"` // "bid" | "dudo" | "calza"
	Quantity int    `json:"quantity,omitempty"`
	Value    int    `json:"value,omitempty"`
	// chat / cible (kick, emote)
	Text   string `json:"text,omitempty"`
	Target string `json:"target,omitempty"`
	// room admin
	Bot bool `json:"bot,omitempty"` // add_bot / remove_bot
	// set_scene
	Scene string `json:"scene,omitempty"`
}

// ---- Options de table (specs §1.3) ----

type Options struct {
	Game           game.Options `json:"game"`
	TimerSeconds   int          `json:"timer_seconds"` // 0 = off
	MaxPlayers     int          `json:"max_players"`
	BotReplacement bool         `json:"bot_replacement"`
	Spectators     bool         `json:"spectators"`
	GodMode        bool         `json:"god_mode"` // salles privées uniquement
	Public         bool         `json:"public"`
	Scene          string       `json:"scene"` // décor 3D, choisi en salle d'attente, figé au lancement
}

// DefaultScene est le décor utilisé quand la valeur demandée est absente ou
// inconnue (vieux client, id retiré). specs_artistiques §3.
const DefaultScene = "salon"

// KnownScenes : ids de décor acceptés par le serveur. Le client garde les
// builders 3D ; le serveur n'a besoin que de la liste des ids valides.
var KnownScenes = map[string]bool{DefaultScene: true, "cimetiere": true, "foret": true}

// NormalizeScene retombe sur DefaultScene pour toute valeur absente ou inconnue.
func NormalizeScene(s string) string {
	if !KnownScenes[s] {
		return DefaultScene
	}
	return s
}

// ---- Serveur -> client : enveloppe ----

type Envelope struct {
	Type string `json:"type"`
	Data any    `json:"data,omitempty"`
}

type Welcome struct {
	Token string `json:"token"`
	Name  string `json:"name"`
}

type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type Notice struct {
	Kind     string `json:"kind"`               // "kicked" | "room_closed" | "chat" | "emote" | "info"
	From     string `json:"from,omitempty"`     // pseudo émetteur (chat/emote)
	Text     string `json:"text,omitempty"`     // message ou type d'emote
	Target   string `json:"target,omitempty"`   // siège cible (emote)
	FromSeat *int   `json:"from_seat,omitempty"` // siège émetteur (emote ; -1 = spectateur)
}

// ---- État de la salle (snapshot, specs §4 : complet à chaque changement) ----

type PlayerView struct {
	Seat      int    `json:"seat"` // -1 tant que la partie n'a pas commencé
	Name      string `json:"name"`
	Bot       bool   `json:"bot"`
	Connected bool   `json:"connected"`
	DiceCount int    `json:"dice_count"`
	Dice      []int  `json:"dice,omitempty"` // valeurs : soi-même, ou tous en god mode
}

type View struct {
	Code       string       `json:"code"`
	Name       string       `json:"name"` // « Table de <pseudo> »
	State      string       `json:"state"`
	Options    Options      `json:"options"`
	Host       string       `json:"host"`
	Players    []PlayerView `json:"players"`
	Spectators int          `json:"spectators"`
	// En jeu
	Round    int      `json:"round"`
	Turn     int      `json:"turn"`     // siège du joueur de tour, -1 si n/a
	Bid      game.Bid `json:"bid"`
	Bidder   int      `json:"bidder"`   // siège de l'enchérisseur, -1 si n/a
	HasBid   bool     `json:"has_bid"`
	Palifico bool     `json:"palifico"`
	Over     bool     `json:"over"`
	Winner   int      `json:"winner"`   // siège du vainqueur, -1 si n/a
	Ranking  []int    `json:"ranking,omitempty"`
	YourSeat int      `json:"your_seat"` // -1 pour les spectateurs
}

type Events struct {
	Events []game.Event `json:"events"`
}
