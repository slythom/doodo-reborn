package room

import (
	"encoding/json"
	"math/rand"
	"testing"

	"doodo/internal/game"
	"doodo/internal/protocol"
)

// benchRoom : salle lancée avec n membres humains (état « playing »).
func benchRoom(b *testing.B, n int) *Room {
	b.Helper()
	clk := &fakeClock{}
	s := &sink{}
	opts := protocol.Options{
		Game:         game.Options{DicePerPlayer: 5, PacoJoker: true, CalzaEnabled: true, PalificoEnabled: true},
		TimerSeconds: 30,
		MaxPlayers:   6,
		Spectators:   true,
	}
	r := New("BENCH1", &Member{ID: "u1", Name: "alice"}, opts,
		rand.New(rand.NewSource(1)), s.emit, clk.after)
	for i := 2; i <= n; i++ {
		m := &Member{ID: "u" + string(rune('a'+i)), Name: "p" + string(rune('a'+i)), Connected: true}
		if err := r.Join(m); err != nil {
			b.Fatalf("join: %v", err)
		}
	}
	if err := r.Launch("u1"); err != nil {
		b.Fatalf("launch: %v", err)
	}
	return r
}

// marshalSink mesure le coût réel d'émission : le hub sérialise l'enveloppe
// par destinataire (vue personnalisée — pas de marshal partagé possible).
type marshalSink struct{ bytes int64 }

func (s *marshalSink) emit(_ []string, env protocol.Envelope) {
	b, _ := json.Marshal(env)
	s.bytes += int64(len(b))
}

// Construction du snapshot pour UN membre — appelée une fois par membre
// connecté à chaque changement d'état.
func BenchmarkViewForLocked(b *testing.B) {
	r := benchRoom(b, 6)
	m := r.players[0]
	b.ReportAllocs()
	for b.Loop() {
		_ = r.viewForLocked(m)
	}
}

// Chemin complet par membre : vue + sérialisation JSON — ce que paie le
// hub à chaque snapshot poussé.
func BenchmarkSendViewLocked(b *testing.B) {
	clk := &fakeClock{}
	s := &marshalSink{}
	opts := protocol.Options{
		Game:         game.Options{DicePerPlayer: 5, PacoJoker: true, CalzaEnabled: true},
		TimerSeconds: 30, MaxPlayers: 6, Spectators: true,
	}
	r := New("BENCH2", &Member{ID: "u1", Name: "alice"}, opts,
		rand.New(rand.NewSource(1)), s.emit, clk.after)
	for i := 2; i <= 6; i++ {
		m := &Member{ID: "u" + string(rune('a'+i)), Name: "p" + string(rune('a'+i)), Connected: true}
		if err := r.Join(m); err != nil {
			b.Fatalf("join: %v", err)
		}
	}
	if err := r.Launch("u1"); err != nil {
		b.Fatalf("launch: %v", err)
	}
	m := r.players[0]
	b.ReportAllocs()
	for b.Loop() {
		v := r.viewForLocked(m)
		data, _ := json.Marshal(v)
		_ = data
	}
}

// Broadcast complet d'une salle 6 joueurs : N vues + N marshals — coût
// total par changement d'état, avant l'I/O websocket.
func BenchmarkBroadcastLocked(b *testing.B) {
	clk := &fakeClock{}
	s := &marshalSink{}
	opts := protocol.Options{
		Game:         game.Options{DicePerPlayer: 5, PacoJoker: true, CalzaEnabled: true},
		TimerSeconds: 30, MaxPlayers: 6, Spectators: true,
	}
	r := New("BENCH3", &Member{ID: "u1", Name: "alice"}, opts,
		rand.New(rand.NewSource(1)), s.emit, clk.after)
	for i := 2; i <= 6; i++ {
		m := &Member{ID: "u" + string(rune('a'+i)), Name: "p" + string(rune('a'+i)), Connected: true}
		if err := r.Join(m); err != nil {
			b.Fatalf("join: %v", err)
		}
	}
	if err := r.Launch("u1"); err != nil {
		b.Fatalf("launch: %v", err)
	}
	b.ReportAllocs()
	for b.Loop() {
		r.mu.Lock()
		r.broadcastLocked()
		r.mu.Unlock()
	}
	b.ReportMetric(float64(s.bytes)/float64(b.N)/1024.0, "KiB/broadcast")
}
