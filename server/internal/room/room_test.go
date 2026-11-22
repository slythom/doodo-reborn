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

func TestSetScene(t *testing.T) {
	r, _, s := newRoom(t)
	// L'option par défaut est propagée dans le snapshot.
	if got := r.Opts.Scene; got != "salon" {
		t.Fatalf("scene par défaut=%q, want salon", got)
	}
	if err := r.Join(&Member{ID: "u2", Name: "bob"}); err != nil {
		t.Fatal(err)
	}
	if err := r.SetScene("u2", "plage"); err != ErrNotHost {
		t.Errorf("non-hôte change la scène: err=%v", err)
	}
	if err := r.SetScene("u1", "cimetiere"); err != nil {
		t.Fatal(err)
	}
	if got := r.Opts.Scene; got != "cimetiere" {
		t.Errorf("scene=%q, want cimetiere", got)
	}
	if err := r.SetScene("u1", "plage"); err != nil {
		t.Fatal(err)
	}
	// Id inconnu → fallback salon (vieux client / id retiré).
	if got := r.Opts.Scene; got != "salon" {
		t.Errorf("scene inconnue normalisée=%q, want salon", got)
	}
	if err := r.Launch("u1"); err != nil {
		t.Fatal(err)
	}
	if err := r.SetScene("u1", "salon"); err != ErrAlreadyStarted {
		t.Errorf("scène après lancement: err=%v, want ErrAlreadyStarted", err)
	}
	views := s.viewsFor("u1")
	if len(views) == 0 || views[len(views)-1].Options.Scene != "salon" {
		t.Errorf("le snapshot ne propage pas options.scene")
	}
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

func TestSetOptions(t *testing.T) {
	r, _, s := newRoom(t)
	if err := r.Join(&Member{ID: "u2", Name: "bob"}); err != nil {
		t.Fatal(err)
	}
	// L'hôte modifie tout : dés, timer, max joueurs, toggles.
	o := r.Opts
	o.Game.DicePerPlayer = 4
	o.Game.PacoJoker = false
	o.TimerSeconds = 60
	o.MaxPlayers = 4
	o.Spectators = false
	if err := r.SetOptions("u2", &o); err != ErrNotHost {
		t.Errorf("non-hôte modifie les options: err=%v", err)
	}
	if err := r.SetOptions("u1", &o); err != nil {
		t.Fatal(err)
	}
	if r.Opts.Game.DicePerPlayer != 4 || r.Opts.Game.PacoJoker ||
		r.Opts.TimerSeconds != 60 || r.Opts.MaxPlayers != 4 || r.Opts.Spectators {
		t.Errorf("options non appliquées: %+v", r.Opts)
	}
	// Le snapshot propagé porte les nouvelles options.
	views := s.viewsFor("u2")
	if len(views) == 0 || views[len(views)-1].Options.TimerSeconds != 60 {
		t.Errorf("le snapshot ne propage pas les options")
	}
	// Figées au lancement.
	if err := r.Launch("u1"); err != nil {
		t.Fatal(err)
	}
	if err := r.SetOptions("u1", &o); err != ErrAlreadyStarted {
		t.Errorf("options après lancement: err=%v, want ErrAlreadyStarted", err)
	}
}

func TestSetOptionsValidation(t *testing.T) {
	cases := []struct {
		name string
		mut  func(o *protocol.Options)
	}{
		{"nil → rejet", nil},
		{"dés hors [3,5]", func(o *protocol.Options) { o.Game.DicePerPlayer = 7 }},
		{"timer hors liste", func(o *protocol.Options) { o.TimerSeconds = 45 }},
		{"max hors [2,6]", func(o *protocol.Options) { o.MaxPlayers = 9 }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r, _, _ := newRoom(t)
			if tc.mut == nil {
				if err := r.SetOptions("u1", nil); err != ErrBadOptions {
					t.Errorf("err=%v, want ErrBadOptions", err)
				}
				return
			}
			o := r.Opts
			tc.mut(&o)
			if err := r.SetOptions("u1", &o); err == nil {
				t.Errorf("options invalides acceptées: %+v", o)
			}
		})
	}
	// Max joueurs < joueurs présents → rejet (mais ≥ présents passe).
	r, _, _ := newRoom(t)
	for _, id := range []string{"u2", "u3"} {
		if err := r.Join(&Member{ID: id, Name: id}); err != nil {
			t.Fatal(err)
		}
	}
	o := r.Opts
	o.MaxPlayers = 2 // 3 joueurs présents
	if err := r.SetOptions("u1", &o); err != ErrTooManyPresent {
		t.Errorf("max < présents: err=%v, want ErrTooManyPresent", err)
	}
	o.MaxPlayers = 3
	if err := r.SetOptions("u1", &o); err != nil {
		t.Errorf("max = présents: err=%v", err)
	}
}

