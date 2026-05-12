#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "agent hook installers: shell syntax"
bash -n plugins/codex/install.sh
bash -n plugins/claude-code/install.sh
bash -n Tools/install-codex-hooks.sh
bash -n Tools/install-claude-code-hooks.sh

echo "agent hook installers: template json"
python3 - <<'PY'
import json
from pathlib import Path

for path in [
    Path("plugins/codex/templates/hooks.json"),
    Path("plugins/claude-code/templates/settings.json"),
]:
    json.loads(path.read_text(encoding="utf-8"))
PY

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT
fake_bridge="$tmp_home/global-pet-agent-bridge"
cat > "$fake_bridge" <<'SH'
#!/usr/bin/env sh
exit 0
SH
chmod +x "$fake_bridge"

echo "agent hook installers: codex clean install"
CODEX_HOME="$tmp_home/codex" \
  GLOBAL_PET_AGENT_BRIDGE="$fake_bridge" \
  plugins/codex/install.sh >/tmp/global-pet-assistant-codex-install.log

echo "agent hook installers: codex idempotent reinstall"
CODEX_HOME="$tmp_home/codex" \
  GLOBAL_PET_AGENT_BRIDGE="$fake_bridge" \
  plugins/codex/install.sh >/tmp/global-pet-assistant-codex-reinstall.log

python3 - "$tmp_home/codex/config.toml" "$tmp_home/codex/hooks.json" "$fake_bridge" <<'PY'
import json
import sys
from pathlib import Path

config = Path(sys.argv[1]).read_text(encoding="utf-8")
hooks = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))["hooks"]
bridge = sys.argv[3]
expected = {
    "SessionStart",
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "PermissionRequest",
    "Stop",
}
if "codex_hooks = true" not in config:
    raise SystemExit("Codex config did not enable codex_hooks")
if set(hooks) != expected:
    raise SystemExit(f"Unexpected Codex hook events: {sorted(hooks)}")
for event_name in expected:
    commands = [
        entry["command"]
        for group in hooks[event_name]
        for entry in group.get("hooks", [])
        if isinstance(entry, dict)
    ]
    managed = [command for command in commands if "--source codex" in command]
    if managed != [f'"{bridge}" --source codex']:
        raise SystemExit(f"Expected one managed Codex command for {event_name}, got {managed}")
PY

echo "agent hook installers: claude-code clean install"
CLAUDE_HOME="$tmp_home/claude" \
  GLOBAL_PET_AGENT_BRIDGE="$fake_bridge" \
  plugins/claude-code/install.sh >/tmp/global-pet-assistant-claude-install.log

echo "agent hook installers: claude-code idempotent reinstall"
CLAUDE_HOME="$tmp_home/claude" \
  GLOBAL_PET_AGENT_BRIDGE="$fake_bridge" \
  plugins/claude-code/install.sh >/tmp/global-pet-assistant-claude-reinstall.log

python3 - "$tmp_home/claude/settings.json" "$fake_bridge" <<'PY'
import json
import sys
from pathlib import Path

settings = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
hooks = settings["hooks"]
bridge = sys.argv[2]
expected = {
    "SessionStart",
    "UserPromptSubmit",
    "PreToolUse",
    "PermissionRequest",
    "PermissionDenied",
    "PostToolUse",
    "PostToolUseFailure",
    "PostToolBatch",
    "Notification",
    "SubagentStart",
    "SubagentStop",
    "Stop",
    "StopFailure",
    "SessionEnd",
}
if set(hooks) != expected:
    raise SystemExit(f"Unexpected Claude Code hook events: {sorted(hooks)}")
for event_name in expected:
    commands = [
        entry["command"]
        for group in hooks[event_name]
        for entry in group.get("hooks", [])
        if isinstance(entry, dict)
    ]
    managed = [command for command in commands if "--source claude-code" in command]
    if managed != [f'"{bridge}" --source claude-code']:
        raise SystemExit(f"Expected one managed Claude Code command for {event_name}, got {managed}")
PY

echo "agent hook installers verified"
