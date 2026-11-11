// doodo-cli est une interface de debug pour le moteur internal/game :
// tous les joueurs sont pilotés à la main et tous les dés sont visibles.
//
// Commandes :
//
//	bid X V   enchérir (ex: bid 3 4 — « 3 dés de valeur 4 » ; V=1 = paco)
//	dudo      douter de l'enchère en cours
//	calza     annoncer l'enchère exacte
//	auto      simuler l'expiration du timer (enchère minimale auto)
//	abandon   éliminer le joueur courant (abandon/expulsion)
//	quit      quitter
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"doodo/internal/game"
)

func main() {
	fmt.Println("=== doodo-cli — debug du moteur Perudo ===")
	fmt.Print("Pseudos (séparés par des espaces) [a b c d] : ")
	in := bufio.NewScanner(os.Stdin)
	ids := []string{"a", "b", "c", "d"}
	if in.Scan() && strings.TrimSpace(in.Text()) != "" {
		ids = strings.Fields(in.Text())
	}
	g, err := game.New(game.DefaultOptions(), ids, nil)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	printState(g)

	for in.Scan() {
		fields := strings.Fields(in.Text())
		if len(fields) == 0 {
			prompt(g)
			continue
		}
		var evs []game.Event
		switch fields[0] {
		case "bid":
			if len(fields) != 3 {
				fmt.Println("usage: bid <quantité> <valeur>")
				break
			}
			q, e1 := strconv.Atoi(fields[1])
			v, e2 := strconv.Atoi(fields[2])
			if e1 != nil || e2 != nil {
				fmt.Println("usage: bid <quantité> <valeur> (entiers)")
				break
			}
			evs, err = g.Apply(g.Turn, game.Action{Type: game.ActionBid, Bid: game.Bid{Quantity: q, Value: v}})
		case "dudo":
			evs, err = g.Apply(g.Turn, game.Action{Type: game.ActionDudo})
		case "calza":
			evs, err = g.Apply(g.Turn, game.Action{Type: game.ActionCalza})
		case "auto":
			evs, err = g.AutoAction(g.Turn)
		case "abandon":
			evs = g.Abandon(g.Turn)
		case "quit", "exit":
			return
		default:
			fmt.Println("commandes: bid X V | dudo | calza | auto | abandon | quit")
		}
		if err != nil {
			fmt.Println("!", err)
			err = nil
		} else {
			printEvents(g, evs)
		}
		if g.Over {
			fmt.Println("=== partie terminée ===")
			return
		}
		printState(g)
		prompt(g)
	}
}

func name(g *game.Game, i int) string {
	if i < 0 || i >= len(g.Players) {
		return "?"
	}
	return g.Players[i].ID
}

func printState(g *game.Game) {
	pali := ""
	if g.Palifico {
		pali = "  *** PALIFICO ***"
	}
	fmt.Printf("\n--- Manche %d%s ---\n", g.Round, pali)
	for i, p := range g.Players {
		if !p.Alive {
			fmt.Printf("  %s : éliminé\n", p.ID)
			continue
		}
		turn := "  "
		if g.Turn == i {
			turn = "> "
		}
		fmt.Printf(" %s%s : %v  (%d dé(s))\n", turn, p.ID, p.Dice, p.DiceCount)
	}
	if g.HasBid {
		fmt.Printf("  enchère : %s par %s\n", g.Current, name(g, g.Bidder))
	}
}

func printEvents(g *game.Game, evs []game.Event) {
	for _, e := range evs {
		switch e.Type {
		case game.EvBid:
			fmt.Printf("→ %s enchérit : %s\n", name(g, e.Player), e.Bid)
		case game.EvReveal:
			fmt.Printf("→ %s révèle ! Enchère %s vs réalité : %d dé(s)\n", name(g, e.Player), e.Bid, e.Count)
		case game.EvDieLost:
			fmt.Printf("→ %s perd un dé\n", name(g, e.Player))
		case game.EvDieGained:
			fmt.Printf("→ %s regagne un dé\n", name(g, e.Player))
		case game.EvEliminated:
			fmt.Printf("→ %s est éliminé\n", name(g, e.Player))
		case game.EvPalifico:
			fmt.Println("→ *** manche PALIFICO : pacos non jokers, valeur figée au premier enchérisseur ***")
		case game.EvRoundStart:
			fmt.Printf("→ manche %d — %s entame\n", g.Round, name(g, e.Player))
		case game.EvGameOver:
			fmt.Print("→ CLASSEMENT : ")
			for r, p := range e.Ranking {
				fmt.Printf("%d.%s ", r+1, name(g, p))
			}
			fmt.Println()
		}
	}
}

func prompt(g *game.Game) {
	fmt.Printf("\n%s > ", name(g, g.Turn))
}
