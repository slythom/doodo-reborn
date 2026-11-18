package hub

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/coder/websocket"

	"doodo/internal/protocol"
)

// client de test : connexion WS + envoi/réception d'enveloppes JSON.
type testClient struct {
	ws  *websocket.Conn
	in  chan protocol.Envelope
	ctx context.Context
}

func dial(t *testing.T, url string) *testClient {
	t.Helper()
	ws, _, err := websocket.Dial(context.Background(), url, nil)
	if err != nil {
		t.Fatal(err)
	}
	c := &testClient{ws: ws, in: make(chan protocol.Envelope, 64), ctx: context.Background()}
	go func() {
		for {
			_, data, err := ws.Read(c.ctx)
			if err != nil {
				return
			}
			var env protocol.Envelope
			if json.Unmarshal(data, &env) == nil {
				c.in <- env
			}
		}
	}()
	return c
}

func (c *testClient) send(t *testing.T, m any) {
	t.Helper()
	buf, _ := json.Marshal(m)
	if err := c.ws.Write(c.ctx, websocket.MessageText, buf); err != nil {
		t.Fatal(err)
	}
}

// recv retourne la prochaine enveloppe du type attendu (en ignorant les autres).
func (c *testClient) recv(t *testing.T, typ string, timeout time.Duration) protocol.Envelope {
	t.Helper()
	deadline := time.After(timeout)
	for {
		select {
		case env := <-c.in:
			if env.Type == typ {
				return env
			}
		case <-deadline:
			t.Fatalf("timeout en attendant %q", typ)
		}
	}
}

func hello(t *testing.T, c *testClient, name string) string {
	t.Helper()
	c.send(t, map[string]any{"type": "hello", "name": name})
	env := c.recv(t, "welcome", 3*time.Second)
	var w protocol.Welcome
	raw, _ := json.Marshal(env.Data)
	json.Unmarshal(raw, &w)
	if w.Token == "" {
		t.Fatal("pas de token dans welcome")
	}
	return w.Token
}

func TestEndToEndGame(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	alice := dial(t, wsURL)
	defer alice.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, alice, "alice")

	// Crée une salle privée + un bot, lance la partie.
	alice.send(t, map[string]any{"type": "create"})
	env := alice.recv(t, "room_state", 3*time.Second)
	view := decodeView(t, env)
	if view.Code == "" || len(view.Players) != 1 {
		t.Fatalf("salle mal créée: %+v", view)
	}

	alice.send(t, map[string]any{"type": "add_bot"})
	alice.recv(t, "room_state", 3*time.Second)

	alice.send(t, map[string]any{"type": "launch"})
	env = alice.recv(t, "room_state", 3*time.Second)
	view = decodeView(t, env)
	if view.State != "playing" || len(view.Players) != 2 {
		t.Fatalf("partie mal lancée: %+v", view)
	}

	// Attendre que le tour soit à alice (le bot joue tout seul s'il commence).
	deadline := time.Now().Add(5 * time.Second)
	for view.YourSeat != view.Turn {
		if time.Now().After(deadline) {
			t.Fatal("le tour n'est jamais arrivé à alice")
		}
		env = alice.recv(t, "room_state", 5*time.Second)
		view = decodeView(t, env)
	}

	// Alice enchérit (légale quelle que soit l'enchère debout) ; le bot doit
	// réagir (bid, dudo ou calza → nouvel état).
	q, v := 1, 3
	if view.HasBid {
		q, v = view.Bid.Quantity+1, view.Bid.Value
	}
	alice.send(t, map[string]any{"type": "action", "action": "bid", "quantity": q, "value": v})
	got := false
	deadline = time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) && !got {
		select {
		case env = <-alice.in:
			if env.Type == "events" {
				got = true
			}
		case <-time.After(8 * time.Second):
		}
	}
	if !got {
		t.Fatal("aucun événement de jeu reçu")
	}
}

func TestJoinByCode(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	alice := dial(t, wsURL)
	defer alice.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, alice, "alice")
	alice.send(t, map[string]any{"type": "create"})
	view := decodeView(t, alice.recv(t, "room_state", 3*time.Second))

	bob := dial(t, wsURL)
	defer bob.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, bob, "bob")
	bob.send(t, map[string]any{"type": "join", "code": view.Code})
	env := bob.recv(t, "room_state", 3*time.Second)
	v2 := decodeView(t, env)
	if len(v2.Players) != 2 {
		t.Fatalf("bob n'a pas rejoint: %+v", v2.Players)
	}
	// Alice doit aussi avoir reçu la mise à jour.
	env = alice.recv(t, "room_state", 3*time.Second)
	if got := len(decodeView(t, env).Players); got != 2 {
		t.Fatalf("alice n'a pas vu bob arriver: %d joueurs", got)
	}
}

