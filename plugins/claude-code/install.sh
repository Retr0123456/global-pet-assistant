#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-$CLAUDE_HOME/settings.json}"
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

mkdir -p "$(dirname "$SETTINGS_FILE")"

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

python3 - "$SETTINGS_FILE" "$BRIDGE_PATH" <<'PY'
import json
import os
import sys
from pathlib import Path

settings_file = Path(sys.argv[1])
bridge_path = sys.argv[2]
managed_needle = "global-pet-agent-bridge"
managed_source = "--source claude-code"
command = f'"{bridge_path}" --source claude-code'
events = [
    ("SessionStart", None, "Updating pet Claude Code session state"),
    ("UserPromptSubmit", None, "Updating pet Claude Code running state"),
    ("PreToolUse", "*", "Updating pet Claude Code tool state"),
    ("PermissionRequest", "*", "Updating pet Claude Code approval state"),
    ("PermissionDenied", "*", "Updating pet Claude Code denied-permission state"),
    ("PostToolUse", "*", "Updating pet Claude Code tool result"),
    ("PostToolUseFailure", "*", "Updating pet Claude Code tool failure"),
    ("PostToolBatch", None, "Updating pet Claude Code tool batch state"),
    ("Notification", None, "Updating pet Claude Code notification state"),
    ("SubagentStart", "*", "Updating pet Claude Code subagent state"),
    ("SubagentStop", "*", "Updating pet Claude Code subagent completion"),
    ("Stop", None, "Updating pet Claude Code completion state"),
    ("StopFailure", None, "Updating pet Claude Code failure state"),
    ("SessionEnd", "*", "Updating pet Claude Code session end state"),
]

if settings_file.exists():
    with settings_file.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
else:
    payload = {
        "$schema": "https://json.schemastore.org/claude-code-settings.json"
    }

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
            if managed_needle not in entry_command or managed_source not in entry_command:
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

settings_file.parent.mkdir(parents=True, exist_ok=True)
tmp_file = settings_file.with_suffix(settings_file.suffix + ".tmp")
with tmp_file.open("w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp_file, settings_file)
PY

echo "Installed Global Pet Assistant Claude Code hooks:"
echo "  bridge:   $BRIDGE_PATH"
echo "  settings: $SETTINGS_FILE"
echo "Restart Claude Code sessions to load the hook settings."
echo "Disable temporarily with: export GLOBAL_PET_ASSISTANT_DISABLE_AGENT_HOOKS=1"
