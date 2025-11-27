#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const readline = require("readline");

const ROOT_ENV_PATH = path.resolve(process.cwd(), ".env");
const SUPABASE_DIR = path.resolve(process.cwd(), "docker/supabase");
const SUPABASE_ENV_PATH = path.join(SUPABASE_DIR, ".env");
const SUPABASE_ENV_EXAMPLE_PATH = path.join(SUPABASE_DIR, ".env.example");
const SUPPORTED_SCOPES = new Set(["dev", "prod"]);
const INTERACTIVE_SUPABASE_KEYS = new Set([
  "JWT_SECRET",
  "ANON_KEY",
  "SERVICE_ROLE_KEY",
  "DASHBOARD_USERNAME",
  "DASHBOARD_PASSWORD",
  "SECRET_KEY_BASE",
  "VAULT_ENC_KEY",
  "PG_META_CRYPTO_KEY",
]);

function resolveScope() {
  const envScope = (process.env.SETUP_ENV_SCOPE || "").toLowerCase();
  if (SUPPORTED_SCOPES.has(envScope)) {
    return envScope;
  }

  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg.startsWith("--scope=")) {
      const value = arg.split("=")[1].toLowerCase();
      if (SUPPORTED_SCOPES.has(value)) {
        return value;
      }
    }
    if (arg === "--scope" || arg === "-s") {
      const value = (args[i + 1] || "").toLowerCase();
      if (SUPPORTED_SCOPES.has(value)) {
        return value;
      }
    }
  }

  return "dev";
}

function parseTemplate(content) {
  const lines = content.split(/\r?\n/);
  const entries = [];
  let pendingMeta = null;

  for (const line of lines) {
    const metaMatch = line.match(/^#\s*@meta\s+(.*)$/);
    if (metaMatch) {
      try {
        pendingMeta = JSON.parse(metaMatch[1]);
      } catch (error) {
        const details =
          error instanceof Error ? error.message : String(error || "");
        throw new Error(`Ungültiger @meta Block: ${metaMatch[1]} (${details})`);
      }
      continue;
    }

    const varMatch = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (varMatch) {
      entries.push({
        type: "var",
        key: varMatch[1],
        rawValue: varMatch[2],
        meta: pendingMeta,
      });
      pendingMeta = null;
      continue;
    }

    entries.push({ type: "text", value: line });
    pendingMeta = null;
  }

  return entries;
}

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

function defaultForScope(entry, scope) {
  if (entry.meta?.defaults && entry.meta.defaults[scope] !== undefined) {
    return String(entry.meta.defaults[scope]);
  }
  return entry.rawValue ?? "";
}

function scopeMatches(entry, scope) {
  if (!entry.meta?.scopes || entry.meta.scopes.length === 0) {
    return true;
  }
  return entry.meta.scopes.includes(scope);
}

function promptValue(entry, scope, rl, currentValue) {
  const fallback = defaultForScope(entry, scope);
  const defaultValue = currentValue ?? fallback;
  const description = entry.meta?.description || entry.key;
  const hint =
    defaultValue !== undefined && defaultValue !== ""
      ? ` [${defaultValue}]`
      : " [leer]";
  const question = `${description} (${entry.key}, Scope: ${scope})${hint}: `;

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      const trimmed = answer.trim();
      if (trimmed === ".") {
        resolve("");
        return;
      }
      if (answer === "") {
        resolve(defaultValue);
        return;
      }
      resolve(answer);
    });
  });
}

function promptYesNo(rl, question, defaultAnswer = false) {
  const suffix = defaultAnswer ? " (J/n)" : " (j/N)";
  return new Promise((resolve) => {
    rl.question(`${question}${suffix} `, (answer) => {
      const normalized = answer.trim().toLowerCase();
      if (!normalized) {
        resolve(defaultAnswer);
        return;
      }
      resolve(normalized === "j" || normalized === "ja" || normalized === "y");
    });
  });
}

function resolveApiExternalUrl(rootEnv) {
  if (rootEnv.SUPABASE_DOMAIN) {
    return `https://${rootEnv.SUPABASE_DOMAIN}`;
  }

  const host = rootEnv.SUPABASE_KONG_HOST || "localhost";
  const port = rootEnv.SUPABASE_KONG_PORT || "8000";
  return `http://${host}:${port}`;
}

