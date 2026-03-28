# Agents – Leitfaden für den Kurs (Next.js + n8n)

Dieser Leitfaden zeigt dir, wie du in diesem Projekt schrittweise einen Chat‑Agent (später Voice‑Agent) baust und n8n einbindest. Alles ist für Windows, macOS und Linux vorbereitet.

## Voraussetzungen
- Repo geklont, `.env` via `make setup` erstellt (Vorlage & Meta-Daten: `env.template`)
- Stack läuft: `docker compose up -d --build`
- Erreichbar:
  - Web: `http://localhost:3000`
  - n8n: `http://localhost:5678` (Basic‑Auth aus `.env`)
  - Mail‑UI: `http://localhost:8025`

### Setup-Workflow
- `make setup` / `make setup-dev`: lokale Defaults (Scope `dev`).
- `make setup-prod`: produktive Werte mit TLS-/Domain-Feldern (`scope=prod`). Auf frischen Servern zuerst `sudo apt update && sudo apt install build-essential` ausführen, danach übernimmt `scripts/check-server-tools.sh` die Prüfung auf Docker, Compose, Git und Node.js/npm.
- `make setup-env scope=prod`: falls du dynamisch zwischen Scopes wechseln willst (bei Scope `prod` läuft ebenfalls der Dependency-Check nach der manuellen build-essential-Installation).
- Das Skript `scripts/setup-env.cjs` liest die `# @meta { ... }` Blöcke in `env.template`, schlägt pro Scope Defaults vor und schreibt `.env`. Enter übernimmt den Vorschlag, `.` setzt den Wert leer.
- Nach dem Setup prüft `post-setup`, ob `NEW_REMOTE_URL` gesetzt ist, und ruft bei Bedarf `make switch-remote NEW_REMOTE_URL=…` auf, um das Git-Remote automatisch umzustellen. Direkt danach sorgt `scripts/git-bootstrap.sh` dafür, dass `git config user.name`/`user.email` gesetzt sind, der Branch `main` heißt und `git push -u origin main` ausgeführt wird.

## Sicherheits‑Basics
- Admin‑Endpoints (z. B. `/api/admin/*` und `/api/webhooks/n8n`) sind per Header `X-Admin-Token` geschützt.
- Token in `.env` setzen (`ADMIN_TOKEN`) und in Requests mitschicken.
- **n8n:** Image in `docker-compose.yml` fest pinnen und bei Sicherheitshinweisen des Herstellers zeitnah anheben (siehe [n8n Security Advisories](https://github.com/n8n-io/n8n/security/advisories)); danach `make update-n8n` bzw. `docker compose --profile n8n pull n8n` und Container neu starten.

## Wartung, Updates & Serverlast (für Agenten)

**Ziel:** Der Host darf nicht durch parallele oder zu große Jobs überlastet werden (RAM/I/O, dpkg‑Lock, Instabilität). Vorgehen **schrittweise** („peu à peu“).

**Verbindliche Projektregel für Cursor:** `.cursor/rules/server-operations-safety.mdc` (`alwaysApply`).

### Was du nicht tun sollst
- Nicht gleichzeitig auf demselben Server anstoßen: großes `apt upgrade`, mehrere schwere `docker pull`, `docker compose up --build` und weitere CPU-/I/O‑intensive Tasks.
- Kein zweites `apt`/`dpkg`, solange ein anderes läuft (Lock warten).
- Keine „alles in einem Rutsch“-Shells mit mehreren Hintergrundjobs für Wartung.

### Empfohlene Reihenfolge (Produktion / kleiner Server)
1. **Nur prüfen, nicht installieren:** zuerst Last runterfahren oder ruhiges Fenster wählen.
2. **System getrennt von Docker:**  
   - `make check-updates-system` (listet verfügbare Pakete; führt **kein** `apt upgrade` aus).  
   - Pause, dann **manuell** `sudo apt-get upgrade -y` (ein Lauf, zu Ende warten).  
3. **Docker Images:**  
   - Entweder `make check-updates-docker` **nach** dem System-Upgrade und einer Pause, **oder** noch schonender:  
   - `make check-updates-pull-one SERVICE=n8n` (dann z. B. `caddy`, `mailpit`, `web-dev` nacheinander).  
4. **Container mit neuen Images:** z. B. `make prod-n8n` / `make update-n8n` je nach Profil – nicht parallel zum nächsten großen Pull.  
5. **Health:** `make health-check` (Web, n8n, Mailpit per HTTP).

### Make‑Targets & Skript
| Aktion | Befehl |
|--------|--------|
| Hilfe (Optionen + Warnhinweise) | `bash scripts/check-updates.sh --help` |
| Standard (System-Liste + Docker‑Pull nacheinander, mit Hinweis) | `make check-updates` |
| Nur System-Update-Liste | `make check-updates-system` |
| Nur alle Compose‑Images pullen | `make check-updates-docker` |
| Ein Service einzeln pullen | `make check-updates-pull-one SERVICE=n8n` |
| HTTP‑Health | `make health-check` |

Das Skript `scripts/check-updates.sh` installiert **keine** System-Pakete; es aktualisiert nur den Paketindex (apt/brew) zum Auflisten bzw. zieht Docker‑Images.

## Aktueller Stand im Repo
- Next.js (App Router) mit Tailwind
- API‑Routen:
  - `/api/health` (Liveness)
  - `/api/admin/ping` (Token‑geschützt)
  - `/api/webhooks/n8n` (Token‑geschützt; Echo‑Beispiel)
- Prisma + Postgres mit Modell `BlogPost`
- Docker Compose: `web`, `db`, `n8n`, `mailpit`

## Roadmap der Agenten
1) Chat‑Agent (Text): Next.js API‑Route `/api/chat` → n8n Webhook → Antwort zurück
2) Voice‑Agent (später): Streaming/SIP/WebRTC → n8n/LLM‑Kette → TTS zurück
3) Blog‑Automation: n8n erstellt/versendet Blogposts → `/api/admin/blog/*`

