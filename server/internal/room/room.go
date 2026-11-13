// Package room gère le cycle de vie d'une table : salle d'attente, partie,
// reconnexions, bots, spectateurs et timer par action (specs §3-4).
//
// Toutes les méthodes publiques sont sérialisées par un mutex ; la room émet
// des protocol.Envelope via la fonction Emit injectée (nil to = broadcast à
// tous les membres connectés). Le temps est injecté via TimerFunc pour
// permettre des tests déterministes.
package room

import (
	"errors"
	"fmt"
	"log/slog"
	"math/rand"
	"sync"
	"time"

	"doodo/internal/bot"
	"doodo/internal/game"
	"doodo/internal/protocol"
)

var (
	ErrNotHost        = errors.New("room: action réservée à l'hôte")
	ErrNotEnough      = errors.New("room: il faut au moins 2 participants (bots compris)")
	ErrAlreadyStarted = errors.New("room: la partie a déjà commencé")
	ErrNotStarted     = errors.New("room: la partie n'a pas commencé")
	ErrFull           = errors.New("room: salle pleine")
	ErrKicked         = errors.New("room: vous avez été expulsé de cette table")
	ErrNoSpectators   = errors.New("room: spectateurs désactivés sur cette table")
	ErrNoSuchPlayer   = errors.New("room: joueur introuvable")
	ErrNoSuchTarget   = errors.New("room: cible introuvable")
	ErrPlayersOnly    = errors.New("room: action réservée aux joueurs")
	ErrCannotKickSelf = errors.New("room: l'hôte ne peut pas s'expulser")
)

const (
	DisconnectGrace  = 60 * time.Second // §4.2 : délai de reconnexion
	CancelDelay      = 2 * time.Minute  // §1.4 : annulation si plus aucun humain
	resolutionGrace  = 4 * time.Second  // marge du timer pendant la phase de révélation
)

type EmitFunc func(to []string, env protocol.Envelope)
type TimerFunc func(d time.Duration, f func()) interface{ Stop() bool }

type Member struct {
	ID            string
	Name          string
	Bot           bool
	Connected     bool
	Spectator     bool // a rejoint en spectateur ou a été éliminé
	ReplacedByBot bool // humain déconnecté remplacé par un bot (reprend la main au retour)
}

type Room struct {
	Code    string
	Name    string // « Table de <pseudo du créateur> »
	Opts    protocol.Options
	State   string // protocol State* — "lobby" | "playing" | "finished" | "cancelled"
	Host    string // member ID, "" si l'hôte est parti en cours de partie
	Creator string

	mu         sync.Mutex
	players    []*Member          // ordre d'arrivée en salle (ou sièges en partie)
	seats      []*Member          // index = index dans game.Players
	spectators map[string]*Member // spectateurs déclarés (option + en cours)
	kicked     map[string]bool    // bannis pour la durée de la table
	game       *game.Game
	botAI      *bot.Normal
	ranking    []int

	emit     EmitFunc
	rng      *rand.Rand
	newTimer TimerFunc

	timer     interface{ Stop() bool }
	timerGen  int
	cancelTmr interface{ Stop() bool }
	botSeq    int
}

func New(code string, creator *Member, opts protocol.Options, rng *rand.Rand, emit EmitFunc, tf TimerFunc) *Room {
	if opts.MaxPlayers < 2 || opts.MaxPlayers > 6 {
		opts.MaxPlayers = 6
	}
	if opts.Game.DicePerPlayer == 0 {
		opts.Game = game.DefaultOptions()
	}
	if rng == nil {
		rng = rand.New(rand.NewSource(rand.Int63()))
	}
	creator.Connected = true
	r := &Room{
		Code:       code,
		Name:       "Table de " + creator.Name,
		Opts:       opts,
		State:      "lobby",
		Host:       creator.ID,
		Creator:    creator.ID,
		spectators: map[string]*Member{},
		kicked:     map[string]bool{},
		emit:       emit,
		rng:        rng,
		newTimer:   tf,
		botAI:      bot.NewNormal(rng),
	}
	r.players = append(r.players, creator)
	r.sendViewLocked(creator) // snapshot initial pour le créateur
	return r
}

// ---- Salle d'attente ----

