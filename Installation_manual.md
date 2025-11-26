## Installation Manual

Dieses Dokument fasst alle Schritte zusammen, um die aktuelle Umgebung sowohl auf einem Produktionsserver als auch lokal für die Entwicklung exakt auf den getesteten Stand zu bringen. Es dient als Drehbuch für dein Tutorial-Video.

---

## 1. Produktionsserver neu aufsetzen

### 1.1 Vorbereitung
- Alte Codebasis entfernen, Docker-Volumes unter `/var/lib/docker/` unangetastet lassen:
  ```bash
  sudo rm -rf /var/www/ai-test
  ```
- Sicherstellen, dass `docker`, `docker compose`, `git`, `make` und Node.js 20 verfügbar sind (siehe README Abschnitt „Voraussetzungen“).

### 1.2 Repository und Umgebungen
```bash
git clone git@github.com:Dakaric/aam_playground.git /var/www/ai-test
cd /var/www/ai-test
make setup-prod
```
- Beim Setup alle Domains, Tokens und Passwörter auf die geltenden Produktionswerte setzen. Vorhandene `.env` kann überschrieben oder bestätigt werden.
- `make setup-prod` spiegelt die Werte automatisch nach `docker/supabase/.env`.

### 1.3 Supabase initialisieren
- Einmalig ausführen, damit Automationen DB-Benutzer, Extensions, Tabellen (`documents_pg`), das `match_documents`-RPC sowie das Storage-Bucket `n8nRAG` (inkl. Policies) herstellen:
  ```bash
  make supabase-up
  ```
- Das Script `scripts/bootstrap-supabase-vector.sh` läuft dabei automatisch; bei Bedarf lässt es sich später separat neu starten.
- `scripts/ensure-supabase-storage-resources.sh` erzeugt/aktualisiert das Bucket `n8nRAG`, setzt es auf „public“ und legt RLS-Policies für öffentliche Downloads und authentifizierte Uploads an – somit funktionieren Uploads/Downloads direkt nach dem Start.
- `scripts/ensure-app-db-user.sh` liest `APP_DB_USER`, `APP_DB_PASSWORD` und `APP_DB_NAME` aus der `.env`, legt den Benutzer bei Bedarf an und vergibt sämtliche Rechte auf DB, Schema, Tabellen, Sequenzen sowie Default-Privileges – es sind keine manuellen SQL-Befehle nötig.
- `scripts/ensure-supabase-storage-path.sh` erzeugt den Host-Pfad `docker/supabase/volumes/storage` inklusive `.gitkeep`, falls er fehlt (z. B. nach einem frischen Clone).
- **Wichtig:** Bevor die Services starten, sicherstellen, dass der Ordner `docker/supabase/volumes/storage` existiert (Repo enthält eine `.gitkeep`). Falls er gelöscht wurde, einfach `mkdir -p docker/supabase/volumes/storage` ausführen – sonst kann Supabase Storage keine Dateien schreiben.

### 1.4 Produktions-Stack starten
```bash
make prod-all
```
- Startet Supabase, Next.js („web“), Caddy mit automatischem TLS und n8n in einem Rutsch.
- Alternative: `make prod-n8n`, falls Supabase bereits aktiv ist und nur Web + n8n benötigt werden.

### 1.5 Smoke-Tests für das Video
- Website / API:
  ```bash
  curl -Ik https://<SITE_DOMAIN>/api/health
  ```
- Supabase über Kong (erwartet `401` + Header `Server: kong`):
  ```bash
  curl -Ik https://<SUPABASE_DOMAIN>/
  ```
- n8n UI: Browser auf `https://<N8N_DOMAIN>` und per Basic Auth (aus `.env`) einloggen.
- Admin-Token demonstrieren:
  ```bash
  curl -H "X-Admin-Token: $ADMIN_TOKEN" https://<SITE_DOMAIN>/api/admin/ping
  ```

### 1.6 n8n-Workflows & Vector Store
- Da die Docker-Volumes erhalten bleiben, sind bestehende Flows nach dem Neustart sofort verfügbar. Für einen komplett frischen Server kannst du die JSON-Dateien aus `n8n_workflows/` importieren.
- Falls der Vector Store neu initialisiert werden muss (z. B. nach manuellem Eingriff), einfach:
  ```bash
  bash scripts/bootstrap-supabase-vector.sh
  ```
  Das Script ist idempotent und richtet alle Grants und RPCs erneut ein.

### 1.7 Dienste stoppen
```bash
make prod-down
```
- Danach erneut `make prod-all`, um alles sauber hochzufahren.

---

## 2. Lokale Entwicklungsumgebung

### 2.1 Checkout & Setup
```bash
git clone git@github.com:Dakaric/aam_playground.git /var/www/ai-test
cd /var/www/ai-test
make setup       # Scope=dev
```
- Das Setup erstellt `.env` sowie `docker/supabase/.env`, prüft Docker/Node und installiert bei Bedarf automatisch Node.js 20.

### 2.2 Supabase & Services starten
1. Datenbank initialisieren:
   ```bash
   make supabase-up
   ```
2. Next.js + Tools:
   ```bash
   make dev          # Next.js (3000) + Mailpit (8025)
   # oder
   make dev-n8n      # zusätzlich lokales n8n auf 5678
   ```
- Supabase Storage verwendet den Host-Pfad `docker/supabase/volumes/storage`. Sollte dieser Ordner fehlen (z. B. nach `rm -rf`), erneut `mkdir -p docker/supabase/volumes/storage` ausführen, bevor Uploads getestet werden (das macht `make supabase-up` automatisch).
- Das Storage-Bucket `n8nRAG` samt Policies wird beim Aufruf von `make supabase-up` erstellt und ist damit auch lokal sofort einsatzbereit; gleichzeitig werden `documents_pg`, `match_documents` sowie der App-DB-User aus `.env` eingerichtet.

### 2.3 Lokale Endpunkte testen
- App: <http://localhost:3000>
- Mailpit: <http://localhost:8025>
- n8n (optional): <http://localhost:5678> (Basic Auth laut `.env`)
- Healthcheck:
  ```bash
  curl http://localhost:3000/api/health
  ```

### 2.4 Aufräumen
```bash
docker compose --profile dev --profile n8n down
```
- Entfernt alle Dev-Container; Volumes bleiben bestehen.

---

## 3. Hinweise für das Tutorial-Video
- Zeige chronologisch: (1) Repo klonen, (2) `make setup-prod`, (3) `make supabase-up`, (4) `make prod-all`, (5) Smoke-Tests, (6) kurze Demo von n8n-Flow und Supabase Vector Store.
- Ergänze danach das Dev-Kapitel: `make setup`, `make supabase-up`, `make dev`, lokale URLs zeigen.
- Erwähne, dass sämtliche Automatisierungen (App-DB-User, Vector Store, RPCs) durch `make supabase-up` und `bootstrap-supabase-vector.sh` erledigt werden und daher keine manuellen SQL-Schritte notwendig sind.
- Betone Sicherheitsschritte: Austausch aller Default-Keys/Tokens und Verwendung von `X-Admin-Token` bei API-Aufrufen.

Damit lassen sich Prod- und Dev-Umgebungen jederzeit reproduzierbar aufsetzen und filmen.


