#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */
const fs = require("fs");
const path = require("path");
const readline = require("readline");

const TEMPLATE_PATH = path.resolve(process.cwd(), "env.template");
const OUTPUT_PATH = path.resolve(process.cwd(), ".env");
const SUPPORTED_SCOPES = new Set(["dev", "prod"]);

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
      } catch (parseError) {
        const details =
          parseError instanceof Error
            ? parseError.message
            : String(parseError);
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

function defaultForScope(entry, scope) {
  if (entry.meta?.defaults && entry.meta.defaults[scope] !== undefined) {
    return String(entry.meta.defaults[scope]);
  }
  return entry.rawValue ?? "";
}

function scopeMatches(entry, scope) {
  if (!entry.meta || !Array.isArray(entry.meta.scopes)) {
    return true;
  }
  return entry.meta.scopes.includes(scope);
}

async function promptValue(entry, scope, rl) {
  const defaultValue = defaultForScope(entry, scope);
  const description = entry.meta?.description || entry.key;
  const hint =
    defaultValue !== undefined && defaultValue !== ""
      ? ` [${defaultValue}]`
      : " [leer]";

  const question = `${description} (${entry.key}, Scope: ${scope})${hint}: `;
  const answer = await new Promise((resolve) => rl.question(question, resolve));
  const trimmed = answer.trim();

  if (trimmed === ".") {
    return "";
  }
  if (answer === "") {
    return defaultValue;
  }
  return answer;
}

async function main() {
  if (!fs.existsSync(TEMPLATE_PATH)) {
    console.error(`env.template nicht gefunden (${TEMPLATE_PATH})`);
    process.exit(1);
  }

  const scope = resolveScope();
  const template = fs.readFileSync(TEMPLATE_PATH, "utf8");
  const entries = parseTemplate(template);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    const outputLines = [
      `# Erstellt von scripts/setup-env.cjs (Scope: ${scope})`,
      `# ${new Date().toISOString()}`,
    ];

    for (const entry of entries) {
      if (entry.type === "text") {
        outputLines.push(entry.value);
        continue;
      }

      if (entry.type === "var" && scopeMatches(entry, scope)) {
        const value = await promptValue(entry, scope, rl);
        outputLines.push(`${entry.key}=${value}`);
      } else if (entry.type === "var") {
        outputLines.push(`${entry.key}=${entry.rawValue ?? ""}`);
      }
    }

    if (!outputLines[outputLines.length - 1].endsWith("\n")) {
      outputLines.push("");
    }

    fs.writeFileSync(OUTPUT_PATH, outputLines.join("\n"), "utf8");
    console.log(`.env aktualisiert (Scope: ${scope})`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  } finally {
    rl.close();
  }
}

main();

