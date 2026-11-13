// Package game implémente le moteur de règles du Perudo (specs_fonctionnelles §1).
// Machine à états pure, sans dépendance réseau : Apply(action) -> (events, error).
package game

import (
	"errors"
	"fmt"
	"math/rand"
	"time"
)

const Paco = 1

var (
	ErrGameOver      = errors.New("game: partie terminée")
	ErrNotYourTurn   = errors.New("game: pas le tour de ce joueur")
	ErrIllegalBid    = errors.New("game: enchère illégale")
	ErrNoBid         = errors.New("game: aucune enchère en cours")
	ErrCalzaDisabled = errors.New("game: calza désactivé sur cette table")
	ErrUnknownAction = errors.New("game: action inconnue")
)

// Options de table — sous-ensemble de §1.3 qui affecte les règles.
// Les house rules (§1.5) s'ajouteront ici via des hooks, non en dur.
type Options struct {
	DicePerPlayer   int  `json:"dice_per_player"` // 3-5, défaut 5
	PacoJoker       bool `json:"paco_joker"`
	CalzaEnabled    bool `json:"calza_enabled"`
	PalificoEnabled bool `json:"palifico_enabled"`
}

func DefaultOptions() Options {
	return Options{DicePerPlayer: 5, PacoJoker: true, CalzaEnabled: true, PalificoEnabled: true}
}

func (o Options) validate() error {
	if o.DicePerPlayer < 3 || o.DicePerPlayer > 5 {
		return fmt.Errorf("game: %d dés de départ hors de [3,5]", o.DicePerPlayer)
	}
	return nil
}

// Bid est une enchère « au moins Quantity dés de valeur Value sur la table ».
type Bid struct {
	Quantity int `json:"quantity"`
	Value    int `json:"value"` // Paco (1) à 6
}

func (b Bid) String() string {
	if b.Value == Paco {
		return fmt.Sprintf("%d paco(s)", b.Quantity)
	}
	return fmt.Sprintf("%d x %d", b.Quantity, b.Value)
}

type ActionType int

const (
	ActionBid ActionType = iota
	ActionDudo
	ActionCalza
)

type Action struct {
	Type ActionType
	Bid  Bid // pour ActionBid uniquement
}

type EventType string

const (
	EvBid        EventType = "bid"         // Player a enchéri Bid
	EvReveal     EventType = "reveal"      // résolution : tous les dés dévoilés, Count réel vs Bid
	EvDieLost    EventType = "die_lost"    // Player perd un dé
	EvDieGained  EventType = "die_gained"  // Player regagne un dé (calza réussi)
	EvEliminated EventType = "eliminated"  // Player éliminé
	EvRoundStart EventType = "round_start" // nouvelle manche, Player entame
	EvPalifico   EventType = "palifico"    // la manche qui commence est une palifico
	EvGameOver   EventType = "game_over"   // Ranking = indices du 1er au dernier
)

type Event struct {
	Type    EventType `json:"type"`
	Player  int       `json:"player"`
	Bid     Bid       `json:"bid"`
	Count   int       `json:"count"`   // EvReveal : décompte réel
	Dice    [][]int   `json:"dice"`    // EvReveal : dés de chaque joueur (par siège)
	Ranking []int     `json:"ranking"` // EvGameOver : classement du 1er au dernier
	Calza   bool      `json:"calza,omitempty"` // EvReveal : provient d'un calza (vs dudo)
	Bidder  int       `json:"bidder,omitempty"` // EvReveal : siège de l'enchérisseur contesté
}

type Player struct {
	ID        string
	DiceCount int   // dés restants
	Dice      []int // valeurs du lancer de la manche courante
	Alive     bool
}

// Game est l'état complet d'une partie. Les joueurs sont indexés par leur
// siège ; le jeu tourne dans le sens horaire (index croissants).
type Game struct {
	Opts     Options
	Players  []*Player
	Round    int
	Turn     int // index du joueur dont c'est le tour
	Bidder   int // -1 si aucune enchère dans la manche
	Current  Bid
	HasBid   bool
	Palifico bool // la manche courante est une palifico
	Over     bool
	Winner   int // -1 tant que la partie n'est pas finie

	fixedV          int          // valeur figée pendant une palifico (0 = pas encore fixée)
	palificoPending bool         // une palifico est armée pour la prochaine manche
	palificoTrigger map[int]bool // joueurs ayant armé la palifico en attente
	palificoUsed    map[int]bool // a déjà armé une palifico cette partie
	elimOrder       []int        // ordre chronologique des éliminations
	roll            func() int   // tirage d'un dé (1-6), injectable pour les tests
}