// Join ajoute un joueur (lobby) ou un spectateur (partie en cours).
func (r *Room) Join(m *Member) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.kicked[m.ID] {
		return ErrKicked
	}
	if r.State == "playing" {
		if !r.Opts.Spectators {
			return ErrNoSpectators
		}
		m.Spectator = true
		m.Connected = true
		r.spectators[m.ID] = m
		r.sendViewLocked(m)
		r.broadcastLocked()
		return nil
	}
	if r.State != "lobby" {
		return ErrAlreadyStarted
	}
	if len(r.players) >= r.Opts.MaxPlayers {
		return ErrFull
	}
	m.Connected = true
	r.players = append(r.players, m)
	r.broadcastLocked()
	return nil
}

func (r *Room) AddBot(byID string) (*Member, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if byID != r.Host {
		return nil, ErrNotHost
	}
	if r.State != "lobby" {
		return nil, ErrAlreadyStarted
	}
	if len(r.players) >= r.Opts.MaxPlayers {
		return nil, ErrFull
	}
	r.botSeq++
	m := &Member{ID: fmt.Sprintf("bot:%d", r.botSeq), Name: fmt.Sprintf("Bot %d", r.botSeq), Bot: true, Connected: true}
	r.players = append(r.players, m)
	r.broadcastLocked()
	return m, nil
}

func (r *Room) RemoveBot(byID, botID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if byID != r.Host {
		return ErrNotHost
	}
	for i, m := range r.players {
		if m.ID == botID && m.Bot {
			r.players = append(r.players[:i], r.players[i+1:]...)
			r.broadcastLocked()
			return nil
		}
	}
	return ErrNoSuchTarget
}

// Kick expulse un joueur de la salle — banni pour la durée de la table (§3.1).
func (r *Room) Kick(byID, targetID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if byID != r.Host {
		return ErrNotHost
	}
	if targetID == byID {
		return ErrCannotKickSelf
	}
	m := r.memberLocked(targetID)
	if m == nil {
		return ErrNoSuchTarget
	}
	r.kicked[targetID] = true
	r.emitLocked([]string{targetID}, protocol.Envelope{Type: "notice", Data: protocol.Notice{Kind: "kicked"}})
	r.removeLocked(m)
	r.broadcastLocked()
	return nil
}

// Launch démarre la partie (hôte uniquement, ≥ 2 participants, bots compris).
// Les sièges et le premier enchérisseur sont tirés au sort par le moteur.
func (r *Room) Launch(byID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if byID != r.Host {
		return ErrNotHost
	}
	if r.State != "lobby" {
		return ErrAlreadyStarted
	}
	if len(r.players) < 2 {
		return ErrNotEnough
	}
	r.seats = append([]*Member(nil), r.players...)
	r.rng.Shuffle(len(r.seats), func(i, j int) { r.seats[i], r.seats[j] = r.seats[j], r.seats[i] })
	ids := make([]string, len(r.seats))
	for i, m := range r.seats {
		ids[i] = m.ID
	}
	g, err := game.New(r.Opts.Game, ids, r.rng)
	if err != nil {
		return err
	}
	r.game = g
	r.State = "playing"
	r.broadcastLocked()
	r.armTurnLocked(0)
	return nil
}

// Rematch ramène la table en salle d'attente avec les mêmes options (§4.4).
// Réservé aux joueurs — les spectateurs regardent, ils ne décident pas.
func (r *Room) Rematch(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.State != "finished" {
		return nil
	}
	m := r.memberLocked(id)
	if m == nil {
		return ErrNoSuchPlayer
	}
	if _, spec := r.spectators[m.ID]; spec {
		return ErrPlayersOnly
	}
	r.game = nil
	r.seats = nil
	r.State = "lobby"
	for _, p := range r.players {
		p.ReplacedByBot = false
	}
	r.broadcastLocked()
	return nil
}

// ---- En jeu ----

// Act fait jouer le membre id (qui doit être le joueur de tour).
func (r *Room) Act(id string, a game.Action) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.State != "playing" {
		return ErrNotStarted
	}
	seat := r.seatOfLocked(id)
	if seat < 0 {
		return ErrNoSuchPlayer
	}
	evs, err := r.game.Apply(seat, a)
	if err != nil {
		return err
	}
	r.afterGameEventsLocked(evs)
	return nil
}

