package game

import (
	"math/rand"
	"testing"
)

// newTestGame crée une partie 3 joueurs, 3 dés chacun, toutes options actives.
func newTestGame(t *testing.T) *Game {
	t.Helper()
	opts := Options{DicePerPlayer: 3, PacoJoker: true, CalzaEnabled: true, PalificoEnabled: true}
	g, err := New(opts, []string{"a", "b", "c"}, rand.New(rand.NewSource(1)))
	if err != nil {
		t.Fatal(err)
	}
	return g
}

// setDice fixe manuellement les dés de la manche courante (après New/startRound).
func setDice(g *Game, dice ...[]int) {
	for i, d := range dice {
		g.Players[i].Dice = append([]int(nil), d...)
	}
}

func bidAt(g *Game, q, v int) {
	g.Current = Bid{Quantity: q, Value: v}
	g.HasBid = true
}

func TestLegalBid(t *testing.T) {
	cases := []struct {
		name          string
		current       Bid // {0,0} = aucune enchère
		palificoFixed int  // valeur figée en palifico, 0 = pas de palifico
		bid           Bid
		want          bool
	}{
		// Première enchère : tout est légal dans les bornes.
		{"first min", Bid{}, 0, Bid{1, Paco}, true},
		{"first max", Bid{}, 0, Bid{30, 6}, true},
		{"first qty 0", Bid{}, 0, Bid{0, 3}, false},
		{"first value 0", Bid{}, 0, Bid{2, 0}, false},
		{"first value 7", Bid{}, 0, Bid{2, 7}, false},

		// Après (3,4) — règle §1.2 standard.
		{"qty+1 any value", Bid{3, 4}, 0, Bid{4, 2}, true},
		{"qty+2 lower value", Bid{3, 4}, 0, Bid{5, 1}, true}, // 5 pacos > 3 : légal par X'>X
		{"same qty higher v", Bid{3, 4}, 0, Bid{3, 5}, true},
		{"same qty same v", Bid{3, 4}, 0, Bid{3, 4}, false},
		{"same qty lower v", Bid{3, 4}, 0, Bid{3, 3}, false},
		{"lower qty", Bid{3, 4}, 0, Bid{2, 6}, false},

		// Transition vers les pacos : X' >= ceil(X/2).
		{"to paco ceil", Bid{4, 6}, 0, Bid{2, Paco}, true},
		{"to paco ceil odd", Bid{5, 3}, 0, Bid{3, Paco}, true},
		{"to paco under ceil", Bid{4, 6}, 0, Bid{1, Paco}, false},
		{"to paco qty higher", Bid{4, 6}, 0, Bid{4, Paco}, true},

		// Transition depuis les pacos : X' >= 2X+1.
		{"leave paco min", Bid{2, Paco}, 0, Bid{5, 3}, true},
		{"leave paco over", Bid{2, Paco}, 0, Bid{7, 6}, true},
		{"leave paco under", Bid{2, Paco}, 0, Bid{4, 6}, false},
		{"paco to paco qty+", Bid{2, Paco}, 0, Bid{3, Paco}, true},
		{"paco same", Bid{2, Paco}, 0, Bid{2, Paco}, false},

		// Palifico : valeur figée, seule la quantité monte (§1.3).
		{"palifico qty+", Bid{2, 5}, 5, Bid{3, 5}, true},
		{"palifico change v", Bid{2, 5}, 5, Bid{3, 4}, false},
		{"palifico same", Bid{2, 5}, 5, Bid{2, 6}, false},
		{"palifico paco qty+", Bid{2, Paco}, 1, Bid{3, Paco}, true}, // paco enchérissable si c'est la valeur figée
		{"palifico paco to normal", Bid{2, 5}, 5, Bid{3, Paco}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			g := newTestGame(t)
			if c.current.Quantity > 0 {
				bidAt(g, c.current.Quantity, c.current.Value)
			}
			g.Palifico = c.palificoFixed != 0
			g.fixedV = c.palificoFixed
			if got := g.LegalBid(c.bid); got != c.want {
				t.Errorf("LegalBid(%v) après %v = %v, want %v", c.bid, c.current, got, c.want)
			}
		})
	}
}

