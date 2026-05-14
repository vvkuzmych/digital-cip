package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/digital-cip/chunker/internal/amqp"
	"github.com/digital-cip/chunker/internal/config"
	"github.com/digital-cip/chunker/internal/db"
	"github.com/digital-cip/chunker/internal/log"
	"github.com/digital-cip/chunker/internal/metrics"
	"github.com/digital-cip/chunker/internal/worker"
)

func main() {
	cfg := config.Load()
	log.Init(cfg.LogLevel, cfg.ServiceName)

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()

	metrics.Serve(cfg.MetricsPort)
	log.L.Info("worker.booted", "metrics_port", cfg.MetricsPort)

	pool, err := db.New(ctx, cfg)
	if err != nil {
		log.L.Error("db.connect.error", "error", err.Error())
		os.Exit(1)
	}
	defer pool.Close()

	cli, err := amqp.Dial(ctx, cfg)
	if err != nil {
		log.L.Error("amqp.dial.error", "error", err.Error())
		os.Exit(1)
	}
	defer cli.Close()

	w := &worker.Worker{Cfg: cfg, DB: pool, AMQP: cli}
	if err := worker.Run(ctx, w); err != nil {
		log.L.Error("worker.run.error", "error", err.Error())
		os.Exit(1)
	}
}
