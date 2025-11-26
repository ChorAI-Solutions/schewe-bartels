.PHONY: help pull dev dev-n8n dev-down dev-restart dev-logs env-dev rebuild-dev prod prod-n8n prod-down prod-restart prod-logs env-prod rebuild-prod n8n-logs update-n8n lint type format studio migrate setup setup-dev setup-prod setup-env post-setup switch-remote bootstrap-remote reset-dev-db-volume clean-prod supabase-up supabase-down supabase-restart supabase-logs supabase-reset clean-docker

COMPOSE ?= docker compose
SUPABASE_COMPOSE ?= docker compose -f docker/supabase/docker-compose.yml
SUPABASE_ENV_FILE ?= docker/supabase/.env
DEV_PROFILES := --profile dev
PROD_PROFILES := --profile prod
N8N_PROFILE := --profile n8n
COMPOSE_PROJECT_NAME ?= $(notdir $(CURDIR))
DB_VOLUME := $(COMPOSE_PROJECT_NAME)_db-data
WEB_IMAGE := $(COMPOSE_PROJECT_NAME)-web
RESET_DB_VOLUME_ON_SETUP ?= true
REMOTE_NAME ?= origin
SETUP_SCRIPT ?= node scripts/setup-env.cjs
SERVER_CHECK_SCRIPT ?= bash scripts/check-server-tools.sh
GIT_BOOTSTRAP_SCRIPT ?= bash scripts/git-bootstrap.sh

help:
	@echo "Verfügbare Targets:"
	@echo "  make setup         - Alias für setup-dev (lokales Setup)"
	@echo "  make setup-dev     - Interaktiver Assistent mit dev-Defaults (setzt DB-Volume zurück, falls RESET_DB_VOLUME_ON_SETUP=true)"
	@echo "  make setup-prod    - Prüft Server-Abhängigkeiten & führt setup-env im prod-Scope aus"
	@echo "  make setup-env     - Setup ohne Scope (alle Variablen der Reihe nach)"
	@echo "  make post-setup    - Liest .env und setzt optional NEW_REMOTE_URL"
	@echo "  make dev           - Startet das dev-Profil ohne n8n (Hot-Reload, Mailpit, pgAdmin)"
	@echo "  make dev-n8n       - Startet dev + n8n Profile gemeinsam"
	@echo "  make dev-down      - Stoppt das dev-Profil"
	@echo "  make dev-restart   - Neustart aller Dienste im dev-Profil"
	@echo "  make dev-logs      - Folgt den Logs von web-dev"
	@echo "  make env-dev       - Recreated web-dev (z. B. nach .env-Anpassungen)"
	@echo "  make rebuild-dev   - Baut web-dev ohne Cache neu und startet das dev-Profil"
	@echo "  make prod          - Startet das prod-Profil mit --build"
	@echo "  make prod-n8n      - Startet prod + n8n Profile gemeinsam mit --build"
	@echo "  make prod-down     - Stoppt das prod-Profil"
	@echo "  make prod-restart  - Neustart aller Dienste im prod-Profil"
	@echo "  make prod-logs     - Folgt den Logs von web"
	@echo "  make env-prod      - Recreated web (z. B. nach .env-Anpassungen)"
	@echo "  make rebuild-prod  - Baut web ohne Cache neu und startet das prod-Profil"
	@echo "  make n8n-logs      - Folgt den Logs von n8n (falls gestartet)"
	@echo "  make update-n8n    - Holt das neueste n8n-Image und startet den Container neu"
	@echo "  make supabase-up   - Startet den Supabase-Stack (docker/supabase)"
	@echo "  make supabase-down - Stoppt den Supabase-Stack"
	@echo "  make supabase-restart - Restart Supabase-Services"
	@echo "  make supabase-logs - Zeigt Logs des Supabase-Stacks (konfigurierbar via SERVICE=name)"
	@echo "  make supabase-reset - Führt docker/supabase/reset.sh aus (löscht Daten!)"
	@echo "  make clean-docker  - Stoppt alle Container & entfernt Volumes (außer n8n-Daten)"
	@echo "  make switch-remote - Setzt das Git-Remote (Standard-Name: origin)"
	@echo "  make pull          - Führt git pull für den aktuellen Branch aus"
	@echo "  make lint          - Führt npm run lint im web-dev Container aus"
	@echo "  make type          - Führt npm run type-check im web-dev Container aus"
	@echo "  make format        - Führt npm run format im web-dev Container aus"
	@echo "  make studio        - Startet Prisma Studio im web-dev Container"
	@echo "  make migrate       - Führt prisma migrate deploy im web-dev Container aus"

pull:
	git pull

setup: setup-dev

setup-dev:
	@SETUP_ENV_SCOPE=dev $(SETUP_SCRIPT)
	@node scripts/setup-supabase-env.cjs
	@if [ "$(RESET_DB_VOLUME_ON_SETUP)" = "true" ]; then \
		$(MAKE) --no-print-directory reset-dev-db-volume; \
	else \
		echo "ℹ️  RESET_DB_VOLUME_ON_SETUP=false – behalte bestehendes db-Volume."; \
	fi
	@$(MAKE) --no-print-directory post-setup