// afterGameEventsLocked diffuse les événements + snapshots, gère la fin de
// partie et réarme le timer de tour (suspendu pendant la résolution).
func (r *Room) afterGameEventsLocked(evs []game.Event) {
	reveal := false
	for _, e := range evs {
		if e.Type == game.EvReveal {
			reveal = true
		}
		if e.Type != game.EvBid {
			pname := ""
			if e.Player >= 0 && e.Player < len(r.seats) && r.seats[e.Player] != nil {
				pname = r.seats[e.Player].Name
			}
			slog.Info("game event", "room", r.Code, "type", e.Type, "player", pname, "bid", e.Bid, "count", e.Count)
		}
		if e.Type == game.EvEliminated {
			if m := r.seats[e.Player]; m != nil && !m.Bot {
				m.Spectator = true // les éliminés continuent de regarder
			}
		}
		if e.Type == game.EvGameOver {
			r.ranking = e.Ranking
		}
	}
	r.emitLocked(nil, protocol.Envelope{Type: "events", Data: protocol.Events{Events: evs}})
	r.broadcastLocked()
	if r.game.Over {
		r.State = "finished"
		r.stopTimerLocked()
		return
	}
	if reveal {
		r.armTurnLocked(resolutionGrace)
	} else {
		r.armTurnLocked(0)
	}
}

// ---- Présence ----

// Disconnected marque le membre hors-ligne : en salle il est retiré ; en
// partie, délai de grâce de 60 s puis bot ou élimination selon l'option (§4.2).
// Si plus aucun humain n'est connecté, la partie se met en pause (§1.4).
func (r *Room) Disconnected(id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.memberLocked(id)
	if m == nil || m.Bot {
		return
	}
	m.Connected = false
	if r.State == "lobby" {
		r.removeLocked(m)
		r.transferHostLocked()
		r.broadcastLocked()
		return
	}
	if r.State == "playing" {
		r.broadcastLocked()
		gen := r.timerGen
		r.newTimer(DisconnectGrace, func() { r.graceExpired(id, gen) })
	}
	r.checkHumansLocked()
}

// Reconnected réintègre le membre : reprise de main si un bot avait pris le
// relais, spectateur si éliminé entre-temps (§4.2).
func (r *Room) Reconnected(m *Member) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m.Connected = true
	if m.ReplacedByBot {
		m.ReplacedByBot = false
	}
	r.checkHumansLocked()
	r.sendViewLocked(m)
	r.broadcastLocked()
	if r.State == "playing" {
		r.armTurnLocked(0) // reprise : le timer repart
	}
}

func (r *Room) graceExpired(id string, gen int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.memberLocked(id)
	if m == nil || m.Connected || m.Bot {
		return
	}
	seat := r.seatOfLocked(id)
	if r.State != "playing" || seat < 0 || !r.game.Players[seat].Alive {
		return
	}
	if r.Opts.BotReplacement {
		m.ReplacedByBot = true
		r.broadcastLocked()
		if r.game.Turn == seat {
			r.armTurnLocked(0) // le bot prend la main
		}
		return
	}
	evs := r.game.Abandon(seat)
	r.afterGameEventsLocked(evs)
}

// Leave = abandon volontaire en partie (§4.2) ou départ de la salle.
// Retourne true si la room doit être fermée (plus aucun humain).
func (r *Room) Leave(id string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.memberLocked(id)
	if m == nil {
		return r.humanCountLocked() == 0
	}
	if r.State == "lobby" {
		r.removeLocked(m)
		r.transferHostLocked()
		r.broadcastLocked()
		return len(r.players) == 0 || r.onlyBotsLocked()
	}
	if r.State == "playing" {
		seat := r.seatOfLocked(id)
		m.Connected = false
		if id == r.Host {
			r.Host = "" // §4.2 : la table continue sans host
		}
		if seat >= 0 && r.game.Players[seat].Alive {
			evs := r.game.Abandon(seat)
			r.afterGameEventsLocked(evs)
		} else {
			if seat < 0 {
				r.removeLocked(m) // spectateur : simple départ
			}
			// éliminé : reste dans le roster (déconnecté) pour la vue/classement
			r.broadcastLocked()
		}
		r.checkHumansLocked()
		return r.humanCountLocked() == 0
	}
	if r.State == "finished" {
		r.removeLocked(m)
		r.transferHostLocked()
		r.broadcastLocked()
		return r.humanCountLocked() == 0
	}
	return false
}

