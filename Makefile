SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

COMPOSE ?= docker compose
BACKEND_DIR := convert-invert
FRONTEND_DIR := convert-invert-frontend
ROOT_ENV := .env
DOWNLOADS_DIR ?= downloads
REQUIRED_ENV := POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB DATABASE_URL API_KEY USER_NAME USER_PASSWORD CLIENT_ID CLIENT_SECRET

.PHONY: help env-check up down logs ps downloads copy-downloads api frontend backend check test clippy fmt fmt-check install-frontend

help:
	@printf '%s\n' 'Common commands:'
	@printf '  %-18s %s\n' 'make env-check' 'Validate the root .env used by Docker Compose'
	@printf '  %-18s %s\n' 'make up' 'Start the full Docker Compose stack'
	@printf '  %-18s %s\n' 'make down' 'Stop the Docker Compose stack'
	@printf '  %-18s %s\n' 'make full-down' 'Stop the Docker Compose stack and volumes'
	@printf '  %-18s %s\n' 'make logs' 'Follow Docker Compose logs'
	@printf '  %-18s %s\n' 'make ps' 'Show Docker Compose service status'
	@printf '  %-18s %s\n' 'make downloads' 'List downloaded files in the API container'
	@printf '  %-18s %s\n' 'make copy-downloads' 'Copy downloads from the API container into ./downloads'
	@printf '  %-18s %s\n' 'make api' 'Run the Rust HTTP API locally'
	@printf '  %-18s %s\n' 'make backend' 'Run the Rust core CLI locally'
	@printf '  %-18s %s\n' 'make frontend' 'Run the frontend dev server locally'
	@printf '  %-18s %s\n' 'make check' 'Run Rust check, tests, clippy, and fmt check'
	@printf '  %-18s %s\n' 'make analyzed-logs' 'Run analyze-logs binary on the current session logs'

env-check:
	@if [[ ! -f "$(ROOT_ENV)" ]]; then \
		printf '%s\n' "Missing $(ROOT_ENV). Create it with:"; \
		printf '%s\n' "  cp .env.example .env"; \
		printf '%s\n' "Then edit .env and fill in Soulseek, Spotify, and secret values."; \
		exit 1; \
	fi
	@missing=0; \
	for key in $(REQUIRED_ENV); do \
		value=$$(grep -E "^$$key=" "$(ROOT_ENV)" | tail -n 1 | cut -d= -f2-); \
		if [[ -z "$$value" || "$$value" == CHANGE_ME* || "$$value" == your-* ]]; then \
			printf 'Invalid or missing %-18s in %s\n' "$$key" "$(ROOT_ENV)"; \
			missing=1; \
		fi; \
	done; \
	if [[ "$$missing" -ne 0 ]]; then \
		printf '%s\n' "Fill the values above before running Docker Compose."; \
		exit 1; \
	fi

up: env-check
	$(COMPOSE) up --build

down:
	$(COMPOSE) down
full-down:
	$(COMPOSE) down -v

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

downloads:
	python3 scripts/list_downloads.py $(ARGS)

copy-downloads:
	mkdir -p $(DOWNLOADS_DIR)
	docker cp convert-invert-site-api-1:/downloads/. $(DOWNLOADS_DIR)/

api:
	cd $(BACKEND_DIR) && cargo run --bin trigger_server

backend:
	cd $(BACKEND_DIR) && cargo run

frontend:
	cd $(FRONTEND_DIR) && npm run dev

install-frontend:
	cd $(FRONTEND_DIR) && npm install

check: fmt-check test clippy

test:
	cd $(BACKEND_DIR) && cargo test --bins --lib

clippy:
	cd $(BACKEND_DIR) && cargo clippy --bins --lib -- -D warnings

fmt:
	cd $(BACKEND_DIR) && cargo fmt

fmt-check:
	cd $(BACKEND_DIR) && cargo fmt --check
analyze-run:
	cd $(BACKEND_DIR) && docker compose logs > worker-logs.log && cargo run --bin analyze_run_log -- worker-logs.log | tee ../analyzed-logs.txt && cd -
