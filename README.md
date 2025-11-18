## Projekt-Template – Next.js + Prisma + n8n

Dieses Repository ist ein Ausgangspunkt für Projekte mit Next.js (App Router), Postgres/Prisma, wahlweise n8n sowie Hilfsdiensten wie Mailpit und pgAdmin. Alle Komponenten werden über Docker Compose gesteuert und lassen sich sowohl lokal (Development) als auch auf einem Server (Production) betreiben.

---

## Quickstart

```bash
make setup        # erstellt .env per dev-Defaults
docker compose --profile dev up -d
```

---

## 1. Voraussetzungen

- Docker Desktop (Windows/macOS) oder Docker Engine (Linux)
- Git und eine Shell (PowerShell, WSL, Bash, zsh)
- Optional: Node.js 20 LTS, falls du außerhalb von Docker entwickeln willst

---

## 2. Konfiguration (`.env`)

1. (Nur frische Linux-Server) Make sicherstellen:
   ```bash
   sudo apt update
   sudo apt install build-essential   # enthält make
   ```
2. `.env` per Setup-Skript erzeugen:
   ```bash
   make setup        # dev
   make setup-prod   # prod
   # oder direkt:
   node scripts/setup-env.cjs --scope prod
   ```
   Das Skript liest `env.template`, berücksichtigt die `# @meta { ... }` Blöcke und fragt nur Variablen ab, deren `scopes` (`dev` oder `prod`) zum gewünschten Profil passen. Enter übernimmt den Default/Placeholder, ein einzelner Punkt `.` setzt den Wert leer. Nach dem Setup wird optional automatisch `NEW_REMOTE_URL` aus der `.env` gezogen und via `make switch-remote` gesetzt. Bei `make setup-prod` wird zusätzlich `scripts/check-server-tools.sh` aufgerufen: dieses prüft Docker, Docker Compose, Git sowie Node.js/npm und versucht fehlende Pakete (apt/brew) zu installieren. Auf Servern deshalb mit passenden Rechten (sudo) ausführen.