func TestSetOptionsPreservesScene(t *testing.T) {
	r, _, _ := newRoom(t)
	if err := r.SetScene("u1", "cimetiere"); err != nil {
		t.Fatal(err)
	}
	o := r.Opts
	o.Scene = "" // un client qui ne connaît pas les décors ne doit rien casser
	o.Game.DicePerPlayer = 4
	if err := r.SetOptions("u1", &o); err != nil {
		t.Fatal(err)
	}
	if r.Opts.Scene != "cimetiere" {
		t.Errorf("scene=%q, want cimetiere (préservée)", r.Opts.Scene)
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

func TestEmoteWhitelist(t *testing.T) {
	r, _, s := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	for _, kind := range []string{"tomato", "poop", "egg"} {
		r.Emote("u1", "1", kind)
	}
	r.Emote("u1", "1", "rock")     // hors whitelist : ignoré
	r.Emote("nobody", "1", "poop") // inconnu : ignoré
	var got []string
	for _, m := range s.msgs {
		if m.env.Type != "notice" {
			continue
		}
		if n, ok := m.env.Data.(protocol.Notice); ok && n.Kind == "emote" {
			got = append(got, n.Text)
		}
	}
	want := []string{"tomato", "poop", "egg"}
	if len(got) != len(want) {
		t.Fatalf("emotes relayées=%v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("emote[%d]=%q, want %q", i, got[i], want[i])
		}
	}
}

// Chat : texte libre en salle d'attente, ids prédéfinis uniquement en
// partie — le canal reste unique (joueurs + spectateurs, §4.3).
func TestChatFreeVsPredefined(t *testing.T) {
	r, _, s := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	chatTexts := func() []string {
		var out []string
		for _, m := range s.msgs {
			if n, ok := m.env.Data.(protocol.Notice); ok && m.env.Type == "notice" && n.Kind == "chat" {
				out = append(out, n.Text)
			}
		}
		return out
	}
	r.Chat("u1", "bonjour les amis")
	r.Chat("u2", "hein") // id prédéfini accepté aussi en lobby
	if got := chatTexts(); len(got) != 2 || got[0] != "bonjour les amis" || got[1] != "hein" {
		t.Fatalf("chat lobby=%v", got)
	}
	s.msgs = nil
	r.Launch("u1")
	s.msgs = nil
	r.Chat("u1", "texte libre interdit en jeu")
	r.Chat("u1", "hein")
	r.Chat("u2", "redit")
	if got := chatTexts(); len(got) != 2 || got[0] != "hein" || got[1] != "redit" {
		t.Fatalf("chat en jeu=%v, want [hein redit]", got)
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

func TestGodDice(t *testing.T) {
	clk := &fakeClock{}
	s := &sink{}
	opts := protocol.Options{
		Game:           game.Options{DicePerPlayer: 3, PacoJoker: true, CalzaEnabled: true, PalificoEnabled: true},
		TimerSeconds:   30,
		MaxPlayers:     6,
		BotReplacement: true,
		Spectators:     true,
		GodMode:        true,
	}
	r := New("TEST42", &Member{ID: "u1", Name: "alice"}, opts, rand.New(rand.NewSource(1)), s.emit, clk.after)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")

	// Non-créateur : rejeté même si le mode dieu est actif.
	if err := r.GodDice("u2", []int{6, 6, 6}); err != ErrNotHost {
		t.Fatalf("non-créateur: attendu ErrNotHost, reçu %v", err)
	}
	// Mauvaise taille / face invalide.
	if err := r.GodDice("u1", []int{6, 6}); err != game.ErrBadDice {
		t.Fatalf("count: attendu ErrBadDice, reçu %v", err)
	}
	if err := r.GodDice("u1", []int{7, 6, 6}); err != game.ErrBadDice {
		t.Fatalf("face: attendu ErrBadDice, reçu %v", err)
	}
	// Le tirage imposé est appliqué au siège du créateur.
	if err := r.GodDice("u1", []int{6, 6, 6}); err != nil {
		t.Fatalf("god_dice: %v", err)
	}
	seat := r.seatOfLocked("u1")
	got := r.game.Players[seat].Dice
	if len(got) != 3 || got[0] != 6 || got[2] != 6 {
		t.Fatalf("tirage imposé non appliqué: %v", got)
	}
	// Le flag god n'apparaît que dans la vue du créateur.
	last := s.viewsFor("u1")
	if !last[len(last)-1].God {
		t.Error("la vue du créateur devrait porter god=true")
	}
	if !last[len(last)-1].Creator || !last[len(last)-1].Options.GodMode {
		t.Error("le créateur devrait voir creator=true et god_mode actif")
	}
	lastBob := s.viewsFor("u2")
	if lastBob[len(lastBob)-1].God || lastBob[len(lastBob)-1].Creator {
		t.Error("la vue de bob ne devrait porter ni god ni creator")
	}
	// Le statut du mode dieu est masqué aux non-créateurs (§4.5).
	if lastBob[len(lastBob)-1].Options.GodMode {
		t.Error("bob ne devrait pas voir god_mode actif dans ses options")
	}
	// Trop tard : une enchère est posée — le tirage est figé pour la manche.
	bidder, caller := "u1", "u2"
	if r.seats[r.game.Turn].ID == "u2" {
		bidder, caller = "u2", "u1"
	}
	if err := r.Act(bidder, game.Action{Type: game.ActionBid, Bid: game.Bid{Quantity: 1, Value: 4}}); err != nil {
		t.Fatalf("bid: %v", err)
	}
	if err := r.GodDice("u1", []int{6, 6, 6}); err != ErrTooLate {
		t.Fatalf("après enchère: attendu ErrTooLate, reçu %v", err)
	}
	// Manche suivante (démarrée en synchrone par le dudo) : la fenêtre rouvre.
	if err := r.Act(caller, game.Action{Type: game.ActionDudo}); err != nil {
		t.Fatalf("dudo: %v", err)
	}
	if r.game.Players[seat].Alive {
		want := r.game.Players[seat].DiceCount
		dice := make([]int, want)
		for i := range dice {
			dice[i] = 6
		}
		if err := r.GodDice("u1", dice); err != nil {
			t.Fatalf("manche suivante: %v", err)
		}
	}
}

// Mode dieu dormant : god_mode + public est stocké mais inerte tant que
// la table est publique (§4.5) — il reprend au retour en privé.
func TestGodModeDormantWhenPublic(t *testing.T) {
	clk := &fakeClock{}
	s := &sink{}
	opts := protocol.Options{
		Game:           game.Options{DicePerPlayer: 3, PacoJoker: true, CalzaEnabled: true, PalificoEnabled: true},
		TimerSeconds:   30,
		MaxPlayers:     6,
		BotReplacement: true,
		Spectators:     true,
		GodMode:        true,
	}
	r := New("TEST42", &Member{ID: "u1", Name: "alice"}, opts, rand.New(rand.NewSource(1)), s.emit, clk.after)
	r.Join(&Member{ID: "u2", Name: "bob"})

	o := r.Opts
	o.Public = true
	if err := r.SetOptions("u1", &o); err != nil {
		t.Fatalf("god_mode + public devrait être accepté: %v", err)
	}
	if !r.Opts.GodMode || !r.Opts.Public {
		t.Fatal("le couple god_mode + public devrait être stocké")
	}
	// Vue du créateur : dormant (god=false) mais la valeur stockée reste
	// visible pour lui — le switch reste « on » verrouillé.
	views := s.viewsFor("u1")
	last := views[len(views)-1]
	if last.God {
		t.Error("le mode dieu devrait être dormant sur une table publique")
	}
	if !last.Options.GodMode {
		t.Error("god_mode devrait rester mémorisé dans la vue du créateur")
	}
	// En partie publique : GodDice est rejeté (mode dormant).
	r.Launch("u1")
	if err := r.GodDice("u1", []int{6, 6, 6}); err != ErrNotHost {
		t.Fatalf("god_dice sur table publique: attendu ErrNotHost, reçu %v", err)
	}
}

func TestGodDiceWithoutGodMode(t *testing.T) {
	r, _, _ := newRoom(t)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	if err := r.GodDice("u1", []int{6, 6, 6}); err != ErrNotHost {
		t.Fatalf("sans mode dieu: attendu ErrNotHost, reçu %v", err)
	}
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

func TestDePublicView(t *testing.T) {
	clk := &fakeClock{}
	s := &sink{}
	opts := protocol.Options{
		Game: game.Options{DicePerPlayer: 3, PacoJoker: true, CalzaEnabled: true,
			Rules: []string{"de_public"}},
		MaxPlayers: 6, TimerSeconds: 30, BotReplacement: true, Spectators: true,
	}
	r := New("TEST43", &Member{ID: "u1", Name: "alice"}, opts, rand.New(rand.NewSource(1)), s.emit, clk.after)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Launch("u1")
	v := r.viewForLocked(r.memberLocked("u1"))
	for _, pv := range v.Players {
		if pv.DiceCount > 0 && len(pv.PubDice) != 1 {
			t.Errorf("joueur %d : %d dés publics, want 1", pv.Seat, len(pv.PubDice))
		}
	}
	// Sans la règle : pas de dé public.
	r2, clk2, _ := newRoom(t)
	r2.Join(&Member{ID: "u2", Name: "bob"})
	r2.Launch("u1")
	v2 := r2.viewForLocked(r2.memberLocked("u1"))
	for _, pv := range v2.Players {
		if len(pv.PubDice) != 0 {
			t.Errorf("sans dé public : PubDice devrait être vide, got %v", pv.PubDice)
		}
	}
	clk.fire(500)
	clk2.fire(500)
}

func TestCalzoneStealThroughRoom(t *testing.T) {
	clk := &fakeClock{}
	s := &sink{}
	opts := protocol.Options{
		Game: game.Options{DicePerPlayer: 3, PacoJoker: true, CalzaEnabled: true,
			Rules: []string{"calzone"}},
		MaxPlayers: 6, TimerSeconds: 30, BotReplacement: true, Spectators: true,
	}
	r := New("TEST44", &Member{ID: "u1", Name: "alice"}, opts, rand.New(rand.NewSource(1)), s.emit, clk.after)
	r.Join(&Member{ID: "u2", Name: "bob"})
	r.Join(&Member{ID: "u3", Name: "carol"})
	r.Launch("u1")

	// Forcer une enchère exacte : 2 quatre, tous chez le siège 0.
	r.game.Players[0].Dice = []int{4, 4, 6}
	r.game.Players[1].Dice = []int{2, 3, 5}
	r.game.Players[2].Dice = []int{2, 3, 5}
	r.game.Players[1].DiceCount = 2 // calzeur en dessous du max → vol possible
	turn := r.game.Turn
	bidder := r.seats[turn].ID
	if err := r.Act(bidder, game.Action{Type: game.ActionBid, Bid: game.Bid{Quantity: 2, Value: 4}}); err != nil {
		t.Fatal(err)
	}
	// Le joueur suivant calza : décompte exact → vol en attente.
	next := r.game.Turn
	calzer := r.seats[next].ID
	r.game.Players[next].DiceCount = 2 // peut voler (en dessous du max 3)
	if err := r.Act(calzer, game.Action{Type: game.ActionCalza}); err != nil {
		t.Fatal(err)
	}
	if r.game.PendingSteal != next {
		t.Fatalf("PendingSteal=%d, want %d", r.game.PendingSteal, next)
	}
	// La vue expose le vol en attente.
	v := r.viewForLocked(r.memberLocked(calzer))
	if v.StealPending != next {
		t.Errorf("StealPending=%d dans la vue, want %d", v.StealPending, next)
	}
	// Le calzeur vole au joueur 0 via l'action steal.
	victim := 0
	if victim == next {
		victim = 2
	}
	before := r.game.Players[victim].DiceCount
	if err := r.Act(calzer, game.Action{Type: game.ActionSteal, Target: victim}); err != nil {
		t.Fatal(err)
	}
	if r.game.PendingSteal != -1 {
		t.Error("le vol devrait être résolu")
	}
	if r.game.Players[victim].DiceCount != before-1 {
		t.Errorf("victime : %d dés, want %d", r.game.Players[victim].DiceCount, before-1)
	}
	clk.fire(500)
}
