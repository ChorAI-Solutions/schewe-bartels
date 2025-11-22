#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */
const fs = require("fs");
const path = require("path");

const ROOT_ENV_PATH = path.resolve(process.cwd(), ".env");
const SUPABASE_DIR = path.resolve(process.cwd(), "docker/supabase");
const SUPABASE_ENV_PATH = path.join(SUPABASE_DIR, ".env");
const SUPABASE_ENV_EXAMPLE_PATH = path.join(SUPABASE_DIR, ".env.example");

function parseEnv(filePath) {
  if (!fs.existsSync(filePath)) {
    return {};
  }

  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.split(/\r?\n/);
  const entries = {};

  for (const line of lines) {
    if (!line || line.startsWith("#")) {
      continue;
    }
    const match = line.match(/^\s*([A-Z0-9_]+)=(.*)$/);
    if (match) {
      entries[match[1]] = match[2];
    }
  }

  return entries;
}

function updateEnvFile(filePath, updates) {
  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.split(/\r?\n/);
  const applied = new Set();

  const nextLines = lines.map((line) => {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match) {
      return line;
    }
    const key = match[1];
    if (!(key in updates) || updates[key] === undefined) {
      return line;
    }
    applied.add(key);
    return `${key}=${updates[key]}`;
  });

  for (const [key, value] of Object.entries(updates)) {
    if (!applied.has(key) && value !== undefined) {
      nextLines.push(`${key}=${value}`);
    }
  }

  fs.writeFileSync(filePath, nextLines.join("\n"), "utf8");
}

function ensureSupabaseEnvFile() {
  if (!fs.existsSync(SUPABASE_ENV_EXAMPLE_PATH)) {
    console.error(
      `docker/supabase/.env.example fehlt (${SUPABASE_ENV_EXAMPLE_PATH}).`
    );
    process.exit(1);
  }

  if (!fs.existsSync(SUPABASE_ENV_PATH)) {
    fs.copyFileSync(SUPABASE_ENV_EXAMPLE_PATH, SUPABASE_ENV_PATH);
    return true;
  }

  return false;
}

function resolveApiExternalUrl(rootEnv) {
  if (rootEnv.SUPABASE_DOMAIN) {
    return `https://${rootEnv.SUPABASE_DOMAIN}`;
  }

  const host = rootEnv.SUPABASE_KONG_HOST || "localhost";
  const port = rootEnv.SUPABASE_KONG_PORT || "8000";
  return `http://${host}:${port}`;
}

function main() {
  if (!fs.existsSync(ROOT_ENV_PATH)) {
    console.error(
      ".env wurde noch nicht erzeugt. Bitte zuerst make setup-dev oder make setup-prod ausführen."
    );
    process.exit(1);
  }

  const rootEnv = parseEnv(ROOT_ENV_PATH);
  const created = ensureSupabaseEnvFile();
  const supabaseEnvBefore = parseEnv(SUPABASE_ENV_PATH);

  const updates = {
    POSTGRES_PASSWORD:
      rootEnv.POSTGRES_PASSWORD ?? supabaseEnvBefore.POSTGRES_PASSWORD,
    POSTGRES_DB: rootEnv.POSTGRES_DB ?? supabaseEnvBefore.POSTGRES_DB,
    POSTGRES_PORT: rootEnv.POSTGRES_PORT ?? supabaseEnvBefore.POSTGRES_PORT,
    POOLER_PROXY_PORT_TRANSACTION:
      rootEnv.SUPABASE_POOLER_PORT ??
      supabaseEnvBefore.POOLER_PROXY_PORT_TRANSACTION,
    KONG_HTTP_PORT:
      rootEnv.SUPABASE_KONG_PORT ?? supabaseEnvBefore.KONG_HTTP_PORT,
    SITE_URL: rootEnv.NEXT_PUBLIC_SITE_URL ?? supabaseEnvBefore.SITE_URL,
    API_EXTERNAL_URL: resolveApiExternalUrl(rootEnv),
  };

  updateEnvFile(SUPABASE_ENV_PATH, updates);

  if (created) {
    console.log("Supabase .env erstellt unter docker/supabase/.env.");
    console.log(
      "⚠️  Bitte prüfe die Datei und ersetze Platzhalter (ANON_KEY, SERVICE_ROLE_KEY, JWT_SECRET, etc.), bevor du in Produktion gehst."
    );
  } else {
    console.log("Supabase .env synchronisiert.");
  }
}

main();


