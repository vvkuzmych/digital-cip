SHELL := /bin/bash
DC := docker compose

.PHONY: help up down restart build logs ps doctor urls bundle migrate seed psql redis rabbit-purge \
        smoke api-shell test lint clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack
	$(DC) up -d --build

down: ## Stop and remove containers
	$(DC) down

restart: ## Restart everything
	$(DC) restart

build: ## Rebuild images
	$(DC) build

logs: ## Tail logs for SERVICE=name (default: api)
	$(DC) logs -f --tail=200 $(or $(SERVICE),api)

ps: ## List containers
	$(DC) ps

doctor: ## Compose status + curl API health (uses API_HTTP_PORT from .env)
	@./scripts/doctor.sh

urls: ## Print local URLs (defaults: API 3040, Grafana 3010)
	@bash -c 'set -a; [[ -f .env ]] && . ./.env; set +a; \
	  A=$${API_HTTP_PORT:-3040}; G=$${GRAFANA_HTTP_PORT:-3010}; \
	  echo "Rails:     http://localhost:$$A/healthz"; \
	  echo "Grafana:   http://localhost:$$G/"; \
	  echo "RabbitMQ:  http://localhost:15672/"; \
	  echo "MinIO UI:  http://localhost:9001/"'

bundle: ## Reinstall api gems in the bundle volume (after Gemfile.lock change)
	$(DC) run --rm --no-deps api bundle install

migrate: ## Run Rails migrations
	$(DC) exec api bin/rails db:create db:migrate

seed: ## Seed database
	$(DC) exec api bin/rails db:seed

psql: ## Open a psql shell against the app DB
	$(DC) exec postgres psql -U $${POSTGRES_USER:-cip} -d $${POSTGRES_DB:-cip_development}

redis: ## Open a redis-cli shell
	$(DC) exec redis redis-cli

rabbit-purge: ## Purge all ingest.* queues
	$(DC) exec rabbitmq rabbitmqctl list_queues -p / name | grep '^ingest' | \
	  xargs -I{} $(DC) exec -T rabbitmq rabbitmqctl purge_queue {} || true

smoke: ## Upload sample file and follow it through the pipeline
	./scripts/smoke.sh

api-shell: ## Rails console
	$(DC) exec api bin/rails console

test: ## Run API tests
	$(DC) exec api bundle exec rspec

lint: ## Rubocop on the API
	$(DC) exec api bundle exec rubocop

clean: ## Remove containers AND volumes (destructive)
	$(DC) down -v