// validEmotes est la whitelist des interactions visuelles (§4.3).
var validEmotes = map[string]bool{"tomato": true}

// Emote diffuse une interaction visuelle vers le siège cible (§4.3).
// Le serveur ne fait que valider et relayer — l'anim est côté client.
func (r *Room) Emote(id, targetSeat, kind string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.memberLocked(id)
	if m == nil || !validEmotes[kind] {
		return
	}
	fromSeat := r.seatOfLocked(id) // -1 si spectateur
	r.emitLocked(nil, protocol.Envelope{Type: "notice", Data: protocol.Notice{
		Kind: "emote", From: m.Name, Text: kind, Target: targetSeat, FromSeat: &fromSeat,
	}})
}

// Chat relaie un message au canal unique (joueurs + spectateurs, §4.3).
func (r *Room) Chat(id, text string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.memberLocked(id)
	if m == nil || text == "" {
		return
	}
	if len(text) > 200 {
		text = text[:200]
	}
	r.emitLocked(nil, protocol.Envelope{Type: "notice", Data: protocol.Notice{Kind: "chat", From: m.Name, Text: text}})
}

// Members retourne les membres joueurs (hors spectateurs) — pour le
// matchmaking qui compte les sièges.
func (r *Room) Members() []*Member {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]*Member(nil), r.players...)
}

// IsGodModeCreator indique si le mode dieu est actif pour ce membre.
func (r *Room) IsGodModeCreator(id string) bool {
	return r.Opts.GodMode && id == r.Creator
}

// ---- Internes ----

func (r *Room) memberLocked(id string) *Member {
	for _, m := range r.players {
		if m.ID == id {
			return m
		}
	}
	return r.spectators[id]
}

func (r *Room) seatOfLocked(id string) int {
	for i, m := range r.seats {
		if m.ID == id {
			return i
		}
	}
	return -1
}

func (r *Room) removeLocked(m *Member) {
	for i, p := range r.players {
		if p == m {
			r.players = append(r.players[:i], r.players[i+1:]...)
			return
		}
	}
	delete(r.spectators, m.ID)
}

func (r *Room) transferHostLocked() {
	if r.memberLocked(r.Host) != nil {
		return
	}
	r.Host = ""
	for _, m := range r.players { // plus ancien humain (§4.1)
		if !m.Bot {
			r.Host = m.ID
			return
		}
	}
}

func (r *Room) onlyBotsLocked() bool {
	for _, m := range r.players {
		if !m.Bot {
			return false
		}
	}
	return true
}

func (r *Room) humanCountLocked() int {
	n := 0
	for _, m := range r.players {
		if !m.Bot && m.Connected {
			n++
		}
	}
	for _, m := range r.spectators {
		if !m.Bot && m.Connected {
			n++
		}
	}
	return n
}

// checkHumansLocked met la partie en pause si plus aucun humain n'est
// connecté, et programme l'annulation à 2 min (§1.4).
func (r *Room) checkHumansLocked() {
	if r.State != "playing" {
		return
	}
	if r.humanCountLocked() == 0 {
		if r.cancelTmr == nil {
			r.stopTimerLocked() // pause : plus de timer de tour
			r.cancelTmr = r.newTimer(CancelDelay, func() {
				r.mu.Lock()
				defer r.mu.Unlock()
				if r.humanCountLocked() == 0 && r.State == "playing" {
					r.State = "cancelled"
					r.emitLocked(nil, protocol.Envelope{Type: "notice", Data: protocol.Notice{Kind: "room_closed"}})
				}
			})
		}
	} else if r.cancelTmr != nil {
		r.cancelTmr.Stop()
		r.cancelTmr = nil
	}
}

