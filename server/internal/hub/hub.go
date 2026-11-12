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
	rooms    map[string]*room.Room       // code -> room
	sessions map[string]*session         // token -> session
	conns    map[string]*conn            // token -> conn
	queue    []*session                  // file matchmaking
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

func (h *Hub) readPump(ctx context.Context, c *conn) {
	defer func() {
		c.ws.Close(websocket.StatusNormalClosure, "bye")
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
	default:
		h.sendErr(c, "bad_action", "action inconnue: "+m.Action)
		return
	}
	h.roomCall(c, s, func(r *room.Room) error { return r.Act(s.token, a) })
}

// ---- Sessions / rooms ----

func (h *Hub) hello(c *conn, m protocol.ClientMsg) *session {
	token := m.Token
	if token == "" {
		token = newToken()
	}
	name := m.Name
	if name == "" {
		name = "invité"
	}
	h.mu.Lock()
	s := h.sessions[token]
	if s == nil {
		s = &session{token: token}
		h.sessions[token] = s
	}
	s.name = name
	h.conns[token] = c
	h.mu.Unlock()

	// Reconnexion : si le membre existe encore dans une room, on le réintègre.
	if s.room != nil && s.member != nil {
		s.room.Reconnected(s.member)
	}
	h.deliver(c, protocol.Envelope{Type: "welcome", Data: protocol.Welcome{Token: token, Name: name}})
	slog.Info("hello", "token", token[:8], "name", name, "rejoin", s.room != nil)
	return s
}

func (h *Hub) createRoom(c *conn, s *session, m protocol.ClientMsg) {
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
	// Mode dieu : salles privées uniquement (§4.5).
	if opts.Public {
		opts.GodMode = false
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
func (h *Hub) onClose(c *conn, s *session) {
	if s == nil {
		return
	}
	h.mu.Lock()
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

