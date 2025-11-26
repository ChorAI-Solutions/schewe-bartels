#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
SUPABASE_ENV_FILE="${ROOT_DIR}/docker/supabase/.env"
COMPOSE_CMD="docker compose -f docker/supabase/docker-compose.yml --env-file docker/supabase/.env"
TARGET_BUCKET="${SUPABASE_DEFAULT_BUCKET:-n8nRAG}"

log() {
  echo "[supabase-storage-bootstrap] $*"
}

if [[ ! -f "${ENV_FILE}" || ! -f "${SUPABASE_ENV_FILE}" ]]; then
  log ".env oder docker/supabase/.env fehlt – überspringe Bucket/Policy-Bootstrap."
  exit 0
fi

set -a
source "${ENV_FILE}"
source "${SUPABASE_ENV_FILE}"
set +a

DB_NAME="${APP_DB_NAME:-${POSTGRES_DB:-}}"

if [[ -z "${DB_NAME}" ]]; then
  log "APP_DB_NAME/POSTGRES_DB nicht gesetzt – überspringe."
  exit 0
fi

log "Stelle sicher, dass Supabase DB erreichbar ist …"
for _ in {1..30}; do
  if ${COMPOSE_CMD} exec db pg_isready >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if [[ "${ready:-0}" -ne 1 ]]; then
  log "pg_isready blieb erfolglos – breche ab."
  exit 1
fi

psql_exec() {
  ${COMPOSE_CMD} exec -T db psql -v ON_ERROR_STOP=1 -U supabase_admin -d "${DB_NAME}" "$@"
}

log "Erstelle/aktualisiere Storage-Bucket '${TARGET_BUCKET}' …"
psql_exec <<SQL
INSERT INTO storage.buckets (id, name, public)
VALUES ('${TARGET_BUCKET}', '${TARGET_BUCKET}', true)
ON CONFLICT (id)
DO UPDATE SET
  name = EXCLUDED.name,
  public = EXCLUDED.public;
SQL

log "Aktualisiere Storage-Policies für öffentlichen Zugriff …"
BUCKET_ESC="${TARGET_BUCKET//\'/\'\'}"
psql_exec <<SQL
DO \$\$
DECLARE
  bucket text := '${BUCKET_ESC}';
  select_policy text := format(
    'allow_public_read_%s',
    regexp_replace(lower(bucket), '[^a-z0-9_]', '_', 'g')
  );
  write_policy text := format(
    'allow_authenticated_write_%s',
    regexp_replace(lower(bucket), '[^a-z0-9_]', '_', 'g')
  );
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = select_policy
  ) THEN
    EXECUTE format(
      'CREATE POLICY %I ON storage.objects FOR SELECT TO anon USING (bucket_id = %L)',
      select_policy,
      bucket
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = write_policy
  ) THEN
    EXECUTE format(
      'CREATE POLICY %I ON storage.objects FOR ALL TO authenticated USING (bucket_id = %L) WITH CHECK (bucket_id = %L)',
      write_policy,
      bucket,
      bucket
    );
  END IF;
END
\$\$;
SQL

log "Supabase Storage ist vorbereitet."


