#!/usr/bin/env bash
set -euo pipefail

SCOPE="${1:-prod}"

log() {
  printf '[setup-check] %s\n' "$1"
}

warn() {
  printf '[setup-check] WARN: %s\n' "$1" >&2
}

OS="$(uname -s 2>/dev/null || echo unknown)"
PKG_MANAGER=""
APT_UPDATED=0

if command -v apt-get >/dev/null 2>&1; then
  PKG_MANAGER="apt"
elif command -v brew >/dev/null 2>&1; then
  PKG_MANAGER="brew"
fi

apt_install() {
  if [[ "$PKG_MANAGER" != "apt" ]]; then
    return 1
  fi
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    log "Aktualisiere apt Paketindex (sudo erforderlich)…"
    sudo apt-get update -y
    APT_UPDATED=1
  fi
  log "Installiere Pakete via apt-get: $*"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

brew_install() {
  if [[ "$PKG_MANAGER" != "brew" ]]; then
    return 1
  fi
  log "Installiere Pakete via Homebrew: $*"
  brew install "$@"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker gefunden: $(docker --version 2>/dev/null)"
    return
  fi

  log "Docker fehlt – versuche Installation."
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt_install docker.io docker-compose-plugin
    sudo systemctl enable docker >/dev/null 2>&1 || true
    sudo systemctl start docker >/dev/null 2>&1 || true
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    if ! brew install --cask docker >/dev/null 2>&1; then
      warn "Automatische Docker-Installation via brew --cask docker fehlgeschlagen."
      warn "Bitte Docker Desktop manuell installieren: https://www.docker.com/products/docker-desktop/"
      exit 1
    fi
    warn "Bitte Docker Desktop nach der Installation starten und einmalig authorisieren."
  else
    warn "Keine unterstützte Paketverwaltung gefunden. Installiere Docker manuell: https://docs.docker.com/engine/install/"
    exit 1
  fi
}

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose Plugin gefunden."
    return
  fi

  log "Docker Compose Plugin fehlt – versuche Installation."
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt_install docker-compose-plugin
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    brew_install docker-compose || warn "brew docker-compose fehlgeschlagen – nutze Docker Desktop CLI."
  else
    warn "Bitte installiere das Docker Compose Plugin manuell: https://docs.docker.com/compose/install/"
    exit 1
  fi
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    log "Git gefunden."
    return
  fi

  log "Git fehlt – versuche Installation."
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt_install git
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    brew_install git
  else
    warn "Bitte installiere Git manuell: https://git-scm.com/downloads"
    exit 1
  fi
}

ensure_node_stack() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    log "Node.js & npm gefunden ($(node --version 2>/dev/null), $(npm --version 2>/dev/null))."
    return
  fi

  log "Node.js/npm fehlen – versuche Installation."
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt_install nodejs npm
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    brew_install node
  else
    warn "Bitte installiere Node.js manuell: https://nodejs.org/"
    exit 1
  fi
}

log "Prüfe Systemvoraussetzungen für Scope '${SCOPE}'."
log "Erkanntes System: ${OS}, Paketverwaltung: ${PKG_MANAGER:-unbekannt}"

ensure_git
ensure_node_stack
ensure_docker
ensure_docker_compose

log "Alle Abhängigkeiten vorhanden."

