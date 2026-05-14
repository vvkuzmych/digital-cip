package log

import (
	"log/slog"
	"os"
	"strings"
)

var L *slog.Logger

func Init(level, service string) {
	var lvl slog.Level
	switch strings.ToLower(level) {
	case "debug":
		lvl = slog.LevelDebug
	case "warn", "warning":
		lvl = slog.LevelWarn
	case "error":
		lvl = slog.LevelError
	default:
		lvl = slog.LevelInfo
	}
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: lvl})
	L = slog.New(handler).With("service", service)
	slog.SetDefault(L)
}