---

## 1) Chat‑Agent
Ziel: Eine einfache Chat‑HTTP‑Route, die Nachrichten an n8n weiterleitet und die Antwort zurückgibt.

### 1.1 n8n vorbereiten
- In n8n einen „Webhook“ Node anlegen
  - Methode: POST
  - Pfad: `chat`
  - Optional: Header `X-Admin-Token` prüfen (Function Node) → mit `.env` abgleichen
- LLM/Antwort generieren (z. B. OpenAI Node, Dummy Function, etc.)
- Response (Webhook Reply) Node: JSON `{ reply: "..." }`
- Test‑URL lokal: `http://localhost:5678/webhook/chat`

### 1.2 API‑Route in Next.js (Beispiel)
Erstelle `app/api/chat/route.ts` (geschützt via Token, Proxy zu n8n):

```ts
// app/api/chat/route.ts (Beispiel)
import { requireAdminToken } from "@/lib/auth";

export async function POST(request: Request) {
  try {
    requireAdminToken(request);
  } catch (err) {
    return err as Response;
  }

  const body = await request.json().catch(() => ({}));
  const webhookUrl = process.env.N8N_WEBHOOK_URL ?? "http://n8n:5678/webhook/chat";

  const res = await fetch(webhookUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  const data = await res.json().catch(() => ({}));
  return Response.json(data, { status: res.status });
}
```

Hinweis: In Docker ist `n8n` per Servicenamen erreichbar. Außerhalb (z. B. lokal via cURL) nutzt du `http://localhost:5678/webhook/chat`.

### 1.3 Testen
- cURL (zsh/Bash):
```bash
curl -sS -H 'X-Admin-Token: <ADMIN_TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{"message":"Hallo Agent"}' \
  http://localhost:3000/api/chat
```
- Erwartung: `{ "reply": "..." }` aus dem n8n‑Flow

### 1.4 Optional: Client‑UI
- Einfache Eingabe in `app/page.tsx` oder neue Seite `app/chat/page.tsx`
- Request an `/api/chat` senden, Antwort anzeigen

---

