#!/usr/bin/env bash
set -euo pipefail

REMOTE_NAME="${1:-origin}"

log() {
  printf '[git-bootstrap] %s\n' "$1"
}

prompt_config() {
  local key="$1"
  local label="$2"
  local current
  current="$(git config --get "$key" 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    log "$label bereits gesetzt: $current"
    return
  fi

  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$label: " value
    value="${value// / }"
  done
  git config "$key" "$value"
  log "$label gesetzt auf: $value"
}

ensure_git_config() {
  prompt_config "user.name" "Git Benutzername"
  prompt_config "user.email" "Git E-Mail"
}

commit_if_needed() {
  git add -A
  if git diff --cached --quiet; then
    log "Keine neuen Änderungen zum Commit – überspringe Commit-Schritt."
    return
  fi

  local default_message="Initial project setup"
  read -r -p "Commit-Nachricht [${default_message}]: " commit_msg
  commit_msg="${commit_msg:-$default_message}"
  git commit -m "$commit_msg"
  log "Commit erstellt: $commit_msg"
}

push_branch() {
  log "Push zu $REMOTE_NAME main"
  git push -u "$REMOTE_NAME" main
}

main() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Dieses Skript muss im Git-Repository ausgeführt werden." >&2
    exit 1
  fi

  ensure_git_config
  git branch -M main
  commit_if_needed
  push_branch
}

main "$@"