setup-prod:
	@$(SERVER_CHECK_SCRIPT)
	@SETUP_ENV_SCOPE=prod $(SETUP_SCRIPT)
	@node scripts/setup-supabase-env.cjs
	@$(MAKE) --no-print-directory post-setup
	@$(MAKE) --no-print-directory clean-prod
	@echo "⬇️  Ziehe Basis-Images für prod + n8n …"
	@$(COMPOSE) $(PROD_PROFILES) $(N8N_PROFILE) pull n8n caddy
	@echo "🚀 Starte prod + n8n Stack frisch (inkl. Web-Rebuild) …"
	@$(COMPOSE) $(PROD_PROFILES) $(N8N_PROFILE) up -d --build --pull always

clean-prod:
	@echo "🧹 Stoppe laufende prod/n8n-Container (n8n-Daten bleiben erhalten)."
	@$(COMPOSE) $(PROD_PROFILES) $(N8N_PROFILE) down --remove-orphans || true
	@for volume in $(COMPOSE_PROJECT_NAME)_db-data $(COMPOSE_PROJECT_NAME)_caddy-data $(COMPOSE_PROJECT_NAME)_caddy-config; do \
		if docker volume inspect $$volume >/dev/null 2>&1; then \
			echo "   -> Entferne $$volume"; \
			docker volume rm $$volume >/dev/null; \
		fi; \
	done
	@if docker image inspect $(WEB_IMAGE) >/dev/null 2>&1; then \
		echo "🗑️  Entferne altes Web-Image $(WEB_IMAGE), damit beim nächsten Start garantiert frisch gebaut wird."; \
		docker image rm $(WEB_IMAGE) >/dev/null; \
	else \
		echo "ℹ️  Kein lokales Image $(WEB_IMAGE) gefunden – nichts zu tun."; \
	fi

setup-env:
	@node scripts/setup-env.cjs
	@node scripts/setup-supabase-env.cjs
	@$(MAKE) --no-print-directory post-setup

post-setup:
	@if [ -f .env ]; then \
		NEW_REMOTE_URL=$$(grep -E '^NEW_REMOTE_URL=' .env | head -n1 | cut -d= -f2-); \
		if [ -n "$$NEW_REMOTE_URL" ]; then \
			echo "➡️  NEW_REMOTE_URL erkannt: $$NEW_REMOTE_URL"; \
			$(MAKE) switch-remote NEW_REMOTE_URL="$$NEW_REMOTE_URL"; \
			$(MAKE) bootstrap-remote; \
		else \
			echo "ℹ️  Keine NEW_REMOTE_URL gesetzt – überspringe switch-remote."; \
		fi \
	else \
		echo "⚠️  .env nicht gefunden – überspringe switch-remote."; \
	fi

dev:
	$(COMPOSE) $(DEV_PROFILES) up -d

dev-n8n:
	$(COMPOSE) $(DEV_PROFILES) $(N8N_PROFILE) up -d

dev-down:
	$(COMPOSE) $(DEV_PROFILES) down

dev-restart:
	$(COMPOSE) $(DEV_PROFILES) restart

dev-logs:
	$(COMPOSE) logs -f web-dev

env-dev:
	$(COMPOSE) $(DEV_PROFILES) up -d --force-recreate web-dev

rebuild-dev:
	$(COMPOSE) $(DEV_PROFILES) build --no-cache web-dev
	$(COMPOSE) $(DEV_PROFILES) up -d

prod:
	$(COMPOSE) $(PROD_PROFILES) up -d --build

prod-n8n:
	$(COMPOSE) $(PROD_PROFILES) $(N8N_PROFILE) up -d --build

prod-all:
	@$(MAKE) --no-print-directory supabase-up
	$(COMPOSE) $(PROD_PROFILES) $(N8N_PROFILE) up -d --build

prod-down:
	$(COMPOSE) $(PROD_PROFILES) $(N8N_PROFILE) down
	@$(MAKE) --no-print-directory supabase-down

prod-restart:
	$(COMPOSE) $(PROD_PROFILES) restart

prod-logs:
	$(COMPOSE) logs -f web

env-prod:
	$(COMPOSE) $(PROD_PROFILES) up -d --force-recreate web

rebuild-prod:
	$(COMPOSE) $(PROD_PROFILES) build --no-cache web
	$(COMPOSE) $(PROD_PROFILES) up -d

n8n-logs:
	$(COMPOSE) logs -f n8n

update-n8n:
	$(COMPOSE) $(N8N_PROFILE) pull n8n
	$(COMPOSE) $(N8N_PROFILE) up -d n8n

