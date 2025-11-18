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
- `make setup-prod`: produktive Werte mit TLS-/Domain-Feldern (`scope=prod`) und vorgelagerter Server-Prüfung via `scripts/check-deps.sh` (Docker, Compose, Git, Node.js/npm).
- `make setup-env scope=prod`: falls du dynamisch zwischen Scopes wechseln willst (bei Scope `prod` läuft ebenfalls der Dependency-Check).
- Das Skript `scripts/setup-env.cjs` liest die `# @meta { ... }` Blöcke in `env.template`, schlägt pro Scope Defaults vor und schreibt `.env`. Enter übernimmt den Vorschlag, `.` setzt den Wert leer.
- Nach dem Setup prüft `post-setup`, ob `NEW_REMOTE_URL` gesetzt ist, und ruft bei Bedarf `make switch-remote NEW_REMOTE_URL=…` auf, um das Git-Remote automatisch umzustellen.

## Sicherheits‑Basics
- Admin‑Endpoints (z. B. `/api/admin/*` und `/api/webhooks/n8n`) sind per Header `X-Admin-Token` geschützt.
- Token in `.env` setzen (`ADMIN_TOKEN`) und in Requests mitschicken.

## Aktueller Stand im Repo
- Next.js (App Router) mit Tailwind
- API‑Routen:
  - `/api/health` (Liveness)
  - `/api/admin/ping` (Token‑geschützt)
  - `/api/webhooks/n8n` (Token‑geschützt; Echo‑Beispiel)
- Prisma + Postgres mit Modell `BlogPost`
- Docker Compose: `web`, `db`, `n8n`, `pgadmin`, `mailpit`

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
- Health: `http://localhost:3000/api/health`
- Token‑Check: `/api/admin/ping` (Header `X-Admin-Token`)
- n8n Basic‑Auth: in `.env` setzen und ggf. `docker compose restart n8n`
- Mailpit (lokal): `http://localhost:8025` (für Einladungen/Resets, falls User‑Management aktiv)
- Windows PowerShell: Header mit doppelten Quotes, z. B. `"X-Admin-Token: ..."`
- zsh: Tokens mit `!` in einfache Quotes setzen

---

## Cursor – sinnvolle Prompts
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

# Logs
docker compose logs -f web
docker compose logs -f n8n

# Prisma (Migration deploy in Container)
docker compose exec web npx prisma migrate deploy --schema=prisma/schema.prisma

# n8n User‑Management zurücksetzen (falls Login/Setup hängt)
docker compose exec n8n n8n user-management:reset
```

Viel Erfolg – und baue iterativ! Starte mit `/api/chat` + n8n Webhook, teste per cURL, und erstelle dann die UI.