func TestMinBid(t *testing.T) {
	g := newTestGame(t)
	if got := g.MinBid(); got != (Bid{1, Paco}) {
		t.Errorf("MinBid sans enchère = %v", got)
	}
	bidAt(g, 3, 4)
	if got := g.MinBid(); got != (Bid{4, 4}) {
		t.Errorf("MinBid après (3,4) = %v, want (4,4)", got)
	}
	bidAt(g, 2, Paco)
	if got := g.MinBid(); got != (Bid{5, 2}) {
		t.Errorf("MinBid après (2,paco) = %v, want (5,2)", got)
	}
	g.Palifico, g.fixedV = true, 4
	bidAt(g, 6, 4)
	if got := g.MinBid(); got != (Bid{7, 4}) {
		t.Errorf("MinBid palifico = %v, want (7,4)", got)
	}
}

func TestTurnAndBid(t *testing.T) {
	g := newTestGame(t)
	g.Turn = 0
	if _, err := g.Apply(1, Action{Type: ActionBid, Bid: Bid{1, 2}}); err != ErrNotYourTurn {
		t.Errorf("hors tour : err = %v", err)
	}
	evs, err := g.Apply(0, Action{Type: ActionBid, Bid: Bid{1, 2}})
	if err != nil {
		t.Fatal(err)
	}
	if evs[0].Type != EvBid || g.Turn != 1 || !g.HasBid {
		t.Errorf("état après enchère incorrect: %v turn=%d", evs, g.Turn)
	}
}

func TestDudoBidderLoses(t *testing.T) {
	g := newTestGame(t)
	setDice(g, []int{2, 3, 4}, []int{5, 5, 2}, []int{3, 3, 6})
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{9, 6}}) // seul 1 dé de valeur 6 existe
	evs, err := g.Apply(1, Action{Type: ActionDudo})
	if err != nil {
		t.Fatal(err)
	}
	if evs[0].Type != EvReveal || evs[0].Count != 1 {
		t.Fatalf("reveal incorrect: %+v", evs[0])
	}
	if g.Players[0].DiceCount != 2 {
		t.Errorf("enchérisseur devrait perdre un dé, DiceCount=%d", g.Players[0].DiceCount)
	}
	if g.Turn != 0 || g.Round != 2 {
		t.Errorf("le perdant doit entamer la manche 2: turn=%d round=%d", g.Turn, g.Round)
	}
}

func TestDudoChallengerLoses(t *testing.T) {
	g := newTestGame(t)
	setDice(g, []int{4, 4, 1}, []int{4, 2, 3}, []int{1, 4, 6})
	g.Turn = 0
	// 4 dés de valeur 4 + 2 pacos jokers = 6 dés « 4 » sur la table
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{6, 4}})
	evs, _ := g.Apply(1, Action{Type: ActionDudo})
	if evs[0].Count != 6 {
		t.Fatalf("comptage avec pacos: got %d, want 6", evs[0].Count)
	}
	if g.Players[1].DiceCount != 2 {
		t.Errorf("le douteur devrait perdre un dé, DiceCount=%d", g.Players[1].DiceCount)
	}
	if g.Turn != 1 {
		t.Errorf("le perdant (douteur) doit entamer, turn=%d", g.Turn)
	}
}

func TestCountNoJokerWhenOff(t *testing.T) {
	g := newTestGame(t)
	g.Opts.PacoJoker = false
	setDice(g, []int{4, 4, 1}, []int{4, 1, 3}, []int{1, 4, 6})
	if got := g.count(4); got != 4 {
		t.Errorf("sans paco joker: count(4)=%d, want 4", got)
	}
	if got := g.count(1); got != 3 {
		t.Errorf("count(1)=%d, want 3", got)
	}
}

func TestCalzaSuccess(t *testing.T) {
	g := newTestGame(t)
	g.Players[1].DiceCount = 2 // le calzeur a perdu un dé avant : il peut en regagner
	setDice(g, []int{4, 4, 1}, []int{4, 4}, []int{1, 4, 6})
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{7, 4}}) // 5 quatre + 2 pacos = 7
	evs, _ := g.Apply(1, Action{Type: ActionCalza})
	var gained bool
	for _, e := range evs {
		if e.Type == EvDieGained && e.Player == 1 {
			gained = true
		}
	}
	if !gained || g.Players[1].DiceCount != 3 {
		t.Errorf("calza réussi doit regagner un dé: DiceCount=%d evs=%v", g.Players[1].DiceCount, evs)
	}
	if g.Turn != 1 {
		t.Errorf("le calzeur entame la manche suivante, turn=%d", g.Turn)
	}
}

