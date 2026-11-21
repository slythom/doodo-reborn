// Package hub gère les connexions WebSocket, le routage des commandes vers
// les rooms, le lobby et le matchmaking (specs_techniques §5, specs §3-4).
//
// Modèle : une goroutine lecteur + une goroutine écrivain par connexion ;
// chaque room possède son état sous son propre mutex. Les rooms émettent des
// protocol.Envelope adressés à des member IDs (token invité pour les humains).
package hub

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net/http"
	"sort"
	"sync"
	"time"

	"github.com/coder/websocket"

	"doodo/internal/game"
	"doodo/internal/protocol"
	"doodo/internal/room"
)

const (
	writeTimeout = 10 * time.Second
	sendBuffer   = 32
	// §3.1 : code salle — A-Z2-9 privé de I/O/0/1, insensible à la casse.
	codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	codeLen      = 6

	matchmakeSize    = 6                // cible joueurs
	matchmakeTimeout = 60 * time.Second // remplissage bots auto (§3.3)
)

// session identifie un client authentifié par son jeton invité.
type session struct {
	token  string
	name   string
	room   *room.Room
	member *room.Member
}

// conn est une connexion WS active, adressable par le token de sa session.
type conn struct {
	ws   *websocket.Conn
	send chan []byte
	done chan struct{}
}

type Hub struct {
	mu       sync.Mutex
	rooms    map[string]*room.Room // code -> room
	sessions map[string]*session   // token -> session
	conns    map[string]*conn      // token -> conn
	queue    []*session            // file matchmaking
	queueTmr *time.Timer
}

func New() *Hub {
	return &Hub{
		rooms:    map[string]*room.Room{},
		sessions: map[string]*session{},
		conns:    map[string]*conn{},
	}
}

// ---- HTTP ----

func (h *Hub) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /ws", h.serveWS)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	return mux
}

func (h *Hub) serveWS(w http.ResponseWriter, r *http.Request) {
	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// Origins non vérifiées en dev — à restreindre en prod.
		InsecureSkipVerify: true,
	})
	if err != nil {
		slog.Warn("ws accept", "err", err)
		return
	}
	c := &conn{ws: ws, send: make(chan []byte, sendBuffer), done: make(chan struct{})}
	go h.writePump(c)
	go h.pingPump(c)
	h.readPump(r.Context(), c)
}

// ---- Pumps ----

func (h *Hub) writePump(c *conn) {
	for {
		select {
		case buf := <-c.send:
			ctx, cancel := context.WithTimeout(context.Background(), writeTimeout)
			err := c.ws.Write(ctx, websocket.MessageText, buf)
			cancel()
			if err != nil {
				return
			}
		case <-c.done:
			return
		}
	}
}

// pingPump garde la socket vivante par un ping WS toutes les 25 s (#29) :
// les NAT mobiles/4G coupent les connexions idle (~60-120 s) sinon. Un
// ping en échec ferme la conn pour réveiller readPump au plus vite.
func (h *Hub) pingPump(c *conn) {
	t := time.NewTicker(25 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-t.C:
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			err := c.ws.Ping(ctx)
			cancel()
			if err != nil {
				_ = c.ws.Close(websocket.StatusInternalError, "ping timeout")
				return
			}
		case <-c.done:
			return
		}
	}
}

func (h *Hub) readPump(ctx context.Context, c *conn) {
	defer func() {
		_ = c.ws.Close(websocket.StatusNormalClosure, "bye")
		close(c.done)
	}()
	// Premier message obligatoire : hello (token + pseudo).
	var sess *session
	for {
		_, data, err := c.ws.Read(ctx)
		if err != nil {
			h.onClose(c, sess)
			return
		}
		var msg protocol.ClientMsg
		if err := json.Unmarshal(data, &msg); err != nil {
			h.sendErr(c, "bad_json", "message JSON invalide")
			continue
		}
		if sess == nil {
			if msg.Type != "hello" {
				h.sendErr(c, "hello_first", "premier message attendu: hello")
				continue
			}
			sess = h.hello(c, msg)
			continue
		}
		h.dispatch(c, sess, msg)
	}
}

// ---- Dispatch ----

