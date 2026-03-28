#!/usr/bin/env bash
set -euo pipefail

# Prüft System-Updates (apt/brew) und Docker-Stack-Images.
# Schrittweise nutzen, um den Server nicht zu überlasten (siehe --help).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="all"
pullOneService=""

COMPOSE_PULL_PROFILES=(--profile dev --profile prod --profile n8n)

log() {
  printf '[check-updates] %s\n' "$1"
}

warn() {
  printf '[check-updates] WARN: %s\n' "$1" >&2
}

print_usage() {
  cat <<'EOF'
Verwendung: check-updates.sh [OPTION]

  (ohne Option)     Zuerst System-Check, dann Docker-Pull (I/O-intensiv).
  --system-only     Nur Paketindex + Liste verfügbarer System-Updates (kein Upgrade).
  --docker-only     Nur docker compose pull (alle relevanten Profile).
  --docker-pull-one SERVICE
                    Nur ein Compose-Service pullen (weniger Last auf einmal).
                    Beispiel: check-updates.sh --docker-pull-one n8n
  -h, --help        Diese Hilfe.

Sicherheit / Serverlast (wichtig):
  • Kein paralleles zweites apt oder großer Build während dieses Skripts.
  • Auf kleinen Servern: --system-only ausführen, warten, später --docker-only
    oder mehrere Läufe mit --docker-pull-one (z. B. n8n, dann caddy, dann mailpit).
  • Dieses Skript installiert keine System-Pakete; apt upgrade manuell separat.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        print_usage
        exit 0
        ;;
      --system-only)
        MODE="system-only"
        shift
        ;;
      --docker-only)
        MODE="docker-only"
        shift
        ;;
      --docker-pull-one)
        if [[ -z "${2:-}" ]]; then
          echo "[check-updates] Fehler: --docker-pull-one benötigt einen Service-Namen (z. B. n8n)." >&2
          exit 1
        fi
        pullOneService="$2"
        MODE="docker-pull-one"
        shift 2
        ;;
      *)
        echo "[check-updates] Unbekannte Option: $1" >&2
        print_usage >&2
        exit 1
        ;;
    esac
  done
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
  echo "  → Installation separat und zu ruhiger Zeit: sudo apt-get upgrade -y"
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
  echo "  → Installation separat: brew upgrade"
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

docker_compose_pull_all() {
  cd "$REPO_ROOT"
  local out
  if out="$(docker compose "${COMPOSE_PULL_PROFILES[@]}" pull 2>&1)"; then
    if echo "$out" | grep -q "Downloaded newer image"; then
      log "Neue Images wurden heruntergeladen. Neustart z. B.: make prod-n8n / make dev-n8n"
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

docker_compose_pull_one() {
  local serviceName="$1"
  cd "$REPO_ROOT"
  log "Docker: pull nur Service '${serviceName}' …"
  local out
  if out="$(docker compose "${COMPOSE_PULL_PROFILES[@]}" pull "$serviceName" 2>&1)"; then
    if echo "$out" | grep -q "Downloaded newer image"; then
      log "Neues Image für '${serviceName}' geladen."
      echo "$out" | grep "Downloaded newer image" || true
    else
      log "Service '${serviceName}': bereits aktuell oder kein Remote-Image."
    fi
  else
    warn "Pull für '${serviceName}' fehlgeschlagen."
    echo "$out" >&2
    return 1
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
  log "Docker-Stack: Prüfe auf neue Images (pull, kann I/O-intensiv sein) …"
  docker_compose_pull_all
}

hint_low_resource_servers() {
  log "Hinweis: Bei wenig RAM/CPU lieber schrittweise:"
  log "  1) $0 --system-only  → warten  2) $0 --docker-only"
  log "  oder: $0 --docker-pull-one n8n (und weitere Services einzeln)."
  log "Nicht parallel zu apt upgrade, großen Builds oder zweitem Pull ausführen."
}

run_checks() {
  case "$MODE" in
    system-only)
      check_system_updates
      ;;
    docker-only)
      check_docker_stack_updates
      ;;
    docker-pull-one)
      check_docker_stack_updates_for_one
      ;;
    all)
      hint_low_resource_servers
      echo ""
      check_system_updates
      echo ""
      check_docker_stack_updates
      ;;
    *)
      print_usage >&2
      exit 1
      ;;
  esac
}

check_docker_stack_updates_for_one() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker nicht gefunden."
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    warn "Docker Compose nicht verfügbar."
    return 1
  fi
  docker_compose_pull_one "$pullOneService"
}

parse_args "$@"

log "Starte Update-Prüfung (Modus: ${MODE}) …"
run_checks
log "Fertig."
