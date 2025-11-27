## Projekt-Template – Next.js + Prisma + Supabase + n8n

Dieses Repo liefert eine einsatzbereite Stack-Vorlage:

- **Next.js App Router** mit Prisma & Tailwind
- **Supabase Self-Hosting** (Postgres, Auth, Storage, Realtime, Studio, Kong)
- **n8n** Automations-Server
- **Caddy** als Reverse Proxy mit automatischem TLS
- Hilfsdienste für Development: Mailpit (Fake SMTP + UI)

Alle Bausteine werden über Makefile-Targets gestartet. Diese Anleitung führt dich Schritt für Schritt durch Dev- und Prod-Setup und erklärt, wie du n8n mit Supabase verbindest.

---

## Inhaltsverzeichnis

- [1. Voraussetzungen](#1-voraussetzungen)
- [2. Dev-Setup in 5 Schritten](#2-dev-setup-in-5-schritten)
- [3. Prod-Setup (Server)](#3-prod-setup-server)
- [4. Dienste & Ports (Überblick)](#4-dienste--ports-überblick)
- [5. Supabase & Credentials](#5-supabase--credentials)
  - [5.1 Internes n8n (Container aus diesem Projekt)](#61-internes-n8n-container-aus-diesem-projekt)
  - [5.2 Externes n8n (anderer Server oder Cloud)](#62-externes-n8n-anderer-server-oder-cloud)
  - [5.3 Direkter Postgres-Zugriff (n8n DB-Node, Prisma, BI-Tools)](#63-direkter-postgres-zugriff-n8n-db-node-prisma-bi-tools)
  - [5.4 Vector Store & RAG-Setup](#54-vector-store--rag-setup)
- [6. n8n ↔ Supabase (Credentials)](#6-n8n--supabase-credentials)
- [7. Häufige Workflows](#7-häufige-workflows)
- [8. Sicherheit & Best Practices](#8-sicherheit--best-practices)
- [9. Fresh-Install & Smoke-Test Checkliste](#9-fresh-install--smoke-test-checkliste)

---

## 1. Voraussetzungen

- Docker Desktop (macOS/Windows) oder Docker Engine + Compose Plugin (Linux)
- Git und eine Shell (zsh/Bash/PowerShell)
- Node.js 20.x + npm (das Setup-Skript installiert/aktualisiert diese Version automatisch, falls nötig)

Auf frischen Linux-Servern zusätzlich:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin make git
```

---

## 2. Dev-Setup in 5 Schritten

1. **Repo klonen & wechseln**
   ```bash
   git clone <repo> /var/www/ai-test
   cd /var/www/ai-test
   ```

2. **Environment-Dateien anlegen**
   ```bash
   make setup            # Scope=dev
   ```
   - Gibt es bereits eine `.env`, fragt das Skript, ob die bestehenden Werte genutzt werden sollen.
   - Das Setup prüft Git, Docker sowie Node.js und installiert bei Bedarf automatisch Node.js 20.x (NodeSource auf Linux bzw. Homebrew auf macOS).
   - Im Anschluss wird automatisch `docker/supabase/.env` erstellt/aktualisiert.

3. **Supabase-Stack starten**
   ```bash
   make supabase-up
   ```
   -> Startet Postgres, Kong, Auth, Realtime, Studio etc. im Hintergrund.

4. **Web + Dev-Tools hochfahren**
   ```bash
   make dev          # web-dev + Mailpit
   # oder: make dev-n8n für zusätzliches n8n
   ```

5. **Verifizieren**
   - App: <http://localhost:3000>
   - Mailpit: <http://localhost:8025>
   - n8n (optional): <http://localhost:5678> (Basic Auth aus `.env`)

Stoppen & Aufräumen: `docker compose --profile dev --profile n8n down`

---

## 3. Prod-Setup (Server)

1. **Repo bereitstellen & vorbereiten**
   ```bash
   git clone <repo> /var/www/ai-test
   cd /var/www/ai-test
   ```

2. **Produktionswerte eintragen**
   ```bash
   make setup-prod
   ```
   - Das Skript prüft automatisch Docker/Git/Node-Versionen.
   - Wenn eine `.env` existiert, kannst du sie beibehalten (`j`) oder neu ausfüllen.
   - Wichtige Variablen: `NEXT_PUBLIC_SITE_URL`, `SITE_DOMAIN`, `ACME_EMAIL`, `SUPABASE_DOMAIN`, `N8N_DOMAIN`, `POSTGRES_*`, `ADMIN_TOKEN`, `N8N_BASIC_AUTH_*`.
   - `SUPABASE_KONG_HOST` **nur** mit Hostnamen/IP füllen (z. B. `host.docker.internal`), keine komplette URL.

3. **Alles mit einem Befehl starten**
   ```bash
   make prod-all     # Supabase + Web + Caddy + n8n
   ```
   - Caddy holt automatisch Let's-Encrypt-Zertifikate für `SITE_DOMAIN`, `N8N_DOMAIN` und `SUPABASE_DOMAIN`.
   - `make prod-n8n` startet nur Web+Caddy+n8n (ohne Supabase).

4. **Status prüfen**
   ```bash
   docker compose ps
   curl -Ik https://<SITE_DOMAIN>/api/health
   curl -Ik https://sb-<...>/   # erwartet 401 mit "Server: kong"
   ```

5. **Stoppen**
   ```bash
   make prod-down     # web/caddy/n8n + supabase werden sauber beendet
   ```

Weitere nützliche Befehle:

| Befehl                | Zweck                                                      |
|-----------------------|------------------------------------------------------------|
| `make supabase-up`    | Nur Supabase-Stack starten                                 |
| `make supabase-down`  | Supabase stoppen                                           |
| `make supabase-logs`  | Logs eines Supabase-Dienstes (`SERVICE=kong ...`)          |
| `make clean-docker`   | Alle Volumes (außer n8n-Daten) entfernen                   |

---

## 4. Dienste & Ports (Überblick)

| Profil / Stack | Dienste (Ports)                                   | Hinweise |
|----------------|----------------------------------------------------|---------|
| `dev`          | `web-dev` (3000), `mailpit` (8025/1025) | Hot-Reload + lokale Tools |
| `prod`         | `web`, `caddy` (80/443)                            | Öffentliche App mit TLS |
| `n8n`          | `n8n` (5678)                                       | Kann zu jedem Profil kombiniert werden |
| `supabase`     | `kong` (8000), `auth`, `rest`, `storage`, `studio`, `db`, … | Separater Compose-Stack |

Alle Container befinden sich im internen Docker-Netzwerk; externe Zugriffe laufen über Caddy.

---

## 5. Supabase & Credentials

- `make setup` / `make setup-prod` synchronisiert automatisch die Werte aus `.env` nach `docker/supabase/.env` (Ports, DB-Name, Passwörter).
- `make setup-prod` erweitert den Dialog um die Supabase-spezifischen Secrets und erzeugt im Anschluss frische JWT-basierte Keys (`JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`), sofern noch Platzhalter aktiv sind.
- Nach dem Setup unbedingt sensible Defaults ersetzen:
  - `ANON_KEY`, `SERVICE_ROLE_KEY`
  - `JWT_SECRET`, `VAULT_ENC_KEY`, `PG_META_CRYPTO_KEY`
  - `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` (Basic Auth für Kong/Supabase Studio)
- Zugriff:
  - Lokal (ohne TLS): `http://localhost:8000`
  - Prod (über Caddy + Zertifikat): `https://<SUPABASE_DOMAIN>`
  - Interne Verbindungen (Container → DB): `host.docker.internal:${POSTGRES_PORT}`
  - Direkter Externzugriff: `https://<SUPABASE_DOMAIN>:${POSTGRES_DIRECT_PORT}` → `postgresql://<APP_DB_USER>:<APP_DB_PASSWORD>@<SUPABASE_DOMAIN>:<POSTGRES_DIRECT_PORT>/<APP_DB_NAME>`  
    `scripts/ensure-app-db-user.sh` wird nach `make supabase-up` automatisch ausgeführt und legt den in `.env` definierten App-Benutzer inklusive Rechte an (Standard: `APP_DB_USER=shorty`, Port `54324`). Dieser Nutzer wird für n8n/Prisma verwendet.

Backups:

```bash
docker compose -f docker/supabase/docker-compose.yml \
  --env-file docker/supabase/.env exec db \
  pg_dump -U postgres aiTestProdDB > backup.sql
```

---

### 5.4 Vector Store & RAG-Setup

Damit der Supabase-Stack sofort als Vektor-Datenbank funktioniert (n8n „Supabase Vector Store“-Node, `match_documents`-RPC, etc.), passiert beim ersten `make supabase-up` automatisch Folgendes:

1. `scripts/ensure-app-db-user.sh` legt den App-User (`APP_DB_USER`) an und vergibt Rechte.
2. Direkt danach sorgt `scripts/bootstrap-supabase-vector.sh` für alle AI-spezifischen Bausteine:
   - erzwingt das Schema `extensions` inklusive `vector`- und `uuid-ossp`-Extension,
   - erstellt (idempotent) die Tabelle `public.documents_pg` samt IVFFlat-Index,
   - spielt `supase-configs/createMatchFunction.sql` ein (`match_documents` mit optionalem JSONB-Filter),
   - setzt `search_path` für `anon`, `authenticated` und `service_role` auf `public, extensions`,
   - vergibt alle nötigen Grants (Schema `extensions`, Tabelle/Sequence `documents_pg`).
3. Der Vorgang ist wiederholbar: `bash scripts/bootstrap-supabase-vector.sh`.
4. Anpassungen am Retrieval (z. B. Schwellenwert, Filterlogik) nimmst du ausschließlich in `supase-configs/createMatchFunction.sql` vor und führst anschließend `make supabase-up` (oder das Script) erneut aus.
5. Smoke-Test (nachdem `make supabase-up` einmal durchgelaufen ist):
   ```bash
   EMBED=$(docker compose -f docker/supabase/docker-compose.yml \
     --env-file docker/supabase/.env exec -T db \
     psql -U supabase_admin -d ${APP_DB_NAME:-aiTestProdDB} -Atqc \
     "select embedding::text from documents_pg limit 1;")
   curl -sS -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H "Content-Type: application/json" \
        -X POST http://localhost:8000/rest/v1/rpc/match_documents \
        -d "{\"query_embedding\":$EMBED,\"match_count\":2,\"filter\":{}}"
   ```
   Wenn zwei Treffer zurückkommen, ist Supabase für RAG bereit – genau so greift n8n später auch zu.

💡 Wichtig: Ein frisch geklonter Server benötigt lediglich `make setup` / `make setup-prod` **und anschließend einmal `make supabase-up`**, damit alle Automatisierungen ihre Arbeit erledigen. Danach funktionieren Storage-Buckets, `match_documents` und n8n-Vector-Workflows ohne manuelle Schritte.

---

## 6. n8n ↔ Supabase (Credentials)

### 6.1 Internes n8n (Container aus diesem Projekt)

| Feld                     | Wert                                                                 |
|--------------------------|----------------------------------------------------------------------|
| **Host**                 | `https://sb-ai-test.dakatos.online` (oder deine Supabase-Domain)     |
| **Service Role Secret**  | `SERVICE_ROLE_KEY` aus `docker/supabase/.env`                        |
| **Allowed Domains**      | `All` oder z. B. `https://n8n-ai-test.dakatos.online`                 |
| **Basic Auth für n8n**   | `N8N_BASIC_AUTH_USER` / `N8N_BASIC_AUTH_PASSWORD` aus `.env`         |

ℹ️ Der Supabase-Node von n8n erwartet immer die öffentliche REST-URL (HTTPS). Der Zugriff über `http://host.docker.internal:8000` funktioniert nur mit generischen HTTP- oder Postgres-Nodes.

### 6.2 Externes n8n (anderer Server oder Cloud)

1. DNS muss auf deinen Server zeigen (`sb-...` & `n8n-...`).
2. In den Credentials dieselben Werte wie oben verwenden (Host = Supabase-Domain, Secret = `SERVICE_ROLE_KEY`).
3. Optional zusätzliche Sicherheit:
   - Supabase-Kong → n8n: HTTP Basic Auth (Header `Authorization: Basic ...`)
   - n8n-Webhooks → Next.js: Header `X-Admin-Token: <ADMIN_TOKEN>` aus `.env`
4. Für direkten Postgres-Zugriff über Internet empfiehlt sich ein VPN oder SSH-Tunnel; ansonsten `host.docker.internal` nur innerhalb desselben Servers nutzen.

### 6.3 Direkter Postgres-Zugriff (n8n DB-Node, Prisma, BI-Tools)

`scripts/ensure-app-db-user.sh` erzeugt nach jedem `make supabase-up` automatisch den App-Benutzer (`APP_DB_USER` / `APP_DB_PASSWORD`) und vergibt die notwendigen Rechte auf `APP_DB_NAME` – inklusive `USAGE/CREATE` auf dem Schema `public`, damit CREATE TABLE/ALTER TABLE aus n8n oder Prisma funktionieren. Die Verbindung läuft über den offenen Port `POSTGRES_DIRECT_PORT` (Standard 54324) ohne TLS.

| Feld                       | Wert / Herkunft                                    |
|----------------------------|----------------------------------------------------|
| **Host**                   | `SUPABASE_DOMAIN` (z. B. `sb-ai-test.dakatos.online`) |
| **Port**                   | `POSTGRES_DIRECT_PORT` (Default `54324`)           |
| **Database**               | `APP_DB_NAME` (Default `aiTestProdDB`)          |
| **User / Password**        | `APP_DB_USER` / `APP_DB_PASSWORD`                  |
| **SSL**                    | `Disable` bzw. `Allow` + „Ignore SSL Issues“       |

Beispiel-DSN:

```
postgresql://APP_DB_USER:APP_DB_PASSWORD@sb-ai-test.dakatos.online:54324/APP_DB_NAME
```

---

## 7. Häufige Workflows

| Aufgabe                              | Befehl / Hinweis |
|-------------------------------------|------------------|
| Migration erzeugen                  | `docker compose exec web-dev npx prisma migrate dev --name ...` |
| Migration in Prod anwenden          | automatisch beim Deploy (`npm run build`), sonst `docker compose exec web npx prisma migrate deploy` |
| Healthcheck                         | `curl -k https://<SITE_DOMAIN>/api/health` |
| Admin-Token testen                  | `curl -H "X-Admin-Token: $ADMIN_TOKEN" https://<SITE_DOMAIN>/api/admin/ping` |
| Supabase Basic Auth (Kong)          | `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` |
| n8n Daten sichern                   | Volume: `/var/lib/docker/volumes/ai-test_n8n-data/_data` (z. B. per `rsync`) |
| Supabase DB-Config sichern          | Volume: `/var/lib/docker/volumes/supabase_db-config/_data` – `make supabase-up` übernimmt vorhandene Daten automatisch |

---

## 8. Sicherheit & Best Practices

- `.env` und `docker/supabase/.env` niemals committen.
- Alle Default-Keys (Supabase, n8n, Admin Tokens) zeitnah austauschen.
- `AUTH_DISABLED` nur in der lokalen Entwicklung auf `true`.
- Firewalls so konfigurieren, dass nur Ports 80/443 (und optional 5678 sowie dein direkter DB-Port, Standard 54324) öffentlich sind.
- Regelmäßige Backups der Supabase-Datenbank und der n8n-Volume-Daten erstellen.

---

## 9. Fresh-Install & Smoke-Test Checkliste

Diese Kurzliste stellt sicher, dass auch unerfahrene User das Template fehlerfrei starten können:

1. **Repository klonen & Setup ausführen**
   ```bash
   git clone <repo> /var/www/ai-test
   cd /var/www/ai-test
   make setup            # lokal
   # oder
   make setup-prod       # Server
   ```
2. **Supabase einmalig initialisieren**
   ```bash
   make supabase-up
   ```
   Dadurch laufen `ensure-app-db-user` und `bootstrap-supabase-vector` automatisch und stellen alle Rechte, Extensions, Tabellen und RPCs her.
3. **Optional: Testaufrufe**
   - `curl http://localhost:8000/storage/v1/bucket` (Service-Role-Key) ⇒ sollte JSON liefern.
   - Obiger `match_documents`-Test.
4. **App-/n8n-Stack starten**
   ```bash
   make dev            # lokale Entwicklung
   # oder
   make prod-all       # kompletter Server-Stack inkl. Supabase
   ```

Wenn alle vier Punkte erfolgreich waren, ist der Stand identisch mit der hier getesteten Umgebung und n8n kann sofort auf die Vector-DB zugreifen.

---

Viel Erfolg! Wenn du weitere Dienste ergänzt, kopiere am besten das bestehende Profil-/Makefile-Muster und erweitere die README entsprechend. Dieses Template soll speziell Einsteigern helfen, ohne tiefes Docker-Wissen eine funktionsfähige Umgebung aufzubauen.#
