package rules

import "testing"

// ---- Règles factices pour tester le framework (aucune n'est une vraie
// règle de jeu — elles ne font qu'exercer les points de hook) ----

type fakeMeta struct{ meta Meta }

func (f fakeMeta) Meta() Meta { return f.meta }

type fakeBidFilter struct{ fakeMeta }

func (fakeBidFilter) FilterBid(_ State, b Bid, legal bool) bool {
	return legal && b.Value != 6 // factice : interdit les enchères sur les 6
}

type fakeMinBidder struct{ fakeMeta }

func (fakeMinBidder) MinBid(_ State, b Bid) Bid {
	b.Quantity++
	return b
}

type fakeWeighter struct{ fakeMeta }

func (fakeWeighter) Weight(_ State, _, _, die int) int {
	if die == Paco {
		return 2 // factice : pacos comptent double
	}
	return 1
}

type fakeLoser struct{ fakeMeta }

func (fakeLoser) DiceLost(_ Resolution, _, n int) int { return n + 1 }

type fakeGainer struct{ fakeMeta }

func (fakeGainer) DiceGained(_ Resolution, _, n int) int { return n * 2 }

type fakeSurvivor struct{ fakeMeta }

func (fakeSurvivor) Survives(_ Resolution, seat int) bool { return seat == 0 }

type fakeRounder struct{ fakeMeta }

func (fakeRounder) RoundStart(_ State) RoundMod {
	return RoundMod{Starter: 2, ForcePalifico: true}
}

type fakeRevealer struct{ fakeMeta }

func (fakeRevealer) PublicDice(_ State, seat int) []int {
	if seat == 1 {
		return []int{3, 3}
	}
	return nil
}

// metaOf construit une Meta de test.
func metaOf(id string) Meta {
	return Meta{ID: id, Name: "Test " + id, Description: "règle de test", RankedSafe: true}
}

var _ State = fakeState{} // vérifie le contrat à la compilation

type fakeState struct{}

func (fakeState) RoundNo() int         { return 1 }
func (fakeState) IsPalifico() bool     { return false }
func (fakeState) FixedValue() int      { return 0 }
func (fakeState) StandingBid() Bid     { return Bid{3, 4} }
func (fakeState) HasStandingBid() bool { return true }
func (fakeState) BidderSeat() int      { return 0 }
func (fakeState) TurnSeat() int        { return 1 }
func (fakeState) Seats() []int         { return []int{0, 1, 2} }
func (fakeState) PlayerAlive(int) bool { return true }
func (fakeState) DiceCountOf(int) int  { return 5 }
func (fakeState) DiceOf(int) []int     { return []int{1, 2, 3, 4, 5} }
func (fakeState) DicePerPlayer() int   { return 5 }
func (fakeState) Option(string) bool   { return true }

func TestResolveUnknown(t *testing.T) {
	if _, err := Resolve([]string{"inexistante"}); err == nil {
		t.Fatal("id inconnu devrait échouer")
	}
}

func TestResolveIncompatible(t *testing.T) {
	Register(fakeMeta{metaOf("inc_a")})
	b := metaOf("inc_b")
	b.Incompatible = []string{"inc_a"}
	Register(fakeMeta{b})

	if _, err := Resolve([]string{"inc_a"}); err != nil {
		t.Fatalf("seule : %v", err)
	}
	if _, err := Resolve([]string{"inc_b"}); err != nil {
		t.Fatalf("seule : %v", err)
	}
	if _, err := Resolve([]string{"inc_a", "inc_b"}); err == nil {
		t.Fatal("paire incompatible devrait échouer")
	}
}

func TestCheckOptions(t *testing.T) {
	m := metaOf("conflict_rule")
	m.Conflicts = []string{"paco_joker"}
	Register(fakeMeta{m})
	s, err := Resolve([]string{"conflict_rule"})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CheckOptions(map[string]bool{"paco_joker": true}); err == nil {
		t.Fatal("conflit d'option non détecté")
	}
	if err := s.CheckOptions(map[string]bool{"paco_joker": false}); err != nil {
		t.Fatalf("option désactivée : %v", err)
	}
}

