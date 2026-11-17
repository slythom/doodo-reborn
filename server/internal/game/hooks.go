package game

import "doodo/internal/rules"

// Implémentation de rules.State : la vue en lecture seule du jeu passée
// aux hooks des règles perso (§1.5). Les méthodes renvoient l'état brut —
// les règles sont du code interne de confiance, pas des plugins externes.

func (g *Game) RoundNo() int           { return g.Round }
func (g *Game) IsPalifico() bool       { return g.Palifico }
func (g *Game) FixedValue() int        { return g.fixedV }
func (g *Game) StandingBid() rules.Bid { return rbid(g.Current) }
func (g *Game) HasStandingBid() bool   { return g.HasBid }
func (g *Game) BidderSeat() int        { return g.Bidder }
func (g *Game) TurnSeat() int          { return g.Turn }
func (g *Game) DicePerPlayer() int     { return g.Opts.DicePerPlayer }

func (g *Game) Seats() []int { return g.alivePlayers() }

func (g *Game) PlayerAlive(seat int) bool {
	return seat >= 0 && seat < len(g.Players) && g.Players[seat].Alive
}

func (g *Game) DiceCountOf(seat int) int {
	if seat < 0 || seat >= len(g.Players) {
		return 0
	}
	return g.Players[seat].DiceCount
}

func (g *Game) DiceOf(seat int) []int {
	if seat < 0 || seat >= len(g.Players) || !g.Players[seat].Alive {
		return nil
	}
	return g.Players[seat].Dice
}

// Option expose les options officielles aux hooks par clé stable —
// les mêmes clés que Meta.Conflicts.
func (g *Game) Option(key string) bool {
	switch key {
	case "paco_joker":
		return g.Opts.PacoJoker
	case "calza_enabled":
		return g.Opts.CalzaEnabled
	case "palifico_enabled":
		return g.Opts.PalificoEnabled
	}
	return false
}

// Rules : les règles perso actives de la partie (nil = jeu standard) —
// la salle s'en sert pour les métadonnées et le statut classé (§1.5).
func (g *Game) Rules() *rules.Set { return g.rules }