// New crée une partie et lance la première manche. rng pilote les dés et le
// tirage du premier enchérisseur ; nil -> graine horloge.
func New(opts Options, ids []string, rng *rand.Rand) (*Game, error) {
	if err := opts.validate(); err != nil {
		return nil, err
	}
	if len(ids) < 2 || len(ids) > 6 {
		return nil, fmt.Errorf("game: %d joueurs hors de [2,6]", len(ids))
	}
	if rng == nil {
		rng = rand.New(rand.NewSource(time.Now().UnixNano()))
	}
	g := &Game{
		Opts:            opts,
		Bidder:          -1,
		Winner:          -1,
		palificoTrigger: map[int]bool{},
		palificoUsed:    map[int]bool{},
		roll:            func() int { return 1 + rng.Intn(6) },
	}
	for _, id := range ids {
		g.Players = append(g.Players, &Player{ID: id, DiceCount: opts.DicePerPlayer, Alive: true})
	}
	g.startRound(rng.Intn(len(ids)))
	return g, nil
}

// Apply applique l'action du joueur p (qui doit être le joueur de Turn).
func (g *Game) Apply(p int, a Action) ([]Event, error) {
	if g.Over {
		return nil, ErrGameOver
	}
	if p < 0 || p >= len(g.Players) || !g.Players[p].Alive || p != g.Turn {
		return nil, ErrNotYourTurn
	}
	switch a.Type {
	case ActionBid:
		if !g.LegalBid(a.Bid) {
			return nil, ErrIllegalBid
		}
		g.Current, g.Bidder, g.HasBid = a.Bid, p, true
		if g.Palifico && g.fixedV == 0 {
			g.fixedV = a.Bid.Value // le premier enchérisseur fixe la valeur
		}
		g.Turn = g.nextAlive(p)
		return []Event{{Type: EvBid, Player: p, Bid: a.Bid}}, nil
	case ActionDudo:
		if !g.HasBid {
			return nil, ErrNoBid
		}
		return g.resolve(p, false), nil
	case ActionCalza:
		if !g.HasBid {
			return nil, ErrNoBid
		}
		if !g.Opts.CalzaEnabled {
			return nil, ErrCalzaDisabled
		}
		return g.resolve(p, true), nil
	}
	return nil, ErrUnknownAction
}

// AutoAction joue l'action automatique d'expiration du timer (§1.4) :
// enchère minimale légale, jamais de Dudo/Calza.
func (g *Game) AutoAction(p int) ([]Event, error) {
	return g.Apply(p, Action{Type: ActionBid, Bid: g.MinBid()})
}

// Abandon élimine p en cours de partie (abandon, expulsion, déconnexion
// définitive). Ses dés sont retirés immédiatement du comptage ; l'enchère
// debout reste valable et le jeu continue au joueur suivant (§1.4).
func (g *Game) Abandon(p int) []Event {
	if g.Over || p < 0 || p >= len(g.Players) || !g.Players[p].Alive {
		return nil
	}
	g.Players[p].Alive = false
	g.Players[p].DiceCount = 0
	g.Players[p].Dice = nil
	g.elimOrder = append(g.elimOrder, p)
	evs := []Event{{Type: EvEliminated, Player: p}}
	if g.Turn == p {
		g.Turn = g.nextAlive(p)
	}
	if g.checkEnd(&evs) {
		return evs
	}
	return evs
}

// LegalBid applique la règle §1.2 + les transitions paco + les contraintes
// palifico (valeur figée, quantité croissante seule).
func (g *Game) LegalBid(b Bid) bool {
	if b.Quantity < 1 || b.Value < Paco || b.Value > 6 {
		return false
	}
	if !g.HasBid {
		// Ouverture de manche : pas de paco — sauf en palifico où la valeur
		// est libre (le premier enchérisseur la fixe, §1.3).
		return g.Palifico || b.Value != Paco
	}
	if g.Palifico && g.fixedV != 0 {
		return b.Value == g.fixedV && b.Quantity > g.Current.Quantity
	}
	c := g.Current
	switch {
	case c.Value == Paco && b.Value != Paco:
		return b.Quantity >= 2*c.Quantity+1 // quitter les pacos : min 2X+1
	case c.Value != Paco && b.Value == Paco:
		return b.Quantity >= (c.Quantity+1)/2 // passer aux pacos : min ceil(X/2)
	default:
		return b.Quantity > c.Quantity || (b.Quantity == c.Quantity && b.Value > c.Value)
	}
}

// MinBid est l'enchère minimale légale, utilisée par l'auto-action du timer.
func (g *Game) MinBid() Bid {
	if !g.HasBid {
		if g.Palifico {
			return Bid{Quantity: 1, Value: Paco}
		}
		return Bid{Quantity: 1, Value: 2} // ouverture : paco interdit
	}
	if g.Palifico && g.fixedV != 0 {
		return Bid{Quantity: g.Current.Quantity + 1, Value: g.fixedV}
	}
	if g.Current.Value == Paco {
		return Bid{Quantity: 2*g.Current.Quantity + 1, Value: 2}
	}
	return Bid{Quantity: g.Current.Quantity + 1, Value: g.Current.Value}
}

