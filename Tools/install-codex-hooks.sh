#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"
HOOKS_FILE="$CODEX_HOME/hooks.json"
BUNDLED_BRIDGE="$ROOT_DIR/bin/global-pet-agent-bridge"
SOURCE_BRIDGE="$ROOT_DIR/.build/debug/global-pet-agent-bridge"
INSTALLED_APP_BRIDGE="/Applications/GlobalPetAssistant.app/Contents/Resources/bin/global-pet-agent-bridge"

if [[ -n "${GLOBAL_PET_AGENT_BRIDGE:-}" ]]; then
  BRIDGE_PATH="$GLOBAL_PET_AGENT_BRIDGE"
elif [[ -x "$BUNDLED_BRIDGE" ]]; then
  BRIDGE_PATH="$BUNDLED_BRIDGE"
elif [[ -x "$INSTALLED_APP_BRIDGE" ]]; then
  BRIDGE_PATH="$INSTALLED_APP_BRIDGE"
else
  BRIDGE_PATH="$SOURCE_BRIDGE"
fi

mkdir -p "$CODEX_HOME"

if [[ ! -x "$BRIDGE_PATH" ]]; then
  if [[ ! -f "$ROOT_DIR/Package.swift" ]]; then
    echo "global-pet-agent-bridge was not found. Install GlobalPetAssistant.app or set GLOBAL_PET_AGENT_BRIDGE." >&2
    exit 1
  fi
  swift build --package-path "$ROOT_DIR" --product global-pet-agent-bridge >/dev/null
fi

if [[ ! -x "$BRIDGE_PATH" ]]; then
  echo "global-pet-agent-bridge was not built at $BRIDGE_PATH" >&2
  exit 1
fi

touch "$CONFIG_FILE"
if grep -Eq '^[[:space:]]*codex_hooks[[:space:]]*=' "$CONFIG_FILE"; then
  perl -0pi -e 's/^[ \t]*codex_hooks[ \t]*=.*/codex_hooks = true/m' "$CONFIG_FILE"
elif grep -Eq '^\[features\][[:space:]]*$' "$CONFIG_FILE"; then
  tmp_file="$(mktemp)"
  awk '
    /^\[features\][[:space:]]*$/ && !inserted {
      print
      print "codex_hooks = true"
      inserted = 1
      next
    }
    { print }
  ' "$CONFIG_FILE" > "$tmp_file"
  mv "$tmp_file" "$CONFIG_FILE"
else
  {
    printf '\n'
    printf '[features]\n'
    printf 'codex_hooks = true\n'
  } >> "$CONFIG_FILE"
fi

python3 - "$HOOKS_FILE" "$BRIDGE_PATH" <<'PY'
import json
import os
import sys
from pathlib import Path

hooks_file = Path(sys.argv[1])
bridge_path = sys.argv[2]
managed_needle = "global-pet-agent-bridge"
command = f'"{bridge_path}" --source codex'
events = [
    ("SessionStart", "startup|resume", "Updating pet Codex session state"),
    ("UserPromptSubmit", None, "Updating pet Codex running state"),
    ("PreToolUse", None, "Updating pet Codex tool state"),
    ("PostToolUse", None, "Updating pet Codex tool result"),
    ("PermissionRequest", "*", "Updating pet Codex approval state"),
    ("Stop", None, "Updating pet Codex completion state"),
]

if hooks_file.exists():
    with hooks_file.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
else:
    payload = {}

hooks = payload.setdefault("hooks", {})

for event_name, matcher, status_message in events:
    next_groups = []
    for group in hooks.get(event_name, []):
        if not isinstance(group, dict):
            next_groups.append(group)
            continue
        entries = []
        for entry in group.get("hooks", []):
            entry_command = entry.get("command", "") if isinstance(entry, dict) else ""
            if managed_needle not in entry_command:
                entries.append(entry)
        if entries:
            group = dict(group)
            group["hooks"] = entries
            next_groups.append(group)
    managed_group = {
        "hooks": [{
            "type": "command",
            "command": command,
            "timeout": 5,
            "statusMessage": status_message
        }]
    }
    if matcher is not None:
        managed_group["matcher"] = matcher
    next_groups.append(managed_group)
    hooks[event_name] = next_groups

hooks_file.parent.mkdir(parents=True, exist_ok=True)
tmp_file = hooks_file.with_suffix(hooks_file.suffix + ".tmp")
with tmp_file.open("w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp_file, hooks_file)
PY

echo "Installed Global Pet Assistant Codex hooks:"
echo "  bridge: $BRIDGE_PATH"
echo "  hooks:  $HOOKS_FILE"
echo "Restart Codex sessions to load the user-level hook."
echo "Disable temporarily with: export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1"
