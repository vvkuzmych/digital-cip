package metrics

import (
	"fmt"
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	Processed = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "worker_messages_processed_total",
		Help: "Messages processed by the worker",
	}, []string{"stage"})

	Failed = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "worker_messages_failed_total",
		Help: "Messages that failed processing",
	}, []string{"stage", "reason"})

	Retried = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "worker_messages_retried_total",
		Help: "Messages retried via DLX",
	}, []string{"stage"})

	InFlight = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "worker_in_flight",
		Help: "Messages currently being processed",
	}, []string{"stage"})

	Duration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "worker_processing_seconds",
		Help:    "Time spent processing a single message",
		Buckets: prometheus.DefBuckets,
	}, []string{"stage"})
)

func Serve(port int) {
	http.Handle("/metrics", promhttp.Handler())
	go func() {
		_ = http.ListenAndServe(fmt.Sprintf(":%d", port), nil)
	}()
}
