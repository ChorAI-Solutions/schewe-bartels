#!/usr/bin/env bash
set -euo pipefail

# Automatische Wartung (Samstag 2:00 Uhr)
# Führt Check-Updates und n8n-Update schrittweise aus

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log() { printf '[scheduled-maintenance] %s\n' "$1"; }

send_telegram() {
  local message="$1"
  local telegram_bot_token="${TELEGRAM_BOT_TOKEN:-}"
  local telegram_chat_id="${TELEGRAM_CHAT_ID:-}"

  if [[ -z "$telegram_bot_token" ]] || [[ -z "$telegram_chat_id" ]]; then
    log "Warnung: Telegram-Konfiguration unvollständig"
    return
  fi

  curl -s -X POST "https://api.telegram.org/bot${telegram_bot_token}/sendMessage" \
    -d "chat_id=${telegram_chat_id}" \
    -d "text=${message}" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1 || log "Fehler: Telegram-Nachricht konnte nicht versendet werden"
}

main() {
  cd "$REPO_ROOT"

  log "Starte automatische Wartung …"
  send_telegram "🔧 <b>Automatische Wartung gestartet</b> - $(date '+%d.%m.%Y %H:%M:%S')"

  # System-Check (ohne Installation)
  log "Schritt 1/3: Prüfe System-Updates …"
  bash scripts/check-updates.sh --system-only || true

  log "Warte 60 Sekunden vor Docker-Updates …"
  sleep 60

  # Docker-Updates
  log "Schritt 2/3: Prüfe Docker-Images …"
  bash scripts/check-updates.sh --docker-only || true

  log "Warte 30 Sekunden vor n8n-Update …"
  sleep 30

  # n8n-Update
  log "Schritt 3/3: Aktualisiere n8n …"
  bash scripts/update-n8n.sh || true

  log "Automatische Wartung abgeschlossen."
  send_telegram "✅ <b>Wartung erfolgreich abgeschlossen</b> - $(date '+%d.%m.%Y %H:%M:%S')"
}

main "$@"
