package room

import (
	"math/rand"
	"sync"
	"testing"
	"time"

	"doodo/internal/game"
	"doodo/internal/protocol"
)

// fakeClock implémente TimerFunc pour les tests : les callbacks sont
// collectés et déclenchés manuellement via fire().
type fakeClock struct {
	mu      sync.Mutex
	pending []*fakeTimer
}

type fakeTimer struct {
	f       func()
	stopped bool
}

func (t *fakeTimer) Stop() bool {
	if t.stopped {
		return false
	}
	t.stopped = true
	return true
}

func (c *fakeClock) after(d time.Duration, f func()) interface{ Stop() bool } {
	c.mu.Lock()
	defer c.mu.Unlock()
	t := &fakeTimer{f: f}
	c.pending = append(c.pending, t)
	return t
}

// fire exécute les callbacks en attente (un callback peut en armer un
// nouveau, ex. bot après bot), plafonné à max exécutions : sans borne, les
// chaînes d'auto-enchères de joueurs AFK ne terminent jamais (personne ne
// dit Dudo — en production, la déconnexion tranche ce cas).
func (c *fakeClock) fire(max int) {
	for i := 0; i < max; i++ {
		c.mu.Lock()
		var next *fakeTimer
		for _, t := range c.pending {
			if !t.stopped && t.f != nil {
				next = t
				break
			}
		}
		c.mu.Unlock()
		if next == nil {
			return
		}
		f := next.f
		next.f = nil
		f()
	}
}

// collecteur de messages émis par la room.
type sink struct {
	mu   sync.Mutex
	msgs []sentMsg
}

type sentMsg struct {
	to  []string
	env protocol.Envelope
}

func (s *sink) emit(to []string, env protocol.Envelope) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.msgs = append(s.msgs, sentMsg{to, env})
}

func (s *sink) viewsFor(id string) []*protocol.View {
	s.mu.Lock()
	defer s.mu.Unlock()
	var views []*protocol.View
	for _, m := range s.msgs {
		if m.env.Type == "room_state" && len(m.to) == 1 && m.to[0] == id {
			views = append(views, m.env.Data.(*protocol.View))
		}
	}
	return views
}

func newRoom(t *testing.T) (*Room, *fakeClock, *sink) {
	t.Helper()
	clk := &fakeClock{}
	s := &sink{}
	opts := protocol.Options{
		Game:           game.Options{DicePerPlayer: 3, PacoJoker: true, CalzaEnabled: true, PalificoEnabled: true},
		TimerSeconds:   30,
		MaxPlayers:     6,
		BotReplacement: true,
		Spectators:     true,
	}
	r := New("TEST42", &Member{ID: "u1", Name: "alice"}, opts, rand.New(rand.NewSource(1)), s.emit, clk.after)
	return r, clk, s
}

func TestJoinAndLaunch(t *testing.T) {
	r, clk, _ := newRoom(t)
	if err := r.Join(&Member{ID: "u2", Name: "bob"}); err != nil {
		t.Fatal(err)
	}
	if err := r.Launch("u2"); err != ErrNotHost {
		t.Errorf("non-hôte lance: err=%v", err)
	}
	if err := r.Launch("u1"); err != nil {
		t.Fatal(err)
	}
	if r.State != "playing" {
		t.Fatalf("state=%s", r.State)
	}
	clk.fire(500) // déclenche les timers éventuels (bot)
}

func TestLaunchNeedsTwo(t *testing.T) {
	r, _, _ := newRoom(t)
	if err := r.Launch("u1"); err != ErrNotEnough {
		t.Errorf("err=%v, want ErrNotEnough", err)
	}
	// Un bot compte dans le minimum (§3.1).
	if _, err := r.AddBot("u1"); err != nil {
		t.Fatal(err)
	}
	if err := r.Launch("u1"); err != nil {
		t.Errorf("lancement 1 humain + 1 bot: err=%v", err)
	}
}

