#!/usr/bin/env bash
set -euo pipefail

# Prüft verfügbare System-Updates (apt/brew) und Docker-Stack-Images.
# Aufruf: scripts/check-updates.sh [--system-only|--docker-only]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${1:-all}"

log() {
  printf '[check-updates] %s\n' "$1"
}

warn() {
  printf '[check-updates] WARN: %s\n' "$1" >&2
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v brew >/dev/null 2>&1; then
    echo "brew"
  else
    echo ""
  fi
}

check_system_updates_apt() {
  log "Aktualisiere apt-Index (sudo kann erforderlich sein) …"
  if ! sudo apt-get update -qq 2>/dev/null; then
    warn "apt-get update fehlgeschlagen – prüfe ohne aktualisierten Index."
  fi
  local upgradable
  upgradable="$(apt list --upgradable 2>/dev/null | tail -n +2)"
  if [[ -z "${upgradable// }" ]]; then
    log "Keine System-Updates verfügbar."
    return 0
  fi
  local count
  count="$(echo "$upgradable" | wc -l)"
  log "Verfügbare System-Updates: ${count}"
  echo "$upgradable" | head -20
  if [[ "$count" -gt 20 ]]; then
    echo "  … und $((count - 20)) weitere (apt list --upgradable)."
  fi
  echo "  → Installation: sudo apt-get upgrade -y"
}

check_system_updates_brew() {
  log "Aktualisiere Homebrew-Index …"
  brew update -q 2>/dev/null || true
  local outdated
  outdated="$(brew outdated 2>/dev/null)"
  if [[ -z "${outdated// }" ]]; then
    log "Keine System-Updates verfügbar (brew)."
    return 0
  fi
  local count
  count="$(echo "$outdated" | wc -l)"
  log "Verfügbare Formulae/Casks: ${count}"
  echo "$outdated" | head -20
  if [[ "$count" -gt 20 ]]; then
    echo "  … und $((count - 20)) weitere (brew outdated)."
  fi
  echo "  → Installation: brew upgrade"
}

check_system_updates() {
  local pkg_manager
  pkg_manager="$(detect_package_manager)"
  if [[ -z "$pkg_manager" ]]; then
    warn "Weder apt noch brew gefunden – überspringe System-Check."
    return 0
  fi
  log "System-Check (${pkg_manager}) …"
  if [[ "$pkg_manager" == "apt" ]]; then
    check_system_updates_apt
  else
    check_system_updates_brew
  fi
}

check_docker_stack_updates() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker nicht gefunden – überspringe Stack-Check."
    return 0
  fi
  if ! docker compose version >/dev/null 2>&1; then
    warn "Docker Compose nicht verfügbar – überspringe Stack-Check."
    return 0
  fi
  log "Docker-Stack: Prüfe auf neue Images (pull) …"
  cd "$REPO_ROOT"
  local out
  if out="$(docker compose --profile dev --profile prod --profile n8n pull 2>&1)"; then
    if echo "$out" | grep -q "Downloaded newer image"; then
      log "Neue Images wurden heruntergeladen. Neustart mit: make prod-n8n bzw. make dev-n8n"
      echo "$out" | grep "Downloaded newer image" || true
    else
      log "Docker-Stack: Alle Images sind aktuell."
    fi
  else
    warn "Docker Compose pull ist fehlgeschlagen oder teilweise fehlgeschlagen."
    echo "$out" >&2
    return 1
  fi
}

run_checks() {
  case "$MODE" in
    --system-only)
      check_system_updates
      ;;
    --docker-only)
      check_docker_stack_updates
      ;;
    all)
      check_system_updates
      echo ""
      check_docker_stack_updates
      ;;
    *)
      echo "Verwendung: $0 [--system-only|--docker-only]" >&2
      echo "  Ohne Option: System-Updates und Docker-Stack prüfen." >&2
      exit 1
      ;;
  esac
}

log "Starte Update-Prüfung (Modus: ${MODE}) …"
run_checks
log "Fertig."