func TestSetOptionsEndToEnd(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	alice := dial(t, wsURL)
	defer alice.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, alice, "alice")
	alice.send(t, map[string]any{"type": "create"})
	view := decodeView(t, alice.recv(t, "room_state", 3*time.Second))

	bob := dial(t, wsURL)
	defer bob.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, bob, "bob")
	bob.send(t, map[string]any{"type": "join", "code": view.Code})
	bob.recv(t, "room_state", 3*time.Second)
	alice.recv(t, "room_state", 3*time.Second) // arrivée de bob vue par alice

	opts := map[string]any{
		"game": map[string]any{
			"dice_per_player": 3, "paco_joker": true,
			"calza_enabled": true, "palifico_enabled": true,
		},
		"timer_seconds": 15, "max_players": 4,
		"bot_replacement": true, "spectators": true,
	}
	// Non-hôte : rejeté en erreur.
	bob.send(t, map[string]any{"type": "set_options", "options": opts})
	bob.recv(t, "error", 3*time.Second)

	// Hôte : accepté, le nouvel état est rediffusé.
	alice.send(t, map[string]any{"type": "set_options", "options": opts})
	env := alice.recv(t, "room_state", 3*time.Second)
	v2 := decodeView(t, env)
	if v2.Options.TimerSeconds != 15 || v2.Options.MaxPlayers != 4 ||
		v2.Options.Game.DicePerPlayer != 3 {
		t.Fatalf("options non propagées: %+v", v2.Options)
	}
	// Le décor n'est pas écrasé par un payload sans scene.
	if v2.Options.Scene != "salon" {
		t.Fatalf("scène écrasée: %q", v2.Options.Scene)
	}
}

func TestGodDiceEndToEnd(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	alice := dial(t, wsURL)
	defer alice.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, alice, "alice")
	alice.send(t, map[string]any{"type": "create"})
	view := decodeView(t, alice.recv(t, "room_state", 3*time.Second))

	bob := dial(t, wsURL)
	defer bob.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, bob, "bob")
	bob.send(t, map[string]any{"type": "join", "code": view.Code})
	bob.recv(t, "room_state", 3*time.Second)
	alice.recv(t, "room_state", 3*time.Second)

	// Active le mode dieu (salle privée → autorisé).
	alice.send(t, map[string]any{"type": "set_options", "options": map[string]any{
		"game": map[string]any{
			"dice_per_player": 3, "paco_joker": true,
			"calza_enabled": true, "palifico_enabled": true,
		},
		"timer_seconds": 0, "max_players": 4,
		"bot_replacement": true, "spectators": true, "god_mode": true,
	}})
	alice.recv(t, "room_state", 3*time.Second)

	alice.send(t, map[string]any{"type": "launch"})
	env := alice.recv(t, "room_state", 3*time.Second)
	view = decodeView(t, env)
	if view.State != "playing" || !view.God {
		t.Fatalf("lancement mode dieu: state=%q god=%v", view.State, view.God)
	}
	// Bob n'est pas dieu.
	bobView := decodeView(t, bob.recv(t, "room_state", 3*time.Second))
	if bobView.God {
		t.Fatal("bob ne devrait pas être marqué dieu")
	}
	// Bob tente d'imposer son tirage : rejeté.
	bob.send(t, map[string]any{"type": "god_dice", "dice": []int{1, 1, 1}})
	bob.recv(t, "error", 3*time.Second)

	// Alice impose son tirage : appliqué à sa propre vue.
	alice.send(t, map[string]any{"type": "god_dice", "dice": []int{6, 6, 6}})
	env = alice.recv(t, "room_state", 3*time.Second)
	view = decodeView(t, env)
	var mine []int
	for _, p := range view.Players {
		if p.Seat == view.YourSeat {
			mine = p.Dice
		}
	}
	if len(mine) != 3 || mine[0] != 6 || mine[2] != 6 {
		t.Fatalf("tirage imposé absent de la vue: %v", mine)
	}
	// En mode dieu, alice voit aussi les dés de bob.
	seen := 0
	for _, p := range view.Players {
		if p.Dice != nil {
			seen++
		}
	}
	if seen != 2 {
		t.Fatalf("mode dieu: alice devrait voir 2 mains, vu %d", seen)
	}
}