func TestNilSetDefaults(t *testing.T) {
	var s *Set // nil : aucune règle active = comportement standard
	if !s.FilterBid(fakeState{}, Bid{9, 6}, true) {
		t.Error("FilterBid nil devrait renvoyer le verdict standard")
	}
	if s.MinBid(fakeState{}, Bid{3, 4}) != (Bid{3, 4}) {
		t.Error("MinBid nil devrait renvoyer l'enchère inchangée")
	}
	if s.Weight(fakeState{}, 0, 4, Paco) != 1 {
		t.Error("Weight nil devrait renvoyer 1")
	}
	if s.DiceLost(Resolution{}, 0, 1) != 1 {
		t.Error("DiceLost nil devrait renvoyer 1")
	}
	if s.DiceGained(Resolution{}, 0, 1) != 1 {
		t.Error("DiceGained nil devrait renvoyer 1")
	}
	if s.Survives(Resolution{}, 0) {
		t.Error("Survives nil devrait être faux")
	}
	if mod := s.RoundStart(fakeState{}); mod != (RoundMod{Starter: -1}) {
		t.Errorf("RoundStart nil devrait être neutre, got %+v", mod)
	}
	if d := s.PublicDice(fakeState{}, 0); d != nil {
		t.Error("PublicDice nil devrait être vide")
	}
	if !s.RankedSafe() {
		t.Error("RankedSafe nil devrait être vrai")
	}
	if err := s.CheckOptions(map[string]bool{"paco_joker": true}); err != nil {
		t.Errorf("CheckOptions nil devrait passer : %v", err)
	}
}

func TestSetHooks(t *testing.T) {
	Register(fakeBidFilter{fakeMeta{metaOf("t_filter")}})
	Register(fakeMinBidder{fakeMeta{metaOf("t_min")}})
	Register(fakeWeighter{fakeMeta{metaOf("t_weight")}})
	Register(fakeLoser{fakeMeta{metaOf("t_loser")}})
	Register(fakeGainer{fakeMeta{metaOf("t_gainer")}})
	Register(fakeSurvivor{fakeMeta{metaOf("t_surv")}})
	Register(fakeRounder{fakeMeta{metaOf("t_round")}})
	Register(fakeRevealer{fakeMeta{metaOf("t_reveal")}})

	s, err := Resolve([]string{"t_filter", "t_min", "t_weight", "t_loser",
		"t_gainer", "t_surv", "t_round", "t_reveal"})
	if err != nil {
		t.Fatal(err)
	}
	st := fakeState{}

	if s.FilterBid(st, Bid{4, 6}, true) {
		t.Error("BidFilter devrait interdire la valeur 6")
	}
	if !s.FilterBid(st, Bid{4, 5}, true) {
		t.Error("BidFilter devrait garder légal le reste")
	}
	if s.FilterBid(st, Bid{4, 5}, false) {
		t.Error("BidFilter ne doit pas rendre légal une enchère illégale de base")
	}
	if got := s.MinBid(st, Bid{3, 4}); got.Quantity != 4 {
		t.Errorf("MinBidder : quantité attendue 4, got %d", got.Quantity)
	}
	if s.Weight(st, 0, 4, Paco) != 2 || s.Weight(st, 0, 4, 4) != 1 {
		t.Error("Weighter : pacos ×2, autres ×1")
	}
	if s.DiceLost(Resolution{}, 0, 1) != 2 {
		t.Error("DieLoser devrait porter la perte à 2")
	}
	if s.DiceGained(Resolution{}, 0, 1) != 2 {
		t.Error("DieGainer devrait porter le gain à 2")
	}
	if !s.Survives(Resolution{}, 0) || s.Survives(Resolution{}, 1) {
		t.Error("Survivor : siège 0 sauvé, siège 1 non")
	}
	mod := s.RoundStart(st)
	if mod.Starter != 2 || !mod.ForcePalifico || mod.SkipPalifico {
		t.Errorf("RoundStart mal fusionné : %+v", mod)
	}
	if d := s.PublicDice(st, 1); len(d) != 1 || d[0] != 3 {
		t.Errorf("PublicDice devrait dédoublonner : %v", d)
	}
	if d := s.PublicDice(st, 0); d != nil {
		t.Errorf("PublicDice siège 0 devrait être vide : %v", d)
	}
}

func TestRankedSafe(t *testing.T) {
	Register(fakeMeta{metaOf("safe_a")})
	unsafe := metaOf("unsafe_b")
	unsafe.RankedSafe = false
	Register(fakeMeta{unsafe})

	s, _ := Resolve([]string{"safe_a"})
	if !s.RankedSafe() {
		t.Error("règle classée : partie devrait rester classée")
	}
	s, _ = Resolve([]string{"safe_a", "unsafe_b"})
	if s.RankedSafe() {
		t.Error("une règle non classée suffit à déclasser la partie")
	}
}