// armTurnLocked (re)programme l'action du joueur de tour : latence simulée
// pour un bot, timer auto-enchère pour un humain (§1.4).
func (r *Room) armTurnLocked(extra time.Duration) {
	r.stopTimerLocked()
	if r.State != "playing" || r.game == nil || r.game.Over {
		return
	}
	r.timerGen++
	gen, seat := r.timerGen, r.game.Turn
	m := r.seats[seat]
	if m == nil {
		return
	}
	if m.Bot || m.ReplacedByBot {
		delay := time.Duration(1000+r.rng.Intn(2000)) * time.Millisecond // 1-3 s (§5)
		r.timer = r.newTimer(delay, func() { r.botAct(gen, seat) })
		return
	}
	if r.Opts.TimerSeconds > 0 {
		d := time.Duration(r.Opts.TimerSeconds)*time.Second + extra
		r.timer = r.newTimer(d, func() { r.timeout(gen, seat) })
	}
}

func (r *Room) stopTimerLocked() {
	r.timerGen++
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
}

func (r *Room) botAct(gen, seat int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if gen != r.timerGen || r.State != "playing" || r.game.Turn != seat {
		return
	}
	m := r.seats[seat]
	if m == nil || (!m.Bot && !m.ReplacedByBot) {
		return
	}
	evs, err := r.game.Apply(seat, r.botAI.Decide(r.game, seat))
	if err != nil { // ne devrait pas arriver — repli sur l'auto-action
		evs, _ = r.game.AutoAction(seat)
	}
	r.afterGameEventsLocked(evs)
}

func (r *Room) timeout(gen, seat int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if gen != r.timerGen || r.State != "playing" || r.game.Turn != seat {
		return
	}
	evs, err := r.game.AutoAction(seat)
	if err != nil {
		return
	}
	r.afterGameEventsLocked(evs)
}

// ---- Diffusion ----

func (r *Room) emitLocked(to []string, env protocol.Envelope) {
	if r.emit == nil {
		return
	}
	if to == nil { // broadcast : tous les membres connectés (joueurs + spectateurs)
		for _, m := range r.players {
			if !m.Bot && m.Connected {
				to = append(to, m.ID)
			}
		}
		for _, m := range r.spectators {
			if m.Connected {
				to = append(to, m.ID)
			}
		}
	}
	r.emit(to, env)
}

// broadcastLocked envoie un snapshot personnalisé à chaque membre connecté.
func (r *Room) broadcastLocked() {
	for _, m := range r.players {
		if !m.Bot && m.Connected {
			r.sendViewLocked(m)
		}
	}
	for _, m := range r.spectators {
		if m.Connected {
			r.sendViewLocked(m)
		}
	}
}

func (r *Room) sendViewLocked(m *Member) {
	r.emitLocked([]string{m.ID}, protocol.Envelope{Type: "room_state", Data: r.viewForLocked(m)})
}

// viewForLocked construit le snapshot pour un destinataire : il ne voit que
// ses propres dés — sauf le créateur en mode dieu, qui voit tout (§4.5).
func (r *Room) viewForLocked(m *Member) *protocol.View {
	v := &protocol.View{
		Code:       r.Code,
		Name:       r.Name,
		State:      r.State,
		Options:    r.Opts,
		Host:       r.Host,
		Spectators: len(r.spectators),
		YourSeat:   -1,
		Players:    []protocol.PlayerView{}, // jamais null en JSON
	}
	if r.game != nil {
		v.Round, v.Turn = r.game.Round, r.game.Turn
		v.HasBid, v.Bid, v.Bidder = r.game.HasBid, r.game.Current, r.game.Bidder
		v.Palifico = r.game.Palifico
		v.Over, v.Winner = r.game.Over, r.game.Winner
	}
	godSeeAll := r.Opts.GodMode && m.ID == r.Creator
	for _, p := range r.players {
		pv := protocol.PlayerView{Seat: -1, Name: p.Name, Bot: p.Bot, Connected: p.Connected}
		if r.seats != nil {
			seat := r.seatOfLocked(p.ID)
			pv.Seat = seat
			gp := r.game.Players[seat]
			pv.DiceCount = gp.DiceCount
			if p.ID == m.ID || godSeeAll {
				pv.Dice = gp.Dice
			}
			if p.ID == m.ID {
				v.YourSeat = seat
			}
		}
		v.Players = append(v.Players, pv)
	}
	if r.game != nil && r.game.Over {
		v.Ranking = r.ranking
	}
	return v
}
