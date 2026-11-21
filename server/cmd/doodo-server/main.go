// doodo-server : serveur de jeu Doodo (WebSocket + hub de rooms).
// Dev : go run ./cmd/doodo-server — écoute sur :8080 (ws://localhost:8080/ws).
package main

import (
	"log/slog"
	"net/http"
	"os"

	"doodo/internal/hub"
)

func main() {
	// DOODO_LOG_LEVEL=debug affiche les pings keep-alive (#29) et autres
	// détails — Info par défaut pour garder les logs exploitables.
	level := slog.LevelInfo
	if os.Getenv("DOODO_LOG_LEVEL") == "debug" {
		level = slog.LevelDebug
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr,
		&slog.HandlerOptions{Level: level})))
	addr := os.Getenv("DOODO_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	h := hub.New()
	slog.Info("doodo-server", "addr", addr)
	if err := http.ListenAndServe(addr, h.Handler()); err != nil {
		slog.Error("serveur arrêté", "err", err)
		os.Exit(1)
	}
}