func TestCalzaSuccessAtMax(t *testing.T) {
	// §1.4 : calza réussi au max de dés = simple validation, personne ne perd.
	g := newTestGame(t)
	setDice(g, []int{4, 4, 4}, []int{4, 4, 4}, []int{4, 4, 4})
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{9, 4}})
	evs, _ := g.Apply(1, Action{Type: ActionCalza})
	for _, e := range evs {
		if e.Type == EvDieLost || e.Type == EvDieGained {
			t.Fatalf("aucun dé ne devrait changer de mains: %v", e)
		}
	}
	if g.Turn != 1 {
		t.Errorf("le calzeur entame, turn=%d", g.Turn)
	}
}

func TestCalzaFail(t *testing.T) {
	g := newTestGame(t)
	setDice(g, []int{2, 2, 2}, []int{3, 3, 3}, []int{6, 6, 6})
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{3, 4}}) // réalité : 0 dé de valeur 4
	g.Apply(1, Action{Type: ActionCalza})
	if g.Players[1].DiceCount != 2 {
		t.Errorf("calza raté : le calzeur perd un dé, DiceCount=%d", g.Players[1].DiceCount)
	}
	if g.Turn != 1 {
		t.Errorf("le calzeur (perdant) entame, turn=%d", g.Turn)
	}
}

func TestCalzaDisabled(t *testing.T) {
	g := newTestGame(t)
	g.Opts.CalzaEnabled = false
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{1, 2}})
	if _, err := g.Apply(1, Action{Type: ActionCalza}); err != ErrCalzaDisabled {
		t.Errorf("err = %v, want ErrCalzaDisabled", err)
	}
}

func TestDudoWithoutBid(t *testing.T) {
	g := newTestGame(t)
	g.Turn = 0
	if _, err := g.Apply(0, Action{Type: ActionDudo}); err != ErrNoBid {
		t.Errorf("err = %v, want ErrNoBid", err)
	}
}

func TestEliminationNextStarter(t *testing.T) {
	g := newTestGame(t)
	g.Players[0].DiceCount = 1
	setDice(g, []int{6}, []int{2, 2, 2}, []int{3, 3, 3})
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{8, 6}})
	g.Apply(1, Action{Type: ActionDudo})
	if g.Players[0].Alive {
		t.Fatal("p0 devrait être éliminé")
	}
	// Perdant éliminé → le joueur suivant dans le sens horaire entame (p1).
	if g.Turn != 1 {
		t.Errorf("turn=%d, want 1 (suivant horaire)", g.Turn)
	}
	if len(g.elimOrder) != 1 || g.elimOrder[0] != 0 {
		t.Errorf("elimOrder=%v", g.elimOrder)
	}
}

func TestAbandon(t *testing.T) {
	g := newTestGame(t)
	setDice(g, []int{6, 6, 6}, []int{4, 4, 4}, []int{4, 4, 4})
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{9, 4}}) // enchère de p0 debout
	// p1 abandonne : ses 3 dés de valeur 4 sont retirés du comptage.
	evs := g.Abandon(1)
	if evs[0].Type != EvEliminated || evs[0].Player != 1 {
		t.Fatalf("evs=%v", evs)
	}
	if got := g.count(4); got != 3 {
		t.Errorf("dés de p1 retirés du comptage: count(4)=%d, want 3", got)
	}
	// Tour passe au suivant (p2) ; l'enchère de p0 reste debout.
	if g.Turn != 2 {
		t.Errorf("turn=%d, want 2", g.Turn)
	}
	// p2 dudo : seulement 3 dés de 4 -> l'enchérisseur p0 perd un dé.
	g.Apply(2, Action{Type: ActionDudo})
	if g.Players[0].DiceCount != 2 {
		t.Errorf("enchère debout conservée: p0 DiceCount=%d, want 2", g.Players[0].DiceCount)
	}
}

func TestAbandonEndsGame(t *testing.T) {
	g := newTestGame(t)
	g.Players[1].Alive = false
	g.elimOrder = []int{1}
	g.Turn = 0
	evs := g.Abandon(0)
	if !g.Over || g.Winner != 2 {
		t.Errorf("partie devrait être finie, winner=%d over=%v", g.Winner, g.Over)
	}
	var over *Event
	for i := range evs {
		if evs[i].Type == EvGameOver {
			over = &evs[i]
		}
	}
	if over == nil || len(over.Ranking) != 3 || over.Ranking[0] != 2 || over.Ranking[1] != 0 {
		t.Errorf("ranking=%v", over)
	}
}

