// Package rules : moteur modulaire des règles personnalisées (§1.5).
//
// Une règle se déclare via Register (à l'init de son implémentation) et
// s'active par id dans les options de table. Le moteur de jeu consulte un
// Set via des interfaces de hooks optionnelles — une règle n'implémente
// que les hooks dont elle a besoin. Aucune règle active = jeu inchangé :
// toutes les méthodes de *Set sont nil-sûres et renvoient le comportement
// standard.
package rules

import (
	"fmt"
	"sort"
)

// Paco est la valeur spéciale des dés jokers (§1.2).
const Paco = 1

// Bid est une enchère « au moins Quantity dés de valeur Value sur la
// table ». Définie ici (et ré-exportée par game via alias) pour que les
// hooks puissent la manipuler sans créer de cycle d'imports.
type Bid struct {
	Quantity int `json:"quantity"`
	Value    int `json:"value"` // Paco (1) à 6
}

func (b Bid) String() string {
	if b.Value == Paco {
		return fmt.Sprintf("%d paco(s)", b.Quantity)
	}
	return fmt.Sprintf("%d x %d", b.Quantity, b.Value)
}

// ---- Métadonnées (§1.5) ----

// Meta décrit une règle perso : affichage dans les options de table et
// déclaration de compatibilité.
type Meta struct {
	ID           string   `json:"id"`                     // identifiant stable (activé par les options)
	Name         string   `json:"name"`                   // libellé court affiché
	Description  string   `json:"description"`            // une ligne — infobulle / options
	Incompatible []string `json:"incompatible,omitempty"` // ids d'autres règles perso
	Conflicts    []string `json:"conflicts,omitempty"`    // options officielles incompatibles
	Requires     []string `json:"requires,omitempty"`     // options officielles exigées
	RankedSafe   bool     `json:"ranked_safe"`            // false = partie non classée (§1.5)
}

// Rule est le contrat minimal d'une règle perso : ses métadonnées. Les
// effets s'expriment via les interfaces de hooks optionnelles ci-dessous.
type Rule interface {
	Meta() Meta
}

// ---- Vue en lecture seule passée aux hooks ----

// State est l'état de jeu exposé aux hooks. *game.Game l'implémente.
type State interface {
	RoundNo() int
	IsPalifico() bool
	FixedValue() int  // valeur figée en palifico, 0 sinon
	StandingBid() Bid // enchère debout (nulle si !HasStandingBid)
	HasStandingBid() bool
	BidderSeat() int // -1 si aucune enchère
	TurnSeat() int
	Seats() []int // sièges vivants, ordre croissant
	PlayerAlive(seat int) bool
	DiceCountOf(seat int) int // dés restants
	DiceOf(seat int) []int    // lancer courant (vide si éliminé)
	DicePerPlayer() int
	Option(key string) bool // "paco_joker" | "calza_enabled" | "palifico_enabled"
}

// Act est le type d'action passé aux hooks d'éligibilité (TurnFilter).
type Act int

const (
	ActBid Act = iota
	ActDudo
	ActCalza
)

// Resolution : contexte d'une contestation passé aux hooks de perte de dé.
type Resolution struct {
	Challenger int  // siège du douteur (dudo) ou du calzeur (calza)
	Calza      bool // true = calza, false = dudo
	Bid        Bid  // enchère contestée
	BidderSeat int  // siège de l'enchérisseur
	Count      int  // décompte réel de la valeur enchérie
}

// Won : l'enchère était tenue (décompte >= quantité).
func (r Resolution) Won() bool { return r.Count >= r.Bid.Quantity }

// Exact : le décompte égale exactement la quantité (calza réussi, §1.4).
func (r Resolution) Exact() bool { return r.Count == r.Bid.Quantity }

// RoundMod : ajustements de conditions de manche demandés par un Rounder.
type RoundMod struct {
	Starter       int  // siège qui entame la manche (-1 = inchangé)
	ForcePalifico bool // impose une manche palifico
	SkipPalifico  bool // annule la palifico armée
}

// ---- Interfaces de hooks (optionnelles) ----
// Une règle n'implémente que celles dont elle a besoin, par catégorie.

// Validation d'enchère : FilterBid reçoit le verdict standard et peut le
// durcir ou l'assouplir ; appelés en séquence dans l'ordre d'activation.
type BidFilter interface {
	FilterBid(s State, b Bid, legal bool) bool
}

// MinBidder ajuste l'enchère minimale légale (auto-action du timer, §1.4).
type MinBidder interface {
	MinBid(s State, b Bid) Bid
}

