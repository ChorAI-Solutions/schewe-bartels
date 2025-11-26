#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORAGE_DIR="${ROOT_DIR}/docker/supabase/volumes/storage"

log() {
  echo "[supabase-storage-path] $*"
}

if [[ ! -d "${STORAGE_DIR}" ]]; then
  log "Erstelle fehlenden Ordner ${STORAGE_DIR} …"
  mkdir -p "${STORAGE_DIR}"
else
  log "Ordner ${STORAGE_DIR} ist bereits vorhanden."
fi

if [[ ! -f "${STORAGE_DIR}/.gitkeep" ]]; then
  log "Lege .gitkeep an, damit der Ordner versioniert bleibt."
  touch "${STORAGE_DIR}/.gitkeep"
fi