// count décompte les dés de valeur v sur la table. Les pacos comptent comme
// jokers si l'option est active, sauf pendant une palifico (§1.3) — et jamais
// quand l'enchère porte sur les pacos eux-mêmes.
func (g *Game) count(v int) int {
	jokers := g.Opts.PacoJoker && !g.Palifico && v != Paco
	n := 0
	for _, p := range g.Players {
		for _, d := range p.Dice {
			if d == v || (jokers && d == Paco) {
				n++
			}
		}
	}
	return n
}

func (g *Game) alivePlayers() []int {
	var alive []int
	for i, p := range g.Players {
		if p.Alive {
			alive = append(alive, i)
		}
	}
	return alive
}

func (g *Game) nextAlive(from int) int {
	for i := 1; i <= len(g.Players); i++ {
		if g.Players[(from+i)%len(g.Players)].Alive {
			return (from + i) % len(g.Players)
		}
	}
	return -1
}

// resolve clôt la manche après un Dudo (calza=false) ou un Calza (calza=true)
// appelés par challenger, puis démarre la suivante ou termine la partie.
func (g *Game) resolve(challenger int, calza bool) []Event {
	count := g.count(g.Current.Value)
	dice := make([][]int, len(g.Players))
	for i, p := range g.Players {
		dice[i] = append([]int{}, p.Dice...)
	}
	evs := []Event{{Type: EvReveal, Player: challenger, Bid: g.Current, Count: count, Dice: dice, Calza: calza, Bidder: g.Bidder}}

	var starter int
	if calza && count == g.Current.Quantity {
		// Calza réussi : le calzeur regagne un dé (plafonné à son nombre de
		// départ — §1.4 : au max, le calza ne fait que valider l'enchère).
		if c := g.Players[challenger]; c.DiceCount < g.Opts.DicePerPlayer {
			c.DiceCount++
			evs = append(evs, Event{Type: EvDieGained, Player: challenger})
		}
		starter = challenger
	} else {
		var loser int
		switch {
		case calza:
			loser = challenger // calza raté : le calzeur perd
		case count < g.Current.Quantity:
			loser = g.Bidder // enchère surestimée : l'enchérisseur perd
		default:
			loser = challenger // enchère tenue : le douteur perd
		}
		evs = append(evs, g.loseDie(loser)...)
		if g.Players[loser].Alive {
			starter = loser
		} else {
			starter = g.nextAlive(loser)
		}
	}

	if g.checkEnd(&evs) {
		return evs
	}
	return append(evs, g.startRound(starter)...)
}

// loseDie retire un dé au joueur p ; gère l'élimination et l'armement d'une
// palifico quand il tombe à exactement 1 dé (§1.3).
func (g *Game) loseDie(p int) []Event {
	pl := g.Players[p]
	pl.DiceCount--
	evs := []Event{{Type: EvDieLost, Player: p}}
	if pl.DiceCount <= 0 {
		pl.DiceCount = 0
		pl.Alive = false
		pl.Dice = nil
		g.elimOrder = append(g.elimOrder, p)
		evs = append(evs, Event{Type: EvEliminated, Player: p})
	} else if pl.DiceCount == 1 && g.Opts.PalificoEnabled && !g.palificoUsed[p] {
		g.palificoUsed[p] = true
		g.palificoPending = true
		g.palificoTrigger[p] = true
	}
	return evs
}

// startRound relance les dés, déclenche la palifico armée si un joueur
// déclencheur est encore en vie, et donne la main à starter.
func (g *Game) startRound(starter int) []Event {
	var evs []Event
	g.Round++
	g.HasBid = false
	g.Bidder = -1
	g.fixedV = 0
	g.Palifico = false
	if g.palificoPending {
		g.palificoPending = false
		for p := range g.palificoTrigger {
			if g.Players[p].Alive {
				g.Palifico = true
				break
			}
		}
		clear(g.palificoTrigger)
	}
	for _, p := range g.Players {
		if !p.Alive {
			p.Dice = nil
			continue
		}
		p.Dice = make([]int, p.DiceCount)
		for i := range p.Dice {
			p.Dice[i] = g.roll()
		}
	}
	g.Turn = starter
	if g.Palifico {
		evs = append(evs, Event{Type: EvPalifico, Player: -1})
	}
	evs = append(evs, Event{Type: EvRoundStart, Player: starter})
	return evs
}

// checkEnd termine la partie s'il ne reste qu'un joueur et, le cas échéant,
// ajoute EvGameOver avec le classement (vainqueur puis ordre d'élimination
// inversé : le dernier éliminé finit 2e, §1.4).
func (g *Game) checkEnd(evs *[]Event) bool {
	alive := g.alivePlayers()
	if len(alive) != 1 {
		return false
	}
	g.Over = true
	g.Winner = alive[0]
	ranking := []int{g.Winner}
	for i := len(g.elimOrder) - 1; i >= 0; i-- {
		ranking = append(ranking, g.elimOrder[i])
	}
	*evs = append(*evs, Event{Type: EvGameOver, Ranking: ranking})
	return true
}
