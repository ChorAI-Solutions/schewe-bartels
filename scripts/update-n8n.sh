#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"

# Lade Umgebungsvariablen aus .env
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

log() { printf '[update-n8n] %s\n' "$1"; }
die() { printf '[update-n8n] FEHLER: %s\n' "$1" >&2; exit 1; }

send_telegram() {
  local message="$1"
  local telegram_bot_token="${TELEGRAM_BOT_TOKEN:-}"
  local telegram_chat_id="${TELEGRAM_CHAT_ID:-}"

  if [[ -z "$telegram_bot_token" ]] || [[ -z "$telegram_chat_id" ]]; then
    return
  fi

  curl -s -X POST "https://api.telegram.org/bot${telegram_bot_token}/sendMessage" \
    -d "chat_id=${telegram_chat_id}" \
    -d "text=${message}" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1 || true
}

on_error() {
  local line=$1
  log "FEHLER in Zeile $line - Update fehlgeschlagen"
  send_telegram "❌ <b>[hezner-schewe-bartels] n8n UPDATE FEHLGESCHLAGEN</b>$(printf '\n\n')⚠️ FEHLER:$(printf '\n')━━━━━━━━━━━━━━━━━━━━━━$(printf '\n')Zeile: $line$(printf '\n')Skript: update-n8n.sh$(printf '\n\n')⏰ Zeitstempel: $(date '+%d.%m.%Y %H:%M:%S')$(printf '\n\n')📋 Bitte manuell prüfen!"
}

trap 'on_error $LINENO' ERR

# Neueste stabile n8n-Version von Docker Hub holen (ohne 'latest'-Tag)
fetch_latest_version() {
  local token page tags latest_stable

  # Anonymes Token für registry.hub.docker.com
  token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:n8nio/n8n:pull" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)"

  latest_stable=""
  page=1
  while true; do
    tags="$(curl -fsSL \
      -H "Authorization: Bearer $token" \
      "https://registry-1.docker.io/v2/n8nio/n8n/tags/list?page=${page}&page_size=100" \
      | grep -o '"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"' \
      | tr -d '"' || true)"

    [[ -z "$tags" ]] && break

    # Höchste SemVer-Version aus dieser Seite
    local page_max
    page_max="$(echo "$tags" | sort -V | tail -1)"
    if [[ -z "$latest_stable" ]] || printf '%s\n%s\n' "$latest_stable" "$page_max" | sort -V | tail -1 | grep -qx "$page_max"; then
      latest_stable="$page_max"
    fi
    page=$((page + 1))
    # Docker Hub liefert leere Seiten ab Ende → Abbruch nach 5 Seiten als Sicherheitsnetz
    [[ $page -gt 5 ]] && break
  done

  echo "$latest_stable"
}

# Aktuelle Version aus docker-compose.yml lesen
current_version() {
  grep -oP 'n8nio/n8n:\K[0-9]+\.[0-9]+\.[0-9]+' "$COMPOSE_FILE" | head -1
}

main() {
  log "Ermittle aktuelle Version …"
  local current latest
  current="$(current_version)"
  log "Installiert: ${current}"

  log "Frage Docker Hub nach neuester stabiler Version …"
  latest="$(fetch_latest_version)"
  [[ -z "$latest" ]] && die "Konnte neueste Version nicht ermitteln. Netzwerkfehler?"

  log "Verfügbar:   ${latest}"

  if [[ "$current" == "$latest" ]]; then
    log "n8n ist bereits aktuell (${current}). Kein Update nötig."
    exit 0
  fi

  # Start-Benachrichtigung
  send_telegram "🚀 <b>[hezner-schewe-bartels] n8n Update gestartet</b>$(printf '\n\n')📦 Von: n8nio/n8n:${current}$(printf '\n')Zu: n8nio/n8n:${latest}"

  log "Update: ${current} → ${latest}"
  # docker-compose.yml in-place aktualisieren
  sed -i "s|n8nio/n8n:${current}|n8nio/n8n:${latest}|g" "$COMPOSE_FILE"
  log "docker-compose.yml aktualisiert."

  cd "$REPO_ROOT"
  log "Ziehe neues Image …"
  docker compose --profile n8n pull n8n

  log "Starte n8n neu …"
  docker compose --profile n8n up -d n8n

  log "n8n erfolgreich auf ${latest} aktualisiert."

  # Success-Benachrichtigung
  send_telegram "✅ <b>[hezner-schewe-bartels] n8n UPDATE ERFOLGREICH</b>$(printf '\n\n')📦 VERSIONS-INFO:$(printf '\n')━━━━━━━━━━━━━━━━━━━━━━$(printf '\n')Von: n8nio/n8n:${current}$(printf '\n')Zu: n8nio/n8n:${latest}$(printf '\n\n')🔧 STATUS:$(printf '\n')━━━━━━━━━━━━━━━━━━━━━━$(printf '\n')Container: ✅ Neugestartet$(printf '\n')Datenbank: Online$(printf '\n\n')⏰ Zeitstempel: $(date '+%d.%m.%Y %H:%M:%S')"
}

main