func (h *Hub) dispatch(c *conn, s *session, m protocol.ClientMsg) {
	switch m.Type {
	case "create":
		h.createRoom(c, s, m)
	case "join":
		h.joinRoom(c, s, m)
	case "quick":
		h.quickMatch(c, s)
	case "launch":
		h.roomCall(c, s, func(r *room.Room) error { return r.Launch(s.token) })
	case "add_bot":
		h.roomCall(c, s, func(r *room.Room) error {
			_, err := r.AddBot(s.token)
			return err
		})
	case "remove_bot":
		h.roomCall(c, s, func(r *room.Room) error { return r.RemoveBot(s.token, m.Target) })
	case "kick":
		h.roomCall(c, s, func(r *room.Room) error { return r.Kick(s.token, m.Target) })
	case "set_scene":
		h.roomCall(c, s, func(r *room.Room) error { return r.SetScene(s.token, m.Scene) })
	case "set_options":
		h.roomCall(c, s, func(r *room.Room) error { return r.SetOptions(s.token, m.Options) })
	case "god_dice":
		h.roomCall(c, s, func(r *room.Room) error { return r.GodDice(s.token, m.Dice) })
	case "rematch":
		h.roomCall(c, s, func(r *room.Room) error { return r.Rematch(s.token) })
	case "action":
		h.gameAction(c, s, m)
	case "chat":
		if s.room != nil {
			s.room.Chat(s.token, m.Text)
		}
	case "emote":
		if s.room != nil {
			s.room.Emote(s.token, m.Target, m.Text)
		}
	case "list_rooms":
		h.listRooms(c)
	case "leave":
		h.leave(s)
	case "hello":
		// Idempotent : re-welcome + resync room_state (retour au menu,
		// snapshot perdu côté client…). Le token de session est conservé.
		if s.room != nil && s.member != nil {
			s.room.Reconnected(s.member)
		}
		h.deliver(c, protocol.Envelope{Type: "welcome", Data: protocol.Welcome{Token: s.token, Name: s.name}})
	default:
		h.sendErr(c, "unknown_type", "type de message inconnu: "+m.Type)
	}
}

func (h *Hub) gameAction(c *conn, s *session, m protocol.ClientMsg) {
	var a game.Action
	switch m.Action {
	case "bid":
		a = game.Action{Type: game.ActionBid, Bid: game.Bid{Quantity: m.Quantity, Value: m.Value}}
	case "dudo":
		a = game.Action{Type: game.ActionDudo}
	case "calza":
		a = game.Action{Type: game.ActionCalza}
	case "steal":
		a = game.Action{Type: game.ActionSteal, Target: m.Seat}
	default:
		h.sendErr(c, "bad_action", "action inconnue: "+m.Action)
		return
	}
	h.roomCall(c, s, func(r *room.Room) error { return r.Act(s.token, a) })
}

// ---- Sessions / rooms ----

func (h *Hub) hello(c *conn, m protocol.ClientMsg) *session {
	token := m.Token
	name := m.Name
	if name == "" {
		name = "invité"
	}
	// Durcissement des collisions de jetons (§5) : un jeton déjà associé
	// à une conn vivante n'est pas volé — le nouvel arrivant (autre
	// device, instance partageant la session.cfg) reçoit un jeton neuf.
	// Une conn zombie (socket morte pas encore détectée, ping sans
	// réponse) cède la place : c'est le cas normal de la reconnexion.
	var zombie *conn
	if token != "" {
		h.mu.Lock()
		old := h.conns[token]
		h.mu.Unlock()
		if old != nil && old != c {
			if h.connAlive(old) {
				token = newToken()
			} else {
				zombie = old
			}
		}
	}
	if token == "" {
		token = newToken()
	}

	h.mu.Lock()
	// La conn zombie a pu être remplacée pendant le ping : si le jeton
	// est désormais occupé par une AUTRE conn, on ne la vole pas non plus.
	if zombie != nil {
		if cur := h.conns[token]; cur != nil && cur != zombie {
			zombie = nil
			token = newToken()
		}
	}
	s := h.sessions[token]
	if s == nil {
		s = &session{token: token}
		h.sessions[token] = s
	}
	s.name = name
	h.conns[token] = c
	h.mu.Unlock()

	// Prise de relais : la conn zombie est refermée APRÈS l'enregistrement
	// de la nouvelle — la garde de onClose ignore alors sa fermeture.
	if zombie != nil {
		_ = zombie.ws.Close(websocket.StatusPolicyViolation, "session reprise")
	}
	// Reconnexion : si le membre existe encore dans une room, on le réintègre.
	if s.room != nil && s.member != nil {
		s.room.Reconnected(s.member)
	}
	h.deliver(c, protocol.Envelope{Type: "welcome", Data: protocol.Welcome{Token: token, Name: name}})
	slog.Info("hello", "token", token[:8], "name", name, "rejoin", s.room != nil)
	return s
}