func TestListRooms(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	// Observateur qui interroge le lobby.
	obs := dial(t, wsURL)
	defer obs.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, obs, "obs")

	listRooms := func() protocol.RoomList {
		obs.send(t, map[string]any{"type": "list_rooms"})
		env := obs.recv(t, "room_list", 3*time.Second)
		raw, _ := json.Marshal(env.Data)
		var rl protocol.RoomList
		if err := json.Unmarshal(raw, &rl); err != nil {
			t.Fatal(err)
		}
		return rl
	}

	// Lobby vide.
	if got := len(listRooms().Rooms); got != 0 {
		t.Fatalf("lobby non vide: %d salles", got)
	}

	// Table publique → visible en « En attente ».
	alice := dial(t, wsURL)
	defer alice.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, alice, "alice")
	alice.send(t, map[string]any{"type": "create", "public": true})
	alice.recv(t, "room_state", 3*time.Second)
	rooms := listRooms().Rooms
	if len(rooms) != 1 || rooms[0].State != "lobby" || rooms[0].Players != 1 {
		t.Fatalf("table publique absente du lobby: %+v", rooms)
	}
	if rooms[0].Name != "Table de alice" {
		t.Fatalf("nom de table: %q", rooms[0].Name)
	}

	// Table privée → invisible.
	bob := dial(t, wsURL)
	defer bob.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, bob, "bob")
	bob.send(t, map[string]any{"type": "create"})
	bob.recv(t, "room_state", 3*time.Second)
	if got := len(listRooms().Rooms); got != 1 {
		t.Fatalf("table privée ne devrait pas apparaître: %d salles", got)
	}

	// En cours + spectateurs → visible en « En cours ».
	alice.send(t, map[string]any{"type": "add_bot"})
	alice.recv(t, "room_state", 3*time.Second)
	alice.send(t, map[string]any{"type": "launch"})
	alice.recv(t, "room_state", 3*time.Second)
	rooms = listRooms().Rooms
	if len(rooms) != 1 || rooms[0].State != "playing" {
		t.Fatalf("partie en cours absente: %+v", rooms)
	}

	// Partie publique SANS spectateurs → masquée une fois lancée.
	carol := dial(t, wsURL)
	defer carol.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, carol, "carol")
	carol.send(t, map[string]any{"type": "create", "public": true})
	carol.recv(t, "room_state", 3*time.Second)
	carol.send(t, map[string]any{"type": "set_options", "options": map[string]any{
		"game": map[string]any{
			"dice_per_player": 3, "paco_joker": true,
			"calza_enabled": true, "palifico_enabled": true,
		},
		"timer_seconds": 0, "max_players": 4,
		"bot_replacement": true, "spectators": false, "public": true,
	}})
	carol.recv(t, "room_state", 3*time.Second)
	carol.send(t, map[string]any{"type": "add_bot"})
	carol.recv(t, "room_state", 3*time.Second)
	carol.send(t, map[string]any{"type": "launch"})
	carol.recv(t, "room_state", 3*time.Second)
	rooms = listRooms().Rooms
	if len(rooms) != 1 || rooms[0].Name != "Table de alice" {
		t.Fatalf("partie sans spectateurs ne devrait pas apparaître: %+v", rooms)
	}
}

func decodeView(t *testing.T, env protocol.Envelope) *protocol.View {
	t.Helper()
	raw, _ := json.Marshal(env.Data)
	var v protocol.View
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return &v
}

// Collision de jetons (§5) : un hello avec le jeton d'une conn VIVANTE
// reçoit un jeton neuf au lieu de voler la session.
func TestTokenCollisionLiveOwner(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	alice := dial(t, wsURL)
	defer alice.ws.Close(websocket.StatusNormalClosure, "")
	tokA := hello(t, alice, "alice")

	// Bob arrive avec le MÊME jeton (autre device, session.cfg partagé).
	bob := dial(t, wsURL)
	defer bob.ws.Close(websocket.StatusNormalClosure, "")
	bob.send(t, map[string]any{"type": "hello", "name": "bob", "token": tokA})
	env := bob.recv(t, "welcome", 5*time.Second)
	var w protocol.Welcome
	raw, _ := json.Marshal(env.Data)
	json.Unmarshal(raw, &w)
	if w.Token == tokA {
		t.Fatal("conn vivante : le nouvel arrivant doit recevoir un jeton neuf")
	}

	// Alice garde la main : sa session n'est pas volée.
	alice.send(t, map[string]any{"type": "create"})
	if v := decodeView(t, alice.recv(t, "room_state", 3*time.Second)); v.Code == "" {
		t.Fatal("alice devrait pouvoir créer une salle")
	}
	// Bob est une identité distincte : sa propre salle aussi.
	bob.send(t, map[string]any{"type": "create"})
	if v := decodeView(t, bob.recv(t, "room_state", 3*time.Second)); v.Code == "" {
		t.Fatal("bob devrait pouvoir créer une salle")
	}
}

