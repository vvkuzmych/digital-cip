package config

import (
	"os"
	"strconv"
)

type Config struct {
	ServiceName   string
	RabbitMQURL   string
	QueueIn       string
	RoutingKeyOut string
	Exchange      string
	RetryExchange string
	DLXExchange   string

	PGHost     string
	PGPort     int
	PGUser     string
	PGPassword string
	PGDB       string

	ChunkSize    int
	ChunkOverlap int

	MaxRetries  int
	MetricsPort int
	Concurrency int
	LogLevel    string
}

func Load() Config {
	return Config{
		ServiceName:   "chunker-worker",
		RabbitMQURL:   getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672"),
		QueueIn:       "ingest.chunk",
		RoutingKeyOut: "ingest.embed",
		Exchange:      "ingest",
		RetryExchange: "ingest.retry",
		DLXExchange:   "ingest.dlx",

		PGHost:     getenv("POSTGRES_HOST", "postgres"),
		PGPort:     getenvInt("POSTGRES_PORT", 5432),
		PGUser:     getenv("POSTGRES_USER", "cip"),
		PGPassword: getenv("POSTGRES_PASSWORD", "cip"),
		PGDB:       getenv("POSTGRES_DB", "cip_development"),

		ChunkSize:    getenvInt("CHUNK_SIZE", 800),
		ChunkOverlap: getenvInt("CHUNK_OVERLAP", 120),

		MaxRetries:  getenvInt("MAX_RETRIES", 5),
		MetricsPort: getenvInt("METRICS_PORT", 9101),
		Concurrency: getenvInt("WORKER_CONCURRENCY", 4),
		LogLevel:    getenv("LOG_LEVEL", "info"),
	}
}

func getenv(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

func getenvInt(key string, def int) int {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