// connAlive sonde la conn par un ping WS (2 s max) : réponse = conn
// vivante ; échec ou timeout = socket zombie (morte sans que readPump
// l'ait encore détecté — la détection TCP seule prend du temps).
func (h *Hub) connAlive(c *conn) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return c.ws.Ping(ctx) == nil
}

func (h *Hub) createRoom(c *conn, s *session, m protocol.ClientMsg) {
	h.leave(s) // une session ne vit que dans une salle à la fois
	opts := protocol.Options{
		Game:           game.DefaultOptions(),
		TimerSeconds:   30,
		MaxPlayers:     6,
		BotReplacement: true,
		Spectators:     true,
		Public:         m.Public,
	}
	if m.Options != nil {
		opts = *m.Options
		opts.Public = m.Public
	}
	code := h.newCode()
	member := &room.Member{ID: s.token, Name: s.name}
	r := room.New(code, member, opts, nil, h.emit, func(d time.Duration, f func()) interface{ Stop() bool } {
		return time.AfterFunc(d, f)
	})
	h.mu.Lock()
	h.rooms[code] = r
	h.mu.Unlock()
	h.joinSession(s, r, member)
	slog.Info("room créée", "code", code, "par", s.name)
}

func (h *Hub) joinRoom(c *conn, s *session, m protocol.ClientMsg) {
	h.mu.Lock()
	r := h.rooms[m.Code]
	h.mu.Unlock()
	if r == nil {
		h.sendErr(c, "no_room", "code inconnu: "+m.Code)
		return
	}
	if s.room == r {
		return // déjà dedans
	}
	h.leave(s)
	member := &room.Member{ID: s.token, Name: s.name}
	if err := r.Join(member); err != nil {
		h.sendErr(c, "join_failed", err.Error())
		return
	}
	h.joinSession(s, r, member)
}

func (h *Hub) joinSession(s *session, r *room.Room, member *room.Member) {
	h.mu.Lock()
	s.room = r
	s.member = member
	h.mu.Unlock()
}

// leave = abandon volontaire / départ de la salle.
func (h *Hub) leave(s *session) {
	h.mu.Lock()
	r := s.room
	h.mu.Unlock()
	if r == nil {
		return
	}
	if r.Leave(s.token) {
		h.destroyRoom(r)
	}
	h.mu.Lock()
	s.room = nil
	s.member = nil
	h.mu.Unlock()
}

// onClose : la connexion tombe — grace period côté room (≠ leave volontaire).
// Garde : si conns[token] pointe désormais sur une AUTRE conn (reprise de
// session par un client reconnecté), cette fermeture n'y touche pas (§5).
func (h *Hub) onClose(c *conn, s *session) {
	if s == nil {
		return
	}
	h.mu.Lock()
	if h.conns[s.token] != c {
		h.mu.Unlock()
		return
	}
	delete(h.conns, s.token)
	r := s.room
	h.mu.Unlock()
	if r != nil {
		r.Disconnected(s.token)
	}
}

func (h *Hub) destroyRoom(r *room.Room) {
	h.mu.Lock()
	for code, rr := range h.rooms {
		if rr == r {
			delete(h.rooms, code)
		}
	}
	// détache les sessions pointant sur cette room
	for _, s := range h.sessions {
		if s.room == r {
			s.room = nil
			s.member = nil
		}
	}
	h.mu.Unlock()
}

// listRooms répond à la demande de lobby public (§3.2) : tables publiques
// joignables (« En attente ») ou observables (« En cours », si l'option
// spectateurs est active). Tri par code pour un ordre stable.
func (h *Hub) listRooms(c *conn) {
	h.mu.Lock()
	rooms := make([]*room.Room, 0, len(h.rooms))
	for _, r := range h.rooms {
		rooms = append(rooms, r)
	}
	h.mu.Unlock()
	var list []protocol.RoomSummary
	for _, r := range rooms {
		sum := r.Summary()
		if !sum.Options.Public {
			continue
		}
		if sum.State == "lobby" || (sum.State == "playing" && sum.Options.Spectators) {
			list = append(list, sum)
		}
	}
	sort.Slice(list, func(i, j int) bool { return list[i].Code < list[j].Code })
	slog.Info("room list", "rooms", list)
	h.deliver(c, protocol.Envelope{Type: "room_list", Data: protocol.RoomList{Rooms: list}})
	slog.Info("delivered room list", "rooms", list)
}

