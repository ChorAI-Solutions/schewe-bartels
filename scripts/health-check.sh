#!/usr/bin/env bash
set -euo pipefail

# Führt HTTP-Health-Checks für Web, n8n und Mailpit aus.
# Verwendung: scripts/health-check.sh [--quiet]

QUIET="${1:-}"

check() {
  local name="$1"
  local url="$2"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 "$url" 2>/dev/null || echo "000")"
  if [[ "$QUIET" == "--quiet" ]]; then
    echo "$name: $code"
  else
    if [[ "$code" == "200" ]]; then
      echo "  ✓ $name: $code"
    else
      echo "  ✗ $name: $code (erwartet 200)"
    fi
  fi
  [[ "$code" == "200" ]]
}

echo "[health-check] Prüfe Dienste …"
failed=0
check "Web /api/health" "http://127.0.0.1:3000/api/health" || failed=1
check "n8n :5678"       "http://127.0.0.1:5678/"          || failed=1
check "Mailpit :8025"   "http://127.0.0.1:8025/"         || failed=1
echo "[health-check] Fertig."
exit $failed