func TestFullRoom(t *testing.T) {
	r, _, _ := newRoom(t)
	r.Opts.MaxPlayers = 2
	r.Join(&Member{ID: "u2", Name: "bob"})
	if err := r.Join(&Member{ID: "u3", Name: "carol"}); err != ErrFull {
		t.Errorf("err=%v, want ErrFull", err)
	}
}

func TestKickBan(t *testing.T) {
	r, _, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	if err := r.Kick("u2", "u1"); err != ErrNotHost {
		t.Errorf("non-hôte expulse: err=%v", err)
	}
	if err := r.Kick("u1", "u2"); err != nil {
		t.Fatal(err)
	}
	if err := r.Join(&Member{ID: "u2", Name: "bob"}); err != ErrKicked {
		t.Errorf("rejoin après kick: err=%v, want ErrKicked", err)
	}
}

func TestHostTransfer(t *testing.T) {
	r, _, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Join(&Member{ID: "u3", Name: "carol"})
	r.Leave("u1")
	if r.Host != "u2" {
		t.Errorf("host=%q, want u2 (plus ancien humain)", r.Host)
	}
}

func TestSpectatorJoinDuringGame(t *testing.T) {
	r, clk, s := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	if err := r.Join(&Member{ID: "u3", Name: "spec"}); err != nil {
		t.Fatal(err)
	}
	views := s.viewsFor("u3")
	if len(views) == 0 {
		t.Fatal("le spectateur n'a pas reçu de snapshot")
	}
	last := views[len(views)-1]
	if last.YourSeat != -1 {
		t.Errorf("YourSeat=%d, want -1", last.YourSeat)
	}
	for _, pv := range last.Players {
		if pv.Dice != nil {
			t.Errorf("le spectateur ne doit voir aucun dé: %+v", pv)
		}
	}
	clk.fire(500)
}

func TestSpectatorLeaveDuringGame(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	r.Join(&Member{ID: "u3", Name: "spec"}) // arrive en partie → spectateur
	if len(r.spectators) != 1 {
		t.Fatalf("spectateurs=%d, want 1", len(r.spectators))
	}
	r.Leave("u3")
	if len(r.spectators) != 0 {
		t.Errorf("spectateurs=%d, want 0 après départ", len(r.spectators))
	}
	if len(r.players) != 2 {
		t.Errorf("players=%d, want 2", len(r.players))
	}
	clk.fire(500)
}

func TestEliminatedLeaveStaysInRoster(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	// Bob éliminé à la main puis quitte : il doit rester dans le roster
	// (déconnecté) pour que son nom survive dans la vue/le classement.
	seat := r.seatOfLocked("u2")
	r.game.Players[seat].Alive = false
	r.game.Players[seat].DiceCount = 0
	r.Leave("u2")
	if len(r.players) != 2 {
		t.Errorf("players=%d, want 2 (éliminé conservé)", len(r.players))
	}
	v := r.viewForLocked(r.memberLocked("u1"))
	found := false
	for _, pv := range v.Players {
		if pv.Name == "bob" && pv.DiceCount == 0 {
			found = true
		}
	}
	if !found {
		t.Error("l'éliminé parti doit rester visible (nom, 0 dé) dans la vue")
	}
	clk.fire(500)
}

func TestLeaveInFinishedState(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	r.State = "finished"
	if destroy := r.Leave("u2"); destroy {
		t.Error("il reste u1 : la room ne doit pas être détruite")
	}
	if len(r.players) != 1 {
		t.Errorf("players=%d, want 1", len(r.players))
	}
	clk.fire(500)
}

func TestRematchPlayersOnly(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	r.Join(&Member{ID: "u3", Name: "spec"}) // spectateur
	r.State = "finished"
	if err := r.Rematch("u3"); err != ErrPlayersOnly {
		t.Errorf("spectateur rematch: err=%v, want ErrPlayersOnly", err)
	}
	if err := r.Rematch("u1"); err != nil {
		t.Fatalf("joueur rematch: err=%v", err)
	}
	if r.State != "lobby" {
		t.Errorf("state=%s, want lobby", r.State)
	}
	clk.fire(500)
}

