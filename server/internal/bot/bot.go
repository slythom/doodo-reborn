// Package bot implémente les joueurs automatiques (specs §5).
// V1 : un seul niveau « normal » — raisonnement probabiliste sur les dés
// inconnus, bluff léger, calza occasionnel.
package bot

import (
	"math"
	"math/rand"

	"doodo/internal/game"
)

// Normal décide d'une action pour le joueur seat, ne connaissant que ses
// propres dés (comme un joueur honnête).
type Normal struct {
	rng *rand.Rand
}

func NewNormal(rng *rand.Rand) *Normal {
	if rng == nil {
		rng = rand.New(rand.NewSource(rand.Int63()))
	}
	return &Normal{rng: rng}
}

const (
	dudoThreshold = 0.25 // en dessous de cette proba de vérité → Dudo
	calzaMinProb  = 0.35 // proba d'exactitude minimale pour tenter un Calza
	bluffChance   = 0.25 // part de surenchères volontairement optimistes
)

func (b *Normal) Decide(g *game.Game, seat int) game.Action {
	if !g.HasBid {
		return game.Action{Type: game.ActionBid, Bid: b.opening(g, seat)}
	}
	me := g.Players[seat]
	cur := g.Current
	jokers := g.Opts.PacoJoker && !g.Palifico

	known := countMatch(me.Dice, cur.Value, jokers)
	need := cur.Quantity - known
	if need <= 0 {
		return b.raise(g) // l'enchère est certaine, on poursuit
	}
	unknown := totalDice(g) - len(me.Dice)
	if need > unknown {
		return game.Action{Type: game.ActionDudo}
	}
	p := probPerDie(g, cur.Value)
	switch pTrue := binomGE(unknown, p, need); {
	case pTrue < dudoThreshold:
		return game.Action{Type: game.ActionDudo}
	case g.Opts.CalzaEnabled && binomEq(unknown, p, need) > calzaMinProb && b.rng.Float64() < 0.4:
		return game.Action{Type: game.ActionCalza}
	default:
		return b.raise(g)
	}
}

// opening produit l'enchère initiale de la manche : valeur la plus fréquente
// dans sa main, quantité = dés connus + espérance chez les autres.
func (b *Normal) opening(g *game.Game, seat int) game.Bid {
	me := g.Players[seat]
	jokers := g.Opts.PacoJoker && !g.Palifico

	counts := [7]int{}
	for _, d := range me.Dice {
		counts[d]++
	}
	v := game.Paco
	best := 0
	for val := 2; val <= 6; val++ {
		if counts[val] > best {
			best, v = counts[val], val
		}
	}
	if v == game.Paco && !g.Palifico {
		v = 2 // ouverture : paco interdit hors palifico
	}
	others := totalDice(g) - len(me.Dice)
	q := countMatch(me.Dice, v, jokers) + int(math.Round(float64(others)*probPerDie(g, v)))
	if q < 1 {
		q = 1
	}
	return game.Bid{Quantity: q, Value: v}
}

// raise produit une surenchère : minimale le plus souvent, parfois un cran
// au-dessus (bluff léger).
func (b *Normal) raise(g *game.Game) game.Action {
	bid := g.MinBid()
	if b.rng.Float64() < bluffChance {
		bolder := game.Bid{Quantity: bid.Quantity + 1, Value: bid.Value}
		if g.LegalBid(bolder) {
			bid = bolder
		}
	}
	return game.Action{Type: game.ActionBid, Bid: bid}
}

func totalDice(g *game.Game) int {
	n := 0
	for _, p := range g.Players {
		if p.Alive {
			n += len(p.Dice)
		}
	}
	return n
}

// countMatch compte dans une main les dés « correspondants » : valeur v, plus
// les pacos si jokers actifs et v != paco.
func countMatch(dice []int, v int, jokers bool) int {
	n := 0
	for _, d := range dice {
		if d == v || (jokers && v != game.Paco && d == game.Paco) {
			n++
		}
	}
	return n
}

// probPerDie est la probabilité qu'un dé inconnu « corresponde » à v.
func probPerDie(g *game.Game, v int) float64 {
	if g.Palifico || !g.Opts.PacoJoker || v == game.Paco {
		return 1.0 / 6
	}
	return 2.0 / 6 // v elle-même ou paco joker
}

// binomGE = P(X >= k) pour X ~ Binomial(n, p).
func binomGE(n int, p float64, k int) float64 {
	if k <= 0 {
		return 1
	}
	if k > n {
		return 0
	}
	sum := 0.0
	for i := k; i <= n; i++ {
		sum += binomEq(n, p, i)
	}
	return sum
}

// binomEq = P(X == k) pour X ~ Binomial(n, p).
func binomEq(n int, p float64, k int) float64 {
	if k < 0 || k > n {
		return 0
	}
	lg, _ := math.Lgamma(float64(n + 1))
	lgk, _ := math.Lgamma(float64(k + 1))
	lgnk, _ := math.Lgamma(float64(n - k + 1))
	return math.Exp(lg - lgk - lgnk + float64(k)*math.Log(p) + float64(n-k)*math.Log(1-p))
}
