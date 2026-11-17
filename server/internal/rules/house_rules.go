package rules

// Règles personnalisées implémentées (§1.5, roadmap v0.8). Chacune
// n'implémente que les hooks dont elle a besoin ; l'enregistrement se fait
// à l'init via Register.
func init() {
	Register(dePublic{})
	Register(doublePaco{})
	Register(salsa{})
	Register(calzone{})
	Register(pacoBye{})
}

// « Dé public » — le premier dé du lancer de chaque joueur est révélé à
// toute la table en début de manche.
type dePublic struct{}

func (dePublic) Meta() Meta {
	return Meta{
		ID: "de_public", Name: "Dé public", RankedSafe: true,
		Description: "Un dé de chaque joueur est révélé à tous en début de manche",
	}
}

func (dePublic) PublicDice(s State, seat int) []int {
	if d := s.DiceOf(seat); len(d) > 0 {
		return d[:1]
	}
	return nil
}

// « Double Paco » — les pacos comptent double au décompte, quand ils
// jouent leur rôle de joker (enchère non-paco, hors palifico — §1.3).
// Requiert l'option « Paco joker » : sans jokers, la règle est inerte.
type doublePaco struct{}

func (doublePaco) Meta() Meta {
	return Meta{
		ID: "double_paco", Name: "Double Paco", RankedSafe: true,
		Description: "Les pacos comptent double au décompte",
		Requires:    []string{"paco_joker"},
	}
}

func (doublePaco) Weight(s State, _, target, die int) int {
	if die == Paco && target != Paco && s.Option("paco_joker") && !s.IsPalifico() {
		return 2
	}
	return 1
}

// « Salsa » — enchères et dudo hors de son tour ; le calza reste réservé
// au joueur de tour. L'obligation de parler reste sur le joueur suivant
// l'ordre naturel (le tour avance après chaque surenchère, y compris hors
// tour).
type salsa struct{}

func (salsa) Meta() Meta {
	return Meta{
		ID: "salsa", Name: "Salsa", RankedSafe: true,
		Description: "Enchérir et douter hors de son tour",
	}
}

func (salsa) CanAct(s State, seat int, act Act) bool {
	return (act == ActBid || act == ActDudo) && s.PlayerAlive(seat)
}

// « Calzone » — calza réussi : au lieu de regagner un dé, le calzeur vole
// un dé à l'adversaire de son choix. Requiert « Calza » : sans calza, pas
// de vol possible.
type calzone struct{}

func (calzone) Meta() Meta {
	return Meta{
		ID: "calzone", Name: "Calzone", RankedSafe: true,
		Description: "Calza réussi : vole un dé à l'adversaire de ton choix",
		Requires:    []string{"calza_enabled"},
	}
}

func (calzone) StealsDie(_ Resolution, _ int) bool { return true }

// « Pacobye » — tirage 100 % pacos : élimination d'office, la manche est
// relancée. Ne s'applique qu'avec 4 ou 5 dés en main (en dessous, la règle
// est inerte).
type pacoBye struct{}

func (pacoBye) Meta() Meta {
	return Meta{
		ID: "pacobye", Name: "Pacobye", RankedSafe: true,
		Description: "Tirage 100 % pacos (avec 4-5 dés) : élimination immédiate",
	}
}

func (pacoBye) InvalidRoll(s State, seat int) bool {
	if n := s.DiceCountOf(seat); n < 4 || n > 5 {
		return false
	}
	for _, d := range s.DiceOf(seat) {
		if d != Paco {
			return false
		}
	}
	return true
}
