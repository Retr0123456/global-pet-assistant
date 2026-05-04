#!/usr/bin/env bash
set -euo pipefail

SWITCH_PATH="${CODEX_PET_EVENTS_DISABLE_FILE:-$HOME/.codex/global-pet-assistant-disabled}"
COMMAND="${1:-status}"

case "$COMMAND" in
  enable)
    rm -f "$SWITCH_PATH"
    echo "Codex pet event push is enabled."
    ;;
  disable)
    mkdir -p "$(dirname "$SWITCH_PATH")"
    touch "$SWITCH_PATH"
    echo "Codex pet event push is disabled."
    ;;
  status)
    if [[ -f "$SWITCH_PATH" ]]; then
      echo "disabled"
    else
      echo "enabled"
    fi
    ;;
  *)
    echo "Usage: Tools/codex-pet-events.sh [enable|disable|status]" >&2
    exit 2
    ;;
esac
