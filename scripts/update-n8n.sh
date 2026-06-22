#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"

log() { printf '[update-n8n] %s\n' "$1"; }
die() { printf '[update-n8n] FEHLER: %s\n' "$1" >&2; exit 1; }

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
}

main
