#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
SUPABASE_ENV_FILE="${ROOT_DIR}/docker/supabase/.env"
MATCH_FUNCTION_SQL="${ROOT_DIR}/supase-configs/createMatchFunction.sql"
COMPOSE_CMD="docker compose -f docker/supabase/docker-compose.yml --env-file docker/supabase/.env"

if [[ ! -f "$ENV_FILE" || ! -f "$SUPABASE_ENV_FILE" ]]; then
  echo "[supabase-vector] .env oder docker/supabase/.env fehlt – überspringe."
  exit 0
fi

if [[ ! -f "$MATCH_FUNCTION_SQL" ]]; then
  echo "[supabase-vector] SQL-Datei $MATCH_FUNCTION_SQL fehlt – kann match_documents nicht erstellen." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
source "$SUPABASE_ENV_FILE"
set +a

DB_NAME="${APP_DB_NAME:-${POSTGRES_DB:-}}"

if [[ -z "$DB_NAME" ]]; then
  echo "[supabase-vector] APP_DB_NAME/POSTGRES_DB nicht gesetzt – überspringe."
  exit 0
fi

echo "[supabase-vector] Stelle sicher, dass Extensions, Tabellen und RPCs installiert sind …"

for _ in {1..30}; do
  if $COMPOSE_CMD exec db pg_isready >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if [[ "${ready:-0}" -ne 1 ]]; then
  echo "[supabase-vector] pg_isready blieb erfolglos – konnte Supabase-DB nicht erreichen." >&2
  exit 1
fi

psql_exec() {
  $COMPOSE_CMD exec -T db psql -v ON_ERROR_STOP=1 -U supabase_admin -d "$DB_NAME" "$@"
}

# Ensure extensions & schema permissions
psql_exec <<'SQL'
CREATE SCHEMA IF NOT EXISTS extensions AUTHORIZATION supabase_admin;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
ALTER EXTENSION "uuid-ossp" SET SCHEMA extensions;
ALTER EXTENSION vector SET SCHEMA extensions;
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;
GRANT USAGE ON TYPE extensions.vector TO postgres, anon, authenticated, service_role;
SQL

# Ensure vector-ready documents table
psql_exec <<'SQL'
CREATE TABLE IF NOT EXISTS public.documents_pg (
  id bigserial PRIMARY KEY,
  content text,
  metadata jsonb,
  embedding extensions.vector(1536)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'documents_pg_embedding_idx'
  ) THEN
    EXECUTE 'CREATE INDEX documents_pg_embedding_idx ON public.documents_pg USING ivfflat (embedding vector_cosine_ops) WITH (lists=100)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'documents_pg_metadata_file_id_idx'
  ) THEN
    EXECUTE 'CREATE INDEX documents_pg_metadata_file_id_idx ON public.documents_pg ((metadata ->> ''file_id''))';
  END IF;
END$$;
SQL

# Apply latest match_documents implementation
cat "$MATCH_FUNCTION_SQL" | psql_exec -f -

# Enforce search_path + grants for API roles
psql_exec <<SQL
ALTER FUNCTION public.match_documents(vector(1536), integer, jsonb)
  SET search_path = public, extensions;

ALTER ROLE anon IN DATABASE "${DB_NAME}" SET search_path = public, extensions;
ALTER ROLE authenticated IN DATABASE "${DB_NAME}" SET search_path = public, extensions;
ALTER ROLE service_role IN DATABASE "${DB_NAME}" SET search_path = public, extensions;

GRANT ALL ON TABLE public.documents_pg TO service_role;
GRANT SELECT ON TABLE public.documents_pg TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.documents_pg_id_seq TO service_role;
SQL

echo "[supabase-vector] Vector-Store ist bereit."



