package amqp

import (
	"context"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/digital-cip/chunker/internal/config"
	"github.com/digital-cip/chunker/internal/log"
)

type Client struct {
	Conn *amqp.Connection
	Ch   *amqp.Channel
}

func Dial(ctx context.Context, cfg config.Config) (*Client, error) {
	var (
		conn *amqp.Connection
		err  error
	)
	for i := 0; i < 30; i++ {
		conn, err = amqp.Dial(cfg.RabbitMQURL)
		if err == nil {
			break
		}
		log.L.Warn("amqp.dial.retry", "error", err.Error(), "attempt", i+1)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
	if err != nil {
		return nil, err
	}
	ch, err := conn.Channel()
	if err != nil {
		return nil, err
	}
	if err := ch.Qos(cfg.Concurrency, 0, false); err != nil {
		return nil, err
	}
	return &Client{Conn: conn, Ch: ch}, nil
}

func (c *Client) Close() {
	if c.Ch != nil {
		_ = c.Ch.Close()
	}
	if c.Conn != nil {
		_ = c.Conn.Close()
	}
}
