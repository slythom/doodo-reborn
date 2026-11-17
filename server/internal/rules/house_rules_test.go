package rules

import "testing"

// Tests des règles perso implémentées (§1.5, v0.8) — comportements
// unitaires via un état factice paramétrable.

type houseState struct {
	fakeState
	dice     map[int][]int
	palifico bool
	options  map[string]bool
	alive    map[int]bool // nil = tous vivants
}

func (h houseState) DiceOf(seat int) []int    { return h.dice[seat] }
func (h houseState) DiceCountOf(seat int) int { return len(h.dice[seat]) }
func (h houseState) IsPalifico() bool         { return h.palifico }
func (h houseState) Option(k string) bool     { return h.options[k] }

func (h houseState) PlayerAlive(seat int) bool {
	if h.alive == nil {
		return true
	}
	return h.alive[seat]
}

func TestDePublic(t *testing.T) {
	s, err := Resolve([]string{"de_public"})
	if err != nil {
		t.Fatal(err)
	}
	st := houseState{dice: map[int][]int{0: {3, 5, 2}, 1: {6}}}
	if got := s.PublicDice(st, 0); len(got) != 1 || got[0] != 3 {
		t.Errorf("un seul dé dévoilé (le premier), got %v", got)
	}
	if got := s.PublicDice(st, 1); len(got) != 1 || got[0] != 6 {
		t.Errorf("joueur à 1 dé : ce dé est dévoilé, got %v", got)
	}
	if got := s.PublicDice(st, 2); got != nil {
		t.Errorf("joueur sans dé : rien de dévoilé, got %v", got)
	}
}

func TestDoublePaco(t *testing.T) {
	s, err := Resolve([]string{"double_paco"})
	if err != nil {
		t.Fatal(err)
	}
	on := houseState{options: map[string]bool{"paco_joker": true}}
	// Paco joker actif, enchère classique : les pacos comptent double.
	if w := s.Weight(on, 0, 4, Paco); w != 2 {
		t.Errorf("paco joker sur enchère classique : poids 2 attendu, got %d", w)
	}
	if w := s.Weight(on, 0, 4, 4); w != 1 {
		t.Errorf("dé de la valeur enchérie : poids 1, got %d", w)
	}
	// Enchère de pacos : les pacos restent à poids 1 (rôle nominal).
	if w := s.Weight(on, 0, Paco, Paco); w != 1 {
		t.Errorf("enchère de pacos : poids 1, got %d", w)
	}
	// Paco joker off : la règle est inerte.
	if w := s.Weight(houseState{}, 0, 4, Paco); w != 1 {
		t.Errorf("joker off : poids 1, got %d", w)
	}
	// Palifico : pas de jokers, pas de double.
	pal := houseState{palifico: true, options: map[string]bool{"paco_joker": true}}
	if w := s.Weight(pal, 0, 4, Paco); w != 1 {
		t.Errorf("palifico : poids 1, got %d", w)
	}
	// Déclaration : paco_joker exigé.
	if err := s.CheckOptions(map[string]bool{"paco_joker": false}); err == nil {
		t.Error("double_paco sans paco_joker devrait être refusé")
	}
}

func TestSalsa(t *testing.T) {
	s, err := Resolve([]string{"salsa"})
	if err != nil {
		t.Fatal(err)
	}
	st := houseState{dice: map[int][]int{2: {1, 2}}}
	// Hors tour : enchère et dudo autorisés pour tout joueur vivant.
	if !s.CanAct(st, 2, ActBid) {
		t.Error("enchère hors tour devrait être autorisée")
	}
	if !s.CanAct(st, 2, ActDudo) {
		t.Error("dudo hors tour devrait être autorisé")
	}
	// Le calza reste réservé au joueur de tour.
	if s.CanAct(st, 2, ActCalza) {
		t.Error("calza hors tour ne devrait pas être autorisé")
	}
	// Joueur éliminé : rien ne passe.
	dead := houseState{alive: map[int]bool{2: false}}
	if s.CanAct(dead, 2, ActBid) {
		t.Error("joueur éliminé ne devrait pas agir")
	}
}

func TestCalzone(t *testing.T) {
	s, err := Resolve([]string{"calzone"})
	if err != nil {
		t.Fatal(err)
	}
	if !s.StealsDie(Resolution{Calza: true}, 0) {
		t.Error("calzone devrait voler un dé sur calza réussi")
	}
	if err := s.CheckOptions(map[string]bool{"calza_enabled": false}); err == nil {
		t.Error("calzone sans calza_enabled devrait être refusé")
	}
	if err := s.CheckOptions(map[string]bool{"calza_enabled": true}); err != nil {
		t.Errorf("calzone avec calza_enabled : %v", err)
	}
}

func TestPacoBye(t *testing.T) {
	s, err := Resolve([]string{"pacobye"})
	if err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		dice []int
		want bool
	}{
		{"5 pacos", []int{1, 1, 1, 1, 1}, true},
		{"4 pacos", []int{1, 1, 1, 1}, true},
		{"3 pacos — règle inerte", []int{1, 1, 1}, false},
		{"2 pacos — inerte", []int{1, 1}, false},
		{"4 dés dont 1 non-paco", []int{1, 1, 1, 4}, false},
		{"5 dés mélangés", []int{1, 1, 1, 1, 6}, false},
		{"aucun dé", nil, false},
	}
	for _, c := range cases {
		st := houseState{dice: map[int][]int{0: c.dice}}
		if got := s.InvalidRoll(st, 0); got != c.want {
			t.Errorf("%s : InvalidRoll = %v, attendu %v", c.name, got, c.want)
		}
	}
}

func TestAvailableListsHouseRules(t *testing.T) {
	want := map[string]bool{
		"de_public": false, "double_paco": false, "salsa": false,
		"calzone": false, "pacobye": false,
	}
	for _, m := range Available() {
		if _, ok := want[m.ID]; ok {
			want[m.ID] = true
			if m.Name == "" || m.Description == "" {
				t.Errorf("%s : métadonnées d'affichage incomplètes", m.ID)
			}
		}
	}
	for id, found := range want {
		if !found {
			t.Errorf("règle %q absente du catalogue", id)
		}
	}
}
