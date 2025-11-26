-- Ensure the Postgres service listens on all interfaces so the exposed
-- host port (POSTGRES_DIRECT_PORT) can be reached from outside Docker.
ALTER SYSTEM SET listen_addresses = '*';