## 2) Voice‑Agent (Ausblick)
- Transport: WebRTC, SIP (z. B. Twilio, Asterisk), oder Browser‑Audio Upload + TTS
- Server‑Seite: Streaming‑Endpoint (Edge‑fähig) oder Polling‑Loop
- n8n: Kette (ASR → NLU/LLM → Tools → TTS)
- Sicherheit: Weiterhin `X-Admin-Token` für Kontroll‑Endpoints

Empfehlung für später:
- `/api/voice` als Upgrade‑Pfad anlegen
- Evaluieren: WebRTC SFU/MCU vs. Anbieter (Twilio, LiveKit)

---

## 3) Blog‑Automation
- Ziel: Beiträge automatisiert über n8n erstellen/veröffentlichen
- Next.js Admin‑API (Token‑geschützt): `/api/admin/blog/create`
- n8n flow: generiert Content (LLM), ruft Admin‑API auf

Beispiel‑Payload (n8n → Next.js):
```json
{
  "title": "Mein erster automatischer Post",
  "content": "…",
  "published": true
}
```

Server‑Hinweis:
- In der Admin‑Route Prisma nutzen (`import { prisma } from "@/lib/db";`)
- Validierung + Token‑Check (`requireAdminToken`)

---

## Datenhaltung (optional)
Für Chat‑Verläufe/Analytik könnte ein Modell sinnvoll sein (nur Vorschlag, nicht umgesetzt):
```prisma
model MessageLog {
  id        String   @id @default(cuid())
  role      String   // user | assistant | system
  content   String
  createdAt DateTime @default(now())
}
```

---

## Testing & Troubleshooting
- Health: `http://localhost:3000/api/health` oder `make health-check`
- Token‑Check: `/api/admin/ping` (Header `X-Admin-Token`)
- n8n Basic‑Auth: in `.env` setzen und ggf. `docker compose restart n8n`
- Mailpit (lokal): `http://localhost:8025` (für Einladungen/Resets, falls User‑Management aktiv)
- Windows PowerShell: Header mit doppelten Quotes, z. B. `"X-Admin-Token: ..."`
- zsh: Tokens mit `!` in einfache Quotes setzen

---

## Cursor – sinnvolle Prompts
- „Führe Wartung auf dem Server aus: strikt schrittweise laut AGENTS.md (keine parallelen schweren Jobs); zuerst `make check-updates-system`, Pause, dann Docker einzeln oder `make check-updates-docker`, danach `make health-check`.“
- „Implementiere eine neue Route `app/api/chat/route.ts`, die Body `{message}` akzeptiert, `requireAdminToken` nutzt und an `process.env.N8N_WEBHOOK_URL` proxyt. Tests via cURL hinzufügen.“
- „Erstelle `app/chat/page.tsx` mit einfachem Formular (Textarea + Button), das `/api/chat` aufruft und die Antwort rendert.“
- „Füge eine Admin‑Route zum Erstellen von Blogposts hinzu (`/api/admin/blog/create`) inkl. Zod‑Validierung.“
- „Baue einen Logging‑Layer, der Requests/Responses des Chat‑Agents in Prisma speichert.“

---

## Stil & Commits
- Code‑Stil: klare Namen, frühe Rückgaben, keine unnötigen try/catch
- Kommentare nur, wenn wirklich nötig (Rationalen, Caveats)
- Commits: kleine, sinnvolle Einheiten mit Klartext („Add /api/chat proxy to n8n“)

---

## Nützliche Kommandos
```bash
# Stack bauen & starten
docker compose up -d --build

# Wartung schrittweise (Details: Abschnitt „Wartung, Updates & Serverlast“)
make check-updates-system      # nur System-Updates listen
make check-updates-docker      # nur Docker-Images pullen (nach Pause)
make check-updates-pull-one SERVICE=n8n   # einzelner Service, am schonendsten
make health-check

# Logs
docker compose logs -f web
docker compose logs -f n8n

# Prisma (Migration deploy in Container)
docker compose exec web npx prisma migrate deploy --schema=prisma/schema.prisma

# n8n User‑Management zurücksetzen (falls Login/Setup hängt)
docker compose exec n8n n8n user-management:reset
```

Viel Erfolg – und baue iterativ! Starte mit `/api/chat` + n8n Webhook, teste per cURL, und erstelle dann die UI.
