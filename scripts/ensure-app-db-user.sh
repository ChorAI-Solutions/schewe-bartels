#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
SUPABASE_ENV_FILE="${ROOT_DIR}/docker/supabase/.env"
COMPOSE_CMD="docker compose -f docker/supabase/docker-compose.yml --env-file docker/supabase/.env"

if [[ ! -f "$ENV_FILE" || ! -f "$SUPABASE_ENV_FILE" ]]; then
  echo "[supabase-app-user] .env oder docker/supabase/.env fehlt – überspringe."
  exit 0
fi

set -a
source "$ENV_FILE"
source "$SUPABASE_ENV_FILE"
set +a

escape_sql() {
  printf "%s" "$1" | sed "s/'/''/g"
}

APP_DB_USER="${APP_DB_USER:-}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:-}"
APP_DB_NAME="${APP_DB_NAME:-${POSTGRES_DB:-}}"

if [[ -z "$APP_DB_USER" || -z "$APP_DB_PASSWORD" || -z "$APP_DB_NAME" ]]; then
  echo "[supabase-app-user] APP_DB_USER/APP_DB_PASSWORD/APP_DB_NAME nicht vollständig gesetzt – überspringe."
  exit 0
fi

echo "[supabase-app-user] Stelle sicher, dass der Benutzer '${APP_DB_USER}' für Datenbank '${APP_DB_NAME}' existiert …"

ROLE_ESC="$(escape_sql "$APP_DB_USER")"
PASS_ESC="$(escape_sql "$APP_DB_PASSWORD")"
DB_ESC="$(escape_sql "$APP_DB_NAME")"

for _ in {1..30}; do
  if $COMPOSE_CMD exec db pg_isready >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if [[ "${ready:-0}" -ne 1 ]]; then
  echo "[supabase-app-user] pg_isready blieb erfolglos – konnte Supabase-DB nicht erreichen." >&2
  exit 1
fi

DB_OWNER="$($COMPOSE_CMD exec -T db psql -U postgres -d postgres -Atqc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = '${DB_ESC}' LIMIT 1;" 2>/dev/null | tr -d '\r')"
DB_SUPERUSER="${DB_OWNER:-${POSTGRES_SUPERUSER:-${POSTGRES_USER:-postgres}}}"

$COMPOSE_CMD exec -T db psql -U "$DB_SUPERUSER" -d "$APP_DB_NAME" <<SQL
DO \$\$
DECLARE
  role_name text := '${ROLE_ESC}';
  role_pass text := '${PASS_ESC}';
  target_db text := '${DB_ESC}';
BEGIN
  IF target_db IS NULL OR target_db = '' THEN
    RAISE EXCEPTION 'APP_DB_NAME is empty';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', role_name, role_pass);
  ELSE
    EXECUTE format('ALTER ROLE %I WITH PASSWORD %L LOGIN', role_name, role_pass);
  END IF;

  EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', target_db, role_name);
  EXECUTE format('GRANT USAGE, CREATE ON SCHEMA public TO %I', role_name);
  EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO %I', role_name);
  EXECUTE format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO %I', role_name);
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO %I', role_name);
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO %I', role_name);
END \$\$;
SQL

echo "[supabase-app-user] Benutzer '${APP_DB_USER}' ist einsatzbereit."