supabase-up:
	@if [ ! -f $(SUPABASE_ENV_FILE) ]; then \
		echo "⚠️  $(SUPABASE_ENV_FILE) fehlt. Kopiere docker/supabase/.env.example und passe sie an."; \
		exit 1; \
	fi
	$(SUPABASE_COMPOSE) --env-file $(SUPABASE_ENV_FILE) up -d
	@bash scripts/ensure-app-db-user.sh
	@bash scripts/bootstrap-supabase-vector.sh

supabase-down:
	@if [ ! -f $(SUPABASE_ENV_FILE) ]; then \
		echo "⚠️  $(SUPABASE_ENV_FILE) fehlt. Kopiere docker/supabase/.env.example und passe sie an."; \
		exit 1; \
	fi
	$(SUPABASE_COMPOSE) --env-file $(SUPABASE_ENV_FILE) down

supabase-restart:
	@if [ ! -f $(SUPABASE_ENV_FILE) ]; then \
		echo "⚠️  $(SUPABASE_ENV_FILE) fehlt. Kopiere docker/supabase/.env.example und passe sie an."; \
		exit 1; \
	fi
	$(SUPABASE_COMPOSE) --env-file $(SUPABASE_ENV_FILE) restart

supabase-logs:
	@if [ ! -f $(SUPABASE_ENV_FILE) ]; then \
		echo "⚠️  $(SUPABASE_ENV_FILE) fehlt. Kopiere docker/supabase/.env.example und passe sie an."; \
		exit 1; \
	fi
	$(SUPABASE_COMPOSE) --env-file $(SUPABASE_ENV_FILE) logs -f $(SERVICE)

supabase-reset:
	bash docker/supabase/reset.sh

clean-docker:
	@echo "🛑 Stoppe alle Compose-Stacks (dev/prod/n8n) ohne Volumes zu löschen …"
	- $(COMPOSE) --profile dev down --remove-orphans >/dev/null 2>&1 || true
	- $(COMPOSE) --profile prod down --remove-orphans >/dev/null 2>&1 || true
	- $(COMPOSE) --profile n8n down --remove-orphans >/dev/null 2>&1 || true
	@echo "🛑 Stoppe Supabase-Stack und entferne seine internen Volumes …"
	@if [ -f $(SUPABASE_ENV_FILE) ]; then \
		$(SUPABASE_COMPOSE) --env-file $(SUPABASE_ENV_FILE) down -v --remove-orphans || true; \
	else \
		echo "ℹ️  $(SUPABASE_ENV_FILE) nicht gefunden – überspringe Supabase Cleanup."; \
	fi
	@echo "🧹 Entferne lokale Docker-Volumes (n8n-data bleibt erhalten) …"
	@for volume in $(COMPOSE_PROJECT_NAME)_db-data $(COMPOSE_PROJECT_NAME)_web-dev-node-modules $(COMPOSE_PROJECT_NAME)_caddy-data $(COMPOSE_PROJECT_NAME)_caddy-config; do \
		if docker volume inspect $$volume >/dev/null 2>&1; then \
			echo "   -> Entferne $$volume"; \
			docker volume rm $$volume >/dev/null; \
		else \
			echo "   -> Überspringe $$volume (nicht vorhanden)"; \
		fi; \
	done

lint:
	$(COMPOSE) exec web-dev npm run lint

type:
	$(COMPOSE) exec web-dev npm run type-check

format:
	$(COMPOSE) exec web-dev npm run format

studio:
	$(COMPOSE) exec web-dev npx prisma studio

migrate:
	$(COMPOSE) exec web-dev npx prisma migrate deploy --schema=prisma/schema.prisma

reset-dev-db-volume:
	@echo "⏹️  Stoppe dev-Stack (falls aktiv), damit das Volume frei wird."; \
	$(COMPOSE) $(DEV_PROFILES) down >/dev/null 2>&1 || true; \
	DB_VOLUME_NAME=$(DB_VOLUME); \
	if docker volume inspect $$DB_VOLUME_NAME >/dev/null 2>&1; then \
		echo "🧹 Entferne bestehendes Volume $$DB_VOLUME_NAME für ein frisches dev-Setup."; \
		docker volume rm $$DB_VOLUME_NAME >/dev/null; \
	else \
		echo "ℹ️  Kein Volume $$DB_VOLUME_NAME gefunden – nichts zu tun."; \
	fi

switch-remote:
	@[ -n "$(strip $(NEW_REMOTE_URL))" ] || (echo "Bitte NEW_REMOTE_URL angeben, z. B. make switch-remote NEW_REMOTE_URL=git@github.com:user/repo.git"; exit 1)
	@if git remote | grep -qx "$(REMOTE_NAME)"; then \
		echo "Entferne bestehendes Remote '$(REMOTE_NAME)'"; \
		git remote remove $(REMOTE_NAME); \
	fi
	@git remote add $(REMOTE_NAME) $(NEW_REMOTE_URL)
	@echo "Remote '$(REMOTE_NAME)' zeigt jetzt auf $(NEW_REMOTE_URL)"
	@git remote -v

bootstrap-remote:
	@$(GIT_BOOTSTRAP_SCRIPT) $(REMOTE_NAME)

