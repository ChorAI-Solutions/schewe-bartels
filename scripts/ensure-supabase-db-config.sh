#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[supabase-config] $*"
}

if ! command -v docker >/dev/null 2>&1; then
  log "docker nicht gefunden – kann Volume nicht prüfen."
  exit 1
fi

VOLUME_NAME="${SUPABASE_DB_CONFIG_VOLUME:-supabase_db-config}"
BACKUP_PATH_DEFAULT="/var/lib/docker/volumes/${VOLUME_NAME}/_data"
BACKUP_PATH="${SUPABASE_DB_CONFIG_BACKUP:-$BACKUP_PATH_DEFAULT}"
TMP_DIR=""

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

if docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  log "Volume ${VOLUME_NAME} existiert bereits – verwende vorhandene Daten."
  exit 0
fi

log "Volume ${VOLUME_NAME} fehlt – prüfe, ob bestehende Dateien übernommen werden können …"

if [[ -d "${BACKUP_PATH}" ]] && [[ -n "$(ls -A "${BACKUP_PATH}" 2>/dev/null)" ]]; then
  TMP_DIR="$(mktemp -d)"
  log "Sicherung unter ${BACKUP_PATH} gefunden – kopiere temporär nach ${TMP_DIR}."
  docker run --rm \
    -v "${BACKUP_PATH}:/source:ro" \
    -v "${TMP_DIR}:/target" \
    alpine:3.20 sh -c "cp -a /source/. /target/" >/dev/null
else
  log "Keine Daten unter ${BACKUP_PATH} gefunden – Supabase startet mit leerem Volume."
fi

docker volume create "${VOLUME_NAME}" >/dev/null
log "Volume ${VOLUME_NAME} wurde angelegt."

if [[ -n "${TMP_DIR}" ]]; then
  log "Bereite Wiederherstellung der Sicherung für ${VOLUME_NAME} vor …"
  docker run --rm \
    -v "${VOLUME_NAME}:/target" \
    -v "${TMP_DIR}:/source:ro" \
    alpine:3.20 sh -c "cp -a /source/. /target/" >/dev/null
  log "Übernahme abgeschlossen."
else
  log "Keine Sicherung zum Einspielen vorhanden – es wird mit den Standardwerten gearbeitet."
fi