// Décompte : Weight pondère le dé die (siège seat) dans le comptage de la
// valeur target. Le moteur multiplie les poids de toutes les règles
// (défaut 1 ; 0 exclut le dé). Ex. « Double Paco » → 2 pour les pacos.
type Weighter interface {
	Weight(s State, seat, target, die int) int
}

// Perte de dé à la résolution : DiceLost ajuste le nombre de dés perdus
// par seat (défaut 1, plafonné aux dés restants).
type DieLoser interface {
	DiceLost(r Resolution, seat, n int) int
}

// DieGainer ajuste le gain d'un calza réussi (défaut 1 dé, plafonné au
// nombre de dés de départ — §1.4).
type DieGainer interface {
	DiceGained(r Resolution, seat, n int) int
}

// Survivor peut empêcher l'élimination de seat à la résolution : le
// joueur repart avec 1 dé au lieu de sortir (ex. « Survivant », §1.5).
type Survivor interface {
	Survives(r Resolution, seat int) bool
}

// Conditions de manche : Rounder demande des ajustements appliqués au
// début de chaque manche (palifico forcée/annulée, joueur entamant).
// Appelé après le tirage des dés — DiceOf renvoie le nouveau lancer.
type Rounder interface {
	RoundStart(s State) RoundMod
}

// Revealer déclare des dés de seat visibles par toute la table (ex.
// « Dé public », §1.5). La salle les fusionne dans les vues joueurs.
type Revealer interface {
	PublicDice(s State, seat int) []int
}

// Éligibilité d'action : TurnFilter est appelé quand seat n'est PAS le
// joueur de tour ; true autorise l'action hors tour (« Salsa » : enchères
// et dudo hors tour, calza réservé au tour).
type TurnFilter interface {
	CanAct(s State, seat int, act Act) bool
}

// InvalidRoll : conditions de manche — déclare le lancer de seat
// éliminatoire ; le moteur l'élimine d'office puis relance une manche
// (« Pacobye » : tirage 100 % pacos avec 4-5 dés, §1.5).
type InvalidRoller interface {
	InvalidRoll(s State, seat int) bool
}

// DieStealer : perte de dé — transforme le gain d'un calza réussi en vol :
// le moteur suspend la résolution et attend que le voleur désigne sa
// victime (« Calzone », §1.5).
type DieStealer interface {
	StealsDie(r Resolution, thief int) bool
}

// ---- Registre et collection ----

var registry = map[string]Rule{}

// Register enregistre une règle dans le catalogue — appelé à l'init des
// implémentations. Panique sur id dupliqué : erreur de dev, pas runtime.
func Register(r Rule) {
	id := r.Meta().ID
	if _, dup := registry[id]; dup {
		panic("rules: id dupliqué " + id)
	}
	registry[id] = r
}

// Available liste les métadonnées de toutes les règles connues, triées
// par id (listage des options de table, §1.5).
func Available() []Meta {
	var metas []Meta
	for _, r := range registry {
		metas = append(metas, r.Meta())
	}
	sort.Slice(metas, func(i, j int) bool { return metas[i].ID < metas[j].ID })
	return metas
}

// Set : collection de règles actives pour une partie. Le moteur
// l'interroge via des méthodes sémantiques — toutes nil-sûres : un Set
// nil reproduit exactement le comportement standard.
type Set struct {
	rules []Rule
}

// Resolve instancie le Set des règles demandées. Id inconnu ou paire de
// règles déclarées incompatibles -> erreur.
func Resolve(ids []string) (*Set, error) {
	s := &Set{}
	for _, id := range ids {
		r, ok := registry[id]
		if !ok {
			return nil, fmt.Errorf("rules: règle inconnue %q", id)
		}
		s.rules = append(s.rules, r)
	}
	seen := map[string]bool{}
	for _, r := range s.each() {
		m := r.Meta()
		for _, other := range m.Incompatible {
			if seen[other] {
				return nil, fmt.Errorf("rules: %q incompatible avec %q", m.ID, other)
			}
		}
		seen[m.ID] = true
	}
	return s, nil
}

// each protège l'accès aux règles : nil-sûr, rend toutes les méthodes de
// *Set appelables sur un receveur nil (= aucune règle active).
func (s *Set) each() []Rule {
	if s == nil {
		return nil
	}
	return s.rules
}

// CheckOptions vérifie les conflits règle ↔ options officielles.
// enabled mappe les clés d'option ("paco_joker", …) à leur état.
func (s *Set) CheckOptions(enabled map[string]bool) error {
	for _, r := range s.each() {
		m := r.Meta()
		for _, key := range m.Conflicts {
			if enabled[key] {
				return fmt.Errorf("rules: %q incompatible avec l'option %q", m.ID, key)
			}
		}
		for _, key := range m.Requires {
			if !enabled[key] {
				return fmt.Errorf("rules: %q requiert l'option %q", m.ID, key)
			}
		}
	}
	return nil
}

