package protocol

import (
	"encoding/json"
	"strings"
	"testing"

	"doodo/internal/game"
)

// TestJSONShape épingle le contrat wire : les champs doivent rester en
// snake_case minuscule — le client Godot lit quantity/value/type.
func TestJSONShape(t *testing.T) {
	v := View{Bid: game.Bid{Quantity: 3, Value: 4}, HasBid: true}
	b, _ := json.Marshal(v)
	s := string(b)
	for _, want := range []string{`"bid":{"quantity":3,"value":4}`, `"has_bid":true`} {
		if !strings.Contains(s, want) {
			t.Errorf("View JSON %s ne contient pas %s", s, want)
		}
	}

	e := Envelope{Type: "events", Data: Events{Events: []game.Event{
		{Type: game.EvReveal, Player: 2, Bid: game.Bid{Quantity: 5, Value: 6}, Count: 4},
	}}}
	b2, _ := json.Marshal(e)
	s2 := string(b2)
	for _, want := range []string{`"type":"reveal"`, `"player":2`} {
		if !strings.Contains(s2, want) {
			t.Errorf("events JSON %s ne contient pas %s", s2, want)
		}
	}
}