// ---- Matchmaking (§3.3) ----

func (h *Hub) quickMatch(c *conn, s *session) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if s.room != nil {
		h.sendErr(c, "already_in_room", "déjà dans une salle")
		return
	}
	for _, q := range h.queue {
		if q == s {
			return // déjà en file
		}
	}
	h.queue = append(h.queue, s)
	if len(h.queue) == 1 {
		h.queueTmr = time.AfterFunc(matchmakeTimeout, h.matchmakeTimeout)
	}
	if len(h.queue) >= matchmakeSize {
		h.matchmakeLocked()
	}
}

// matchmakeTimeout : 60 s sans 6 joueurs → remplissage automatique par bots.
func (h *Hub) matchmakeTimeout() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.matchmakeLocked()
}

func (h *Hub) matchmakeLocked() {
	if len(h.queue) == 0 {
		return
	}
	if h.queueTmr != nil {
		h.queueTmr.Stop()
		h.queueTmr = nil
	}
	opts := protocol.Options{ // options standard (§3.3)
		Game:           game.DefaultOptions(),
		TimerSeconds:   30,
		MaxPlayers:     6,
		BotReplacement: true,
		Spectators:     true,
		Public:         true,
	}
	first := h.queue[0]
	member := &room.Member{ID: first.token, Name: first.name}
	r := room.New(h.newCode(), member, opts, nil, h.emit,
		func(d time.Duration, f func()) interface{ Stop() bool } { return time.AfterFunc(d, f) })
	h.rooms[r.Code] = r
	h.joinSession(first, r, member)

	for _, s := range h.queue[1:] {
		m := &room.Member{ID: s.token, Name: s.name}
		if err := r.Join(m); err == nil {
			h.joinSession(s, r, m)
		}
	}
	// Remplissage bots jusqu'à 6.
	for len(r.Members()) < matchmakeSize {
		if _, err := r.AddBot(first.token); err != nil {
			break
		}
	}
	h.queue = h.queue[:0]
	_ = r.Launch(first.token)
	slog.Info("matchmaking : partie lancée", "code", r.Code)
}

// ---- Émission ----

// emit est injectée dans chaque room : to = member IDs, vide = broadcast
// à tous les membres de la room.
func (h *Hub) emit(to []string, env protocol.Envelope) {
	buf, err := json.Marshal(env)
	if err != nil {
		slog.Error("marshal", "err", err)
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, id := range to {
		if c := h.conns[id]; c != nil {
			select {
			case c.send <- buf:
			default: // client lent : on drop (le snapshot suivant rattrapera)
			}
		}
	}
}

func (h *Hub) deliver(c *conn, env protocol.Envelope) {
	buf, err := json.Marshal(env)
	if err != nil {
		return
	}
	select {
	case c.send <- buf:
	default:
	}
}

func (h *Hub) sendErr(c *conn, code, message string) {
	h.deliver(c, protocol.Envelope{Type: "error", Data: protocol.Error{Code: code, Message: message}})
}

func (h *Hub) roomCall(c *conn, s *session, f func(*room.Room) error) {
	h.mu.Lock()
	r := s.room
	h.mu.Unlock()
	if r == nil {
		h.sendErr(c, "no_room", "pas dans une salle")
		return
	}
	if err := f(r); err != nil {
		h.sendErr(c, "rejected", err.Error())
	}
}

// ---- Utilitaires ----

func newToken() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (h *Hub) newCode() string {
	for {
		b := make([]byte, codeLen)
		_, _ = rand.Read(b)
		code := make([]byte, codeLen)
		for i := range code {
			code[i] = codeAlphabet[int(b[i])%len(codeAlphabet)]
		}
		s := string(code)
		h.mu.Lock()
		_, taken := h.rooms[s]
		h.mu.Unlock()
		if !taken {
			return s
		}
	}
}