// Metas : métadonnées des règles actives, dans l'ordre d'activation.
func (s *Set) Metas() []Meta {
	var metas []Meta
	for _, r := range s.each() {
		metas = append(metas, r.Meta())
	}
	return metas
}

// RankedSafe : la partie reste éligible aux stats — ET de toutes les
// règles actives (une seule règle non classée suffit, §1.5/§2.3).
func (s *Set) RankedSafe() bool {
	for _, r := range s.each() {
		if !r.Meta().RankedSafe {
			return false
		}
	}
	return true
}

// ---- Points d'appel du moteur — tous nil-sûrs ----

// FilterBid applique les BidFilter en séquence sur le verdict standard.
func (s *Set) FilterBid(st State, b Bid, legal bool) bool {
	for _, r := range s.each() {
		if f, ok := r.(BidFilter); ok {
			legal = f.FilterBid(st, b, legal)
		}
	}
	return legal
}

// MinBid applique les MinBidder en séquence sur l'enchère minimale.
func (s *Set) MinBid(st State, b Bid) Bid {
	for _, r := range s.each() {
		if f, ok := r.(MinBidder); ok {
			b = f.MinBid(st, b)
		}
	}
	return b
}

// Weight compose les poids des Weighter pour un dé compté (défaut 1).
func (s *Set) Weight(st State, seat, target, die int) int {
	w := 1
	for _, r := range s.each() {
		if f, ok := r.(Weighter); ok {
			w *= f.Weight(st, seat, target, die)
			if w == 0 {
				break
			}
		}
	}
	return w
}

// DiceLost applique les DieLoser en séquence sur le nombre de dés perdus.
func (s *Set) DiceLost(res Resolution, seat, n int) int {
	for _, r := range s.each() {
		if f, ok := r.(DieLoser); ok {
			n = f.DiceLost(res, seat, n)
		}
	}
	return n
}

// DiceGained applique les DieGainer en séquence sur le gain de dés.
func (s *Set) DiceGained(res Resolution, seat, n int) int {
	for _, r := range s.each() {
		if f, ok := r.(DieGainer); ok {
			n = f.DiceGained(res, seat, n)
		}
	}
	return n
}

// Survives : un Survivor suffit pour sauver le joueur de l'élimination.
func (s *Set) Survives(res Resolution, seat int) bool {
	for _, r := range s.each() {
		if f, ok := r.(Survivor); ok && f.Survives(res, seat) {
			return true
		}
	}
	return false
}

// RoundStart fusionne les RoundMod des Rounder (Starter : dernier
// non -1 ; les booléens : OU).
func (s *Set) RoundStart(st State) RoundMod {
	mod := RoundMod{Starter: -1}
	for _, r := range s.each() {
		if f, ok := r.(Rounder); ok {
			m := f.RoundStart(st)
			if m.Starter >= 0 {
				mod.Starter = m.Starter
			}
			mod.ForcePalifico = mod.ForcePalifico || m.ForcePalifico
			mod.SkipPalifico = mod.SkipPalifico || m.SkipPalifico
		}
	}
	return mod
}

// CanAct : un TurnFilter suffit pour autoriser l'action hors tour.
func (s *Set) CanAct(st State, seat int, act Act) bool {
	for _, r := range s.each() {
		if f, ok := r.(TurnFilter); ok && f.CanAct(st, seat, act) {
			return true
		}
	}
	return false
}

// InvalidRoll : un InvalidRoller suffit pour déclarer le lancer
// éliminatoire.
func (s *Set) InvalidRoll(st State, seat int) bool {
	for _, r := range s.each() {
		if f, ok := r.(InvalidRoller); ok && f.InvalidRoll(st, seat) {
			return true
		}
	}
	return false
}

// StealsDie : un DieStealer suffit pour transformer le gain en vol.
func (s *Set) StealsDie(res Resolution, thief int) bool {
	for _, r := range s.each() {
		if f, ok := r.(DieStealer); ok && f.StealsDie(res, thief) {
			return true
		}
	}
	return false
}

// PublicDice agrège les dés dévoilés par les Revealer (dédoublonnés).
func (s *Set) PublicDice(st State, seat int) []int {
	var out []int
	seen := map[int]bool{}
	for _, r := range s.each() {
		if f, ok := r.(Revealer); ok {
			for _, d := range f.PublicDice(st, seat) {
				if !seen[d] {
					seen[d] = true
					out = append(out, d)
				}
			}
		}
	}
	sort.Ints(out)
	return out
}