// Collision de jetons (§5) : un hello avec le jeton d'une conn ZOMBIE
// (socket morte non détectée) reprend la session — cas normal de la
// reconnexion après crash.
func TestTokenCollisionZombieTakeover(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	alice := dial(t, wsURL)
	tokA := hello(t, alice, "alice")
	alice.send(t, map[string]any{"type": "create"})
	code := decodeView(t, alice.recv(t, "room_state", 3*time.Second)).Code

	// Simule une conn zombie : socket morte, mais le serveur croit encore
	// la conn vivante (sa readPump n'a pas encore vu l'erreur).
	dead := dial(t, wsURL)
	dead.ws.CloseNow()
	zombie := &conn{ws: dead.ws, send: make(chan []byte, 1), done: make(chan struct{})}
	h.mu.Lock()
	oldConn := h.conns[tokA]
	h.conns[tokA] = zombie
	h.mu.Unlock()

	// Reconnexion avec le même jeton : le ping échoue → reprise normale.
	// Le room_state de resync est émis pendant Reconnected, AVANT le
	// welcome — on collecte les deux dans l'ordre d'arrivée.
	carol := dial(t, wsURL)
	defer carol.ws.Close(websocket.StatusNormalClosure, "")
	carol.send(t, map[string]any{"type": "hello", "name": "alice", "token": tokA})
	var w protocol.Welcome
	gotState := false
	deadline := time.After(5 * time.Second)
	for w.Token == "" || !gotState {
		select {
		case env := <-carol.in:
			switch env.Type {
			case "welcome":
				raw, _ := json.Marshal(env.Data)
				json.Unmarshal(raw, &w)
			case "room_state":
				if decodeView(t, env).Code == code {
					gotState = true
				}
			}
		case <-deadline:
			t.Fatalf("welcome=%+v room_state reçu=%v", w, gotState)
		}
	}
	if w.Token != tokA {
		t.Fatalf("zombie : le jeton devrait être repris tel quel, got %s", w.Token)
	}

	// Garde onClose : la mort tardive de la VRAIE conn de alice ne doit
	// pas effacer l'entrée conns[tokA] qui appartient désormais à carol.
	alice.ws.Close(websocket.StatusNormalClosure, "")
	time.Sleep(300 * time.Millisecond)
	h.mu.Lock()
	cur := h.conns[tokA]
	h.mu.Unlock()
	if cur == nil || cur == oldConn {
		t.Error("onClose a effacé l'entrée de la conn de relais")
	}
}

// Issue #5 : le client lit l'id du bot dans la vue et l'envoie à remove_bot.
func TestRemoveBotEndToEnd(t *testing.T) {
	h := New()
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	wsURL := "ws" + srv.URL[4:] + "/ws"

	c := dial(t, wsURL)
	defer c.ws.Close(websocket.StatusNormalClosure, "")
	hello(t, c, "host")

	c.send(t, map[string]any{"type": "create"})
	c.recv(t, "room_state", 3*time.Second)

	c.send(t, map[string]any{"type": "add_bot"})
	env := c.recv(t, "room_state", 3*time.Second)
	view := decodeView(t, env)

	botID := ""
	for _, p := range view.Players {
		if p.Bot {
			botID = p.ID
		}
	}
	if botID == "" {
		t.Fatalf("la vue n'expose pas l'id du bot: %+v", view.Players)
	}

	c.send(t, map[string]any{"type": "remove_bot", "target": botID})
	env = c.recv(t, "room_state", 3*time.Second)
	view = decodeView(t, env)
	if len(view.Players) != 1 || view.Players[0].Bot {
		t.Fatalf("bot toujours présent après remove_bot: %+v", view.Players)
	}
}