func TestDiceCountStaysDownAcrossRounds(t *testing.T) {
	r, clk, s := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	// Le joueur de tour surestime volontairement, l'autre doute :
	// l'enchérisseur perd un dé — et ne doit JAMAIS le regagner sans calza.
	turn := r.game.Turn
	bidder := r.seats[turn].ID
	caller := "u1"
	if bidder == "u1" {
		caller = "u2"
	}
	if err := r.Act(bidder, game.Action{Type: game.ActionBid, Bid: game.Bid{Quantity: 20, Value: 6}}); err != nil {
		t.Fatal(err)
	}
	if err := r.Act(caller, game.Action{Type: game.ActionDudo}); err != nil {
		t.Fatal(err)
	}
	views := s.viewsFor(bidder)
	if len(views) == 0 {
		t.Fatal("pas de snapshot reçu")
	}
	last := views[len(views)-1]
	for _, pv := range last.Players {
		if pv.Seat == turn {
			if pv.DiceCount != 2 {
				t.Errorf("dice_count=%d après perte, want 2", pv.DiceCount)
			}
			if len(pv.Dice) != 2 {
				t.Errorf("len(dice)=%d après relance, want 2", len(pv.Dice))
			}
		}
	}
	clk.fire(500)
}

func TestPlayerSeesOnlyOwnDice(t *testing.T) {
	r, clk, s := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	views := s.viewsFor("u1")
	last := views[len(views)-1]
	seen := 0
	for _, pv := range last.Players {
		if pv.Dice != nil {
			seen++
		}
	}
	if seen != 1 {
		t.Errorf("u1 devrait voir exactement 1 main (la sienne), vu %d", seen)
	}
	// Et c'est bien la sienne.
	for _, pv := range last.Players {
		if pv.Dice != nil && pv.Seat != last.YourSeat {
			t.Errorf("u1 voit les dés du siège %d (le sien: %d)", pv.Seat, last.YourSeat)
		}
	}
	clk.fire(500)
}


func TestTurnTimerAutoBid(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	// Premier joueur de tour : trouver son ID.
	g := r.game
	m := r.seats[g.Turn]
	if m.Bot {
		t.Skip("le premier joueur est un bot dans cette graine")
	}
	evs, err := g.AutoAction(g.Turn)
	if err != nil {
		t.Fatal(err)
	}
	_ = evs
	// Le timer a été armé au launch ; fire() déclenche l'auto-action si
	// le tour n'a pas changé entre-temps.
	clk.fire(500)
}

func TestDisconnectGraceBotReplacement(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	r.Disconnected("u2")
	m := r.memberLocked("u2")
	if m == nil {
		t.Fatal("u2 retiré de la partie")
	}
	clk.fire(500) // expiration du délai de grâce → remplacement bot
	if !m.ReplacedByBot {
		t.Error("u2 devrait être remplacé par un bot")
	}
	// Reconnexion : reprise de main.
	r.Reconnected(m)
	if m.ReplacedByBot {
		t.Error("u2 devrait reprendre la main")
	}
	if !m.Connected {
		t.Error("u2 devrait être connecté")
	}
	clk.fire(500)
}

func TestAbandonInGame(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Join(&Member{ID: "u3", Name: "carol"})
	r.Launch("u1")
	r.Leave("u2")
	seat := -1
	for i, m := range r.seats {
		if m.ID == "u2" {
			seat = i
		}
	}
	if seat >= 0 && r.game.Players[seat].Alive {
		t.Error("u2 devrait être éliminé après abandon")
	}
	clk.fire(500)
}

func TestActRejectsOutOfTurn(t *testing.T) {
	r, clk, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	turnID := r.seats[r.game.Turn].ID
	other := "u1"
	if turnID == "u1" {
		other = "u2"
	}
	err := r.Act(other, game.Action{Type: game.ActionBid, Bid: game.Bid{Quantity: 1, Value: 2}})
	if err != game.ErrNotYourTurn {
		t.Errorf("err=%v, want ErrNotYourTurn", err)
	}
	clk.fire(500)
}
