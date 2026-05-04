#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PETCTL_COMMAND="${PETCTL:-swift run petctl}"
PET_SOURCE="${PET_SOURCE:-claude-code}"
PET_DEDUPE_KEY="${PET_DEDUPE_KEY:-claude:global-pet-assistant}"
PET_MESSAGE="${PET_MESSAGE:-Claude Code is working in global-pet-assistant}"
PET_TTL_MS="${PET_TTL_MS:-30000}"
EVENT="${1:-running}"

run_petctl() {
  ${PETCTL_COMMAND} "$@"
}

case "$EVENT" in
  running|start|started)
    run_petctl state running \
      --source "$PET_SOURCE" \
      --message "$PET_MESSAGE" \
      --ttl-ms "$PET_TTL_MS" \
      --dedupe-key "$PET_DEDUPE_KEY"
    ;;
  success|complete|completed)
    run_petctl notify \
      --source "$PET_SOURCE" \
      --level success \
      --title "${PET_TITLE:-Claude Code task complete}" \
      --message "${PET_MESSAGE:-Review the changes in global-pet-assistant}" \
      --dedupe-key "$PET_DEDUPE_KEY" \
      --action-folder "${PET_ACTION_FOLDER:-/Users/ryanchen/codespace/global-pet-assistant}"
    ;;
  waiting|input)
    run_petctl notify \
      --source "$PET_SOURCE" \
      --level warning \
      --title "${PET_TITLE:-Claude Code is waiting}" \
      --message "${PET_MESSAGE:-Open Claude Code and review the prompt}" \
      --ttl-ms "$PET_TTL_MS" \
      --dedupe-key "$PET_DEDUPE_KEY"
    ;;
  failed|failure|danger)
    run_petctl notify \
      --source "$PET_SOURCE" \
      --level danger \
      --title "${PET_TITLE:-Claude Code task failed}" \
      --message "${PET_MESSAGE:-Open the repo and inspect the failure}" \
      --dedupe-key "$PET_DEDUPE_KEY" \
      --action-folder "${PET_ACTION_FOLDER:-/Users/ryanchen/codespace/global-pet-assistant}"
    ;;
  *)
    echo "Unknown Claude task event: $EVENT" >&2
    exit 2
    ;;
esac