3. Die wichtigsten Variablen im Überblick:
   - **Allgemein**: `NODE_ENV`, `NEXT_PUBLIC_SITE_URL` (öffentliche URL des Frontends), `SITE_DOMAIN` (Domain ohne Schema, für TLS), `ADMIN_TOKEN`, `COMPOSE_PROFILES` (z. B. `dev` lokal oder `prod,n8n` auf dem Server), optional `AUTH_DISABLED=true` nur lokal.
   - **TLS**: `ACME_EMAIL` (Empfänger für Let's-Encrypt-Benachrichtigungen).
   - **Datenbank**: `POSTGRES_USER`, `POSTGRES_DB`, `POSTGRES_PASSWORD`, `DATABASE_URL` (muss zu den obigen Werten passen).
   - **n8n** (nur wenn genutzt): `N8N_HOST`, `N8N_DOMAIN` (für TLS), `N8N_PROTOCOL`, optional `N8N_WEBHOOK_URL`, Basic-Auth (`N8N_BASIC_AUTH_*`) und SMTP-Konfiguration (`N8N_SMTP_*`).
   - **PgAdmin/Mailpit**: Zugangsdaten und SMTP-Port kannst du bei Bedarf anpassen.
3. Production-Domains direkt eintragen (z. B. `https://ai-test.dakatos.online`).
4. Für lokale Entwicklung kannst du `NEXT_PUBLIC_SITE_URL=http://localhost:3000` und `AUTH_DISABLED=true` setzen.
5. Eigene Variablen ergänzen: Im `env.template` oberhalb jeder Variable einen `# @meta` Block mit `description`, `scopes` und optional `defaults` pro Scope hinzufügen – das Setup-Skript erkennt diese automatisch.

Tipp: Du kannst mehrere `.env`-Dateien verwalten (z. B. `.env.dev`, `.env.prod`) und vor dem Start die passende Datei nach `.env` kopieren oder via `env_file:` in separaten Compose-Overrides referenzieren.

---

## 3. Docker Compose Profile & Dienste

| Profil | Dienste                                     | Beschreibung |
|--------|----------------------------------------------|--------------|
| `dev`  | `db`, `web-dev`, `mailpit`, `pgadmin`        | Lokale Entwicklung mit Hot-Reload, Mailpit & pgAdmin |
| `prod` | `db`, `web`, `caddy`                         | Produktionsbetrieb mit automatischem HTTPS (Caddy) |
| `n8n`  | `n8n`                                        | Optionaler Start von n8n (kann mit jedem Profil kombiniert werden) |

Standardmäßig laufen alle Dienste nur auf dem internen Docker-Netzwerk bzw. auf `127.0.0.1`. Für HTTP(S)-Zugriff in Produktion empfiehlt sich ein Reverse Proxy (z. B. nginx; siehe unten).

### Setup-Befehle

- `make setup` / `make setup-dev`: erstellt `.env` mit den dev-Defaults.
- `make setup-prod`: generiert `.env` für produktive Werte (vorher `sudo apt install build-essential`, falls `make` noch fehlt).
- `make setup-env scope=prod`: frei wählbarer Scope (`dev` oder `prod`), auch via `SETUP_ENV_SCOPE=prod make setup-env`. Bei Scope `prod` läuft ebenfalls der Dependency-Check (`scripts/check-server-tools.sh`).
- Nach jedem Setup läuft automatisch `make post-setup`. Falls in `.env` eine `NEW_REMOTE_URL` gesetzt wurde, wird das Git-Remote `origin` darauf aktualisiert (`switch-remote`). Leer lassen, wenn nichts umgehängt werden soll.

### Dienste & Ports

- `web` / `web-dev`: Next.js Applikation (Port 3000)
- `db`: Postgres 16 (intern erreichbar)
- `n8n`: n8n Automation (Port 5678, optional)
- `pgadmin`: PgAdmin 4 (Port 5050, nur dev)
- `mailpit`: Mail UI + SMTP Fake-Server (Ports 8025/1025, nur dev)

---

## 4. Lokale Entwicklung (Docker)

### Ohne n8n (schnellster Start)

```bash
docker compose --profile dev up -d
```

- Öffne `http://localhost:3000`
- Mail UI: `http://localhost:8025`
- PgAdmin: `http://localhost:5050`

### Mit n8n

```bash
docker compose \
  --profile dev \
  --profile n8n \
  up -d
```

- n8n läuft auf `http://localhost:5678` (Basic Auth aus `.env`)
- Webhooks können über `http://localhost:5678/webhook/<pfad>` getestet werden

### Stoppen & Aufräumen

```bash
docker compose --profile dev down
```

> Wenn du mehrere Profile gestartet hast, wiederhole den Befehl mit denselben Profilen oder verwende `docker compose down` ohne Profile, um alles zu stoppen.

### Nützliche Kommandos

- Logs ansehen: `docker compose logs -f web-dev`
- Prisma Studio: `docker compose exec web-dev npx prisma studio`
- Tests / Linting (innerhalb des Containers): `docker compose exec web-dev npm run lint`

---

## 5. Produktionsbetrieb (z. B. Ubuntu Server)

### Vorbereitung

1. System aktualisieren, Docker & Docker Compose Plugin installieren.
2. Sicherstellen, dass kein anderer Dienst Ports 80/443 blockiert (z. B. nginx stoppen/disable).
3. Repository nach `/var/www/<projekt>` klonen.
4. `.env` mit Produktionswerten befüllen:
   - `NODE_ENV=production`
   - `NEXT_PUBLIC_SITE_URL=https://<deine-domain>`
   - `SITE_DOMAIN=<deine-domain>`
   - `COMPOSE_PROFILES=prod` (oder `prod,n8n`, wenn n8n mitlaufen soll)
   - `ACME_EMAIL=<deine-mail>`
   - `N8N_HOST=<deine-n8n-domain>` & `N8N_DOMAIN=<deine-n8n-domain>` (falls n8n öffentlich erreichbar sein soll)
   - `AUTH_DISABLED=false`
5. Optionale Dienste (Mailpit/PgAdmin) in Produktion weglassen.

### Start ohne n8n

```bash
docker compose --profile prod up -d --build
```

- Caddy stellt automatisch Zertifikate über Let's Encrypt aus und leitet Port 80/443 auf die internen Dienste weiter.

### Start mit n8n

```bash
docker compose \
  --profile prod \
  --profile n8n \
  up -d --build
```

- Caddy erzeugt zusätzlich ein Zertifikat für `N8N_DOMAIN` und proxyt Anfragen an den n8n-Container.

### HTTPS-Automatisierung (Caddy)

- Die Caddy-Instanz im `prod`-Profil übernimmt TLS automatisch. Stelle sicher, dass `SITE_DOMAIN`, `ACME_EMAIL` (und optional `N8N_DOMAIN`) gesetzt sind und die DNS-Einträge auf den Server zeigen.
- Zertifikate werden in den Volumes `caddy-data` / `caddy-config` gespeichert und automatisch erneuert.

### Healthchecks & Monitoring

- App-Health: `curl -k https://<domain>/api/health`
- n8n Basic Auth Zugang testen: `curl -I -u user:pass https://n8n-<domain>`
- Docker Status: `docker compose ps`
- Logs: `docker compose logs --tail=100 web`

---

## 6. Optional: Entwicklung ohne Docker

1. Postgres lokal installieren und `DATABASE_URL` anpassen.
2. Dependencies installieren:
   ```bash
   npm install
   npx prisma generate
   npm run dev
   ```
3. n8n separat installieren oder gehosteten Dienst nutzen.

---

## 7. Häufige Aufgaben

- **Migrationen erzeugen**: `docker compose exec web-dev npx prisma migrate dev --name <beschreibung>`
- **Migrationen anwenden (Prod)**: beim Start automatisch, manuell via `docker compose exec web npx prisma migrate deploy`
- **Admin-Token testen**:
  ```bash
  curl -H "X-Admin-Token: $ADMIN_TOKEN" https://<domain>/api/admin/ping
  ```
- **Mailpit öffnen**: `http://localhost:8025`
- **PgAdmin öffnen**: `http://localhost:5050` (Login mit `PGADMIN_DEFAULT_*`)

---

## 8. Sicherheit & Best Practices

- `.env` niemals committen oder weitergeben.
- Starke Passwörter/Tokens wählen und regelmäßig rotieren.
- In Produktion `AUTH_DISABLED=false` lassen.
- Firewalls so konfigurieren, dass nur nötige Ports offen sind (z. B. 80/443 für Web, 22 für SSH).
- Backups für Postgres einplanen (`docker compose exec db pg_dump ...`).

---

Dieses README dient als Template: passe Profile, Dienste, Domains und Automatisierungen nach Bedarf an. Wenn du weitere Services hinzufügst, ergänze deren Profile/TLS-Konfiguration entsprechend.