function isPlaceholder(value) {
  if (!value) {
    return true;
  }
  const normalized = value.trim().toLowerCase();
  if (!normalized) {
    return true;
  }
  return (
    normalized.includes("change") ||
    normalized.includes("replace") ||
    normalized.includes("example")
  );
}

function generateJwtSecret() {
  return toBase64Url(crypto.randomBytes(48));
}

function toBase64Url(input) {
  const buffer = Buffer.isBuffer(input) ? input : Buffer.from(input);
  return buffer
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function signJwt(payload, secret) {
  const header = { alg: "HS256", typ: "JWT" };
  const headerEncoded = toBase64Url(JSON.stringify(header));
  const payloadEncoded = toBase64Url(JSON.stringify(payload));
  const data = `${headerEncoded}.${payloadEncoded}`;
  const signature = crypto
    .createHmac("sha256", secret)
    .update(data)
    .digest("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  return `${data}.${signature}`;
}

async function promptSupabaseSecrets(options) {
  const { scope, rl, supabaseEnv, supabaseFileJustCreated } = options;
  if (!rl) {
    return;
  }

  const templateContent = fs.readFileSync(SUPABASE_ENV_EXAMPLE_PATH, "utf8");
  const entries = parseTemplate(templateContent);
  const manualEntries = entries.filter(
    (entry) =>
      entry.type === "var" &&
      scopeMatches(entry, scope) &&
      INTERACTIVE_SUPABASE_KEYS.has(entry.key)
  );

  if (!manualEntries.length) {
    return;
  }

  const shouldAsk =
    fs.existsSync(SUPABASE_ENV_PATH) && !supabaseFileJustCreated;
  const keepExisting =
    shouldAsk &&
    (await promptYesNo(
      rl,
      "docker/supabase/.env existiert bereits. Vorhandene Secrets behalten?",
      true
    ));

  if (keepExisting) {
    console.log("Supabase Secrets bleiben unverändert.");
    return;
  }

  const updates = {};
  for (const entry of manualEntries) {
    const currentValue = supabaseEnv[entry.key];
    updates[entry.key] = await promptValue(entry, scope, rl, currentValue);
  }

  updateEnvFile(SUPABASE_ENV_PATH, updates);
}

async function ensureJwtKeys(options) {
  const { scope, interactive, rl, supabaseEnv, rootEnv } = options;
  const shouldEnforce =
    scope === "prod" || process.env.SUPABASE_GENERATE_JWT_KEYS === "1";
  if (!shouldEnforce) {
    return;
  }

  let jwtSecret = supabaseEnv.JWT_SECRET;
  const updates = {};
  let secretRotated = false;

  if (isPlaceholder(jwtSecret) || (jwtSecret || "").length < 32) {
    jwtSecret = generateJwtSecret();
    updates.JWT_SECRET = jwtSecret;
    secretRotated = true;
    console.log("🔐 Neues JWT_SECRET generiert.");
  }

  let needsAnon = secretRotated || isPlaceholder(supabaseEnv.ANON_KEY);
  let needsService =
    secretRotated || isPlaceholder(supabaseEnv.SERVICE_ROLE_KEY);

  if (!needsAnon && !needsService) {
    if (interactive && rl) {
      const rotate = await promptYesNo(
        rl,
        "Bestehende JWT-basierten Supabase Keys ersetzen?",
        false
      );
      if (!rotate) {
        console.log(
          "ℹ️  Bestehende JWT-basierten Supabase Keys bleiben erhalten."
        );
        if (Object.keys(updates).length > 0) {
          updateEnvFile(SUPABASE_ENV_PATH, updates);
        }
        return;
      }
      needsAnon = true;
      needsService = true;
    } else if (Object.keys(updates).length > 0) {
      updateEnvFile(SUPABASE_ENV_PATH, updates);
      console.log("✅ JWT_SECRET aktualisiert.");
      return;
    } else {
      console.log(
        "ℹ️  Bestehende JWT-basierten Supabase Keys bleiben erhalten."
      );
      return;
    }
  }

  if (!jwtSecret) {
    console.error(
      "JWT_SECRET konnte nicht ermittelt werden – überspringe Key-Generierung."
    );
    return;
  }

  const issuer =
    rootEnv.SUPABASE_DOMAIN || supabaseEnv.SUPABASE_DOMAIN
      ? `https://${rootEnv.SUPABASE_DOMAIN || supabaseEnv.SUPABASE_DOMAIN}`
      : "supabase-selfhosted";
  const now = Math.floor(Date.now() / 1000);
  const expiresInYears = Number(process.env.SUPABASE_JWT_KEY_YEARS || 10);
  const exp = now + expiresInYears * 365 * 24 * 60 * 60;

  const anonPayload = {
    role: "anon",
    iss: issuer,
    aud: "authenticated",
    iat: now,
    exp,
  };
  const servicePayload = {
    role: "service_role",
    iss: issuer,
    aud: "authenticated",
    iat: now,
    exp,
  };

  if (needsAnon) {
    updates.ANON_KEY = signJwt(anonPayload, jwtSecret);
  }
  if (needsService) {
    updates.SERVICE_ROLE_KEY = signJwt(servicePayload, jwtSecret);
  }

  updateEnvFile(SUPABASE_ENV_PATH, updates);
  console.log("✅ JWT-basierte Supabase Keys aktualisiert.");
}

async function main() {
  if (!fs.existsSync(ROOT_ENV_PATH)) {
    console.error(
      ".env wurde noch nicht erzeugt. Bitte zuerst make setup-dev oder make setup-prod ausführen."
    );
    process.exit(1);
  }

  const scope = resolveScope();
  const interactive =
    scope === "prod" || process.env.SETUP_SUPABASE_INTERACTIVE === "1";
  const rl = interactive
    ? readline.createInterface({ input: process.stdin, output: process.stdout })
    : null;

  try {
    const rootEnv = parseEnv(ROOT_ENV_PATH);
    const created = ensureSupabaseEnvFile();
    let supabaseEnv = parseEnv(SUPABASE_ENV_PATH);

    if (interactive) {
      await promptSupabaseSecrets({
        scope,
        rl,
        supabaseEnv,
        supabaseFileJustCreated: created,
      });
      supabaseEnv = parseEnv(SUPABASE_ENV_PATH);
    }

    const syncUpdates = {
      POSTGRES_PASSWORD:
        rootEnv.POSTGRES_PASSWORD ?? supabaseEnv.POSTGRES_PASSWORD,
      POSTGRES_DB: rootEnv.POSTGRES_DB ?? supabaseEnv.POSTGRES_DB,
      POSTGRES_PORT: rootEnv.POSTGRES_PORT ?? supabaseEnv.POSTGRES_PORT,
      POSTGRES_HOST: rootEnv.POSTGRES_HOST ?? supabaseEnv.POSTGRES_HOST,
      POSTGRES_DIRECT_PORT:
        rootEnv.POSTGRES_DIRECT_PORT ?? supabaseEnv.POSTGRES_DIRECT_PORT,
      POOLER_PROXY_PORT_TRANSACTION:
        rootEnv.SUPABASE_POOLER_PORT ??
        supabaseEnv.POOLER_PROXY_PORT_TRANSACTION,
      KONG_HTTP_PORT:
        rootEnv.SUPABASE_KONG_PORT ?? supabaseEnv.KONG_HTTP_PORT,
      SITE_URL: rootEnv.NEXT_PUBLIC_SITE_URL ?? supabaseEnv.SITE_URL,
      API_EXTERNAL_URL: resolveApiExternalUrl(rootEnv),
    };

    updateEnvFile(SUPABASE_ENV_PATH, syncUpdates);
    supabaseEnv = parseEnv(SUPABASE_ENV_PATH);

    await ensureJwtKeys({
      scope,
      interactive,
      rl,
      supabaseEnv,
      rootEnv,
    });

    if (created) {
      console.log("Supabase .env erstellt unter docker/supabase/.env.");
    }
    console.log("Supabase .env synchronisiert.");
  } catch (error) {
    console.error(error.message || error);
    process.exitCode = 1;
  } finally {
    rl?.close();
  }
}

main();
