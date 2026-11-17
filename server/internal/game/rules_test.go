package game

// Tests du câblage moteur → hooks de règles perso (§1.5, roadmap v0.7).
// Les règles factices ci-dessous ne sont pas des règles de jeu : elles
// prouvent que chaque point d'extension est réellement traversé.

import (
	"math/rand"
	"testing"

	"doodo/internal/rules"
)

type hookWeighter struct{}

func (hookWeighter) Meta() rules.Meta {
	return rules.Meta{ID: "test_weight", Name: "T", RankedSafe: true}
}
func (hookWeighter) Weight(_ rules.State, _, _, die int) int {
	if die == rules.Paco {
		return 2 // factice : les pacos comptent double
	}
	return 1
}

type hookSurvivor struct{}

func (hookSurvivor) Meta() rules.Meta {
	return rules.Meta{ID: "test_survive", Name: "T", RankedSafe: true}
}
func (hookSurvivor) Survives(_ rules.Resolution, _ int) bool { return true }

type hookFilter struct{}

func (hookFilter) Meta() rules.Meta {
	return rules.Meta{ID: "test_filter", Name: "T", RankedSafe: true}
}
func (hookFilter) FilterBid(_ rules.State, b rules.Bid, legal bool) bool {
	return legal && b.Value != 6 // factice : interdit les enchères sur les 6
}

type hookConflict struct{}

func (hookConflict) Meta() rules.Meta {
	return rules.Meta{ID: "test_conflict", Name: "T", Conflicts: []string{"paco_joker"}, RankedSafe: true}
}

func init() {
	rules.Register(hookWeighter{})
	rules.Register(hookSurvivor{})
	rules.Register(hookFilter{})
	rules.Register(hookConflict{})
}

func newRulesGame(t *testing.T, ids ...string) *Game {
	t.Helper()
	opts := Options{DicePerPlayer: 3, PacoJoker: true, CalzaEnabled: true, PalificoEnabled: true, Rules: ids}
	g, err := New(opts, []string{"a", "b", "c"}, rand.New(rand.NewSource(1)))
	if err != nil {
		t.Fatal(err)
	}
	return g
}

func TestRulesValidateUnknown(t *testing.T) {
	opts := Options{DicePerPlayer: 3, Rules: []string{"inexistante"}}
	if err := opts.Validate(); err == nil {
		t.Fatal("un id de règle inconnu devrait être refusé à la validation")
	}
	if _, err := New(opts, []string{"a", "b"}, rand.New(rand.NewSource(1))); err == nil {
		t.Fatal("un id de règle inconnu devrait être refusé à la création")
	}
}

func TestRulesOptionConflict(t *testing.T) {
	opts := Options{DicePerPlayer: 3, PacoJoker: true, Rules: []string{"test_conflict"}}
	if _, err := New(opts, []string{"a", "b"}, rand.New(rand.NewSource(1))); err == nil {
		t.Fatal("conflit règle/option non détecté")
	}
	opts.PacoJoker = false
	if _, err := New(opts, []string{"a", "b"}, rand.New(rand.NewSource(1))); err != nil {
		t.Fatalf("option désactivée, pas de conflit attendu : %v", err)
	}
}

func TestRulesWeightCount(t *testing.T) {
	g := newRulesGame(t, "test_weight")
	setDice(g, []int{4, 4, 1}, []int{4, 1, 3}, []int{1, 4, 6})
	// 4 fours + 3 pacos×2 = 10 (vs 7 sans la règle).
	if got := g.count(4); got != 10 {
		t.Errorf("count avec pacos double : got %d, want 10", got)
	}
	// Règle inactive : même tirage → décompte standard.
	g2 := newTestGame(t)
	setDice(g2, []int{4, 4, 1}, []int{4, 1, 3}, []int{1, 4, 6})
	if got := g2.count(4); got != 7 {
		t.Errorf("count standard : got %d, want 7", got)
	}
}

func TestRulesFilterBid(t *testing.T) {
	g := newRulesGame(t, "test_filter")
	if g.LegalBid(Bid{Quantity: 1, Value: 6}) {
		t.Error("le filtre devrait interdire la valeur 6")
	}
	if !g.LegalBid(Bid{Quantity: 1, Value: 5}) {
		t.Error("le filtre devrait laisser passer les autres valeurs")
	}
	if _, err := g.Apply(g.Turn, Action{Type: ActionBid, Bid: Bid{Quantity: 1, Value: 6}}); err != ErrIllegalBid {
		t.Errorf("enchère filtrée devrait être refusée : %v", err)
	}
}

func TestRulesSurvives(t *testing.T) {
	g := newRulesGame(t, "test_survive")
	g.Players[1].DiceCount = 1
	setDice(g, []int{4, 4, 4}, []int{2}, []int{4, 4, 4})
	g.Turn = 0
	g.Apply(0, Action{Type: ActionBid, Bid: Bid{Quantity: 3, Value: 4}}) // tenue : count=6
	evs, _ := g.Apply(1, Action{Type: ActionDudo})                       // le douteur perd son dernier dé
	var lost, eliminated bool
	for _, e := range evs {
		if e.Type == EvDieLost && e.Player == 1 {
			lost = true
		}
		if e.Type == EvEliminated && e.Player == 1 {
			eliminated = true
		}
	}
	if !lost {
		t.Error("le douteur devrait perdre un dé")
	}
	if eliminated || !g.Players[1].Alive || g.Players[1].DiceCount != 1 {
		t.Errorf("le survivant doit rester en vie avec 1 dé : alive=%v dice=%d",
			g.Players[1].Alive, g.Players[1].DiceCount)
	}
	if g.Turn != 1 {
		t.Errorf("le survivant entame la manche suivante, turn=%d", g.Turn)
	}
}