func TestPalificoTriggered(t *testing.T) {
	g := newTestGame(t)
	g.Players[0].DiceCount = 2
	setDice(g, []int{6, 6}, []int{1, 1, 1}, []int{4, 4, 4})
	g.Turn = 1
	g.Apply(1, Action{Type: ActionBid, Bid: Bid{4, 6}}) // surestimé
	evs, _ := g.Apply(2, Action{Type: ActionDudo})     // p1 perd → 2 dés restants? non: p1 a 3 dés → perd → 2. pas palifico
	// p1 passe à 2 dés : pas de palifico.
	if g.Palifico {
		t.Error("palifico ne devrait pas être armée")
	}
	// Forcer p0 à 1 dé : p0 perd un dé.
	g.Players[0].DiceCount = 2
	setDice(g, []int{6, 6}, g.Players[1].Dice, g.Players[2].Dice)
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{30, 3}})
	evs, _ = g.Apply(1, Action{Type: ActionDudo}) // p0 perd → 1 dé -> palifico armée
	if g.Players[0].DiceCount != 1 {
		t.Fatalf("p0 DiceCount=%d, want 1", g.Players[0].DiceCount)
	}
	var pali bool
	for _, e := range evs {
		if e.Type == EvPalifico {
			pali = true
		}
	}
	if !pali || !g.Palifico {
		t.Errorf("manche palifico attendue, evs=%v palifico=%v", evs, g.Palifico)
	}
}

func TestPalificoNoJokers(t *testing.T) {
	// En palifico, les pacos ne sont pas jokers (§1.3).
	g := newTestGame(t)
	setDice(g, []int{4, 4, 1}, []int{4, 1, 3}, []int{1, 4, 6})
	g.Palifico, g.fixedV = true, 4
	if got := g.count(4); got != 4 {
		t.Errorf("palifico: count(4)=%d, want 4 (pacos non jokers)", got)
	}
}

func TestPalificoCancelledIfTriggerEliminated(t *testing.T) {
	// §1.3 : si le joueur déclencheur est éliminé avant sa manche, pas de palifico.
	g := newTestGame(t)
	g.Players[0].DiceCount = 1
	setDice(g, []int{6}, []int{2, 2, 2}, []int{3, 3, 3})
	// p0 a déjà armé une palifico précédemment ? Simuler armement puis élimination.
	g.palificoPending, g.palificoTrigger[0] = true, true
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{8, 6}})
	evs, _ := g.Apply(1, Action{Type: ActionDudo}) // p0 éliminé
	for _, e := range evs {
		if e.Type == EvPalifico {
			t.Error("palifico ne devrait pas avoir lieu : déclencheur éliminé")
		}
	}
	if g.Palifico {
		t.Error("g.Palifico devrait être false")
	}
}

func TestAutoAction(t *testing.T) {
	g := newTestGame(t)
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{3, 4}})
	// Expiration du timer pour p1 : enchère minimale (4,4), jamais dudo.
	evs, err := g.AutoAction(1)
	if err != nil {
		t.Fatal(err)
	}
	if evs[0].Type != EvBid || evs[0].Bid != (Bid{4, 4}) {
		t.Errorf("auto-action = %v", evs[0])
	}
	if g.Turn != 2 {
		t.Errorf("turn=%d, want 2", g.Turn)
	}
}

func TestFullGameRandom(t *testing.T) {
	// Joue des parties complètes avec stratégie simple : enchère min ou dudo
	// aléatoire — vérifie que le moteur termine toujours.
	for seed := int64(0); seed < 20; seed++ {
		rng := rand.New(rand.NewSource(seed))
		g, err := New(DefaultOptions(), []string{"a", "b", "c", "d", "e", "f"}, rng)
		if err != nil {
			t.Fatal(err)
		}
		for i := 0; i < 10000 && !g.Over; i++ {
			if rng.Intn(3) == 0 && g.HasBid {
				if _, err := g.Apply(g.Turn, Action{Type: ActionDudo}); err != nil {
					t.Fatalf("seed %d: %v", seed, err)
				}
			} else {
				if _, err := g.AutoAction(g.Turn); err != nil {
					t.Fatalf("seed %d: %v", seed, err)
				}
			}
		}
		if !g.Over {
			t.Fatalf("seed %d: partie non terminée après 10000 actions", seed)
		}
		total := 0
		for _, p := range g.Players {
			total += p.DiceCount
		}
		if g.Winner < 0 || g.Players[g.Winner].DiceCount != total {
			t.Errorf("seed %d: winner=%d total dés=%d", seed, g.Winner, total)
		}
	}
}
