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
	for {
		if view.YourSeat == view.Turn {
			break
		}
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

func decodeView(t *testing.T, env protocol.Envelope) *protocol.View {
	t.Helper()
	raw, _ := json.Marshal(env.Data)
	var v protocol.View
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return &v
}
