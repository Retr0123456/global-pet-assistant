#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOK_DIR="$CODEX_HOME/hooks/global-pet-assistant"
HOOK_SCRIPT="$HOOK_DIR/codex-pet-event.py"
CONFIG_FILE="$CODEX_HOME/config.toml"
HOOKS_FILE="$CODEX_HOME/hooks.json"
FORCE="${FORCE:-0}"

mkdir -p "$HOOK_DIR"
cp "$ROOT_DIR/examples/codex-hooks/hooks/codex-pet-event.py" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"

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

if [[ -f "$HOOKS_FILE" ]] && ! grep -q 'global-pet-assistant' "$HOOKS_FILE" && [[ "$FORCE" != "1" ]]; then
  echo "Refusing to overwrite existing $HOOKS_FILE. Set FORCE=1 to replace it." >&2
  exit 1
fi

escaped_hook_script="${HOOK_SCRIPT//\\/\\\\}"
escaped_hook_script="${escaped_hook_script//\"/\\\"}"
cat > "$HOOKS_FILE" <<JSON
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \\"$escaped_hook_script\\"",
            "timeout": 5,
            "statusMessage": "Updating pet session state"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \\"$escaped_hook_script\\"",
            "timeout": 5,
            "statusMessage": "Updating pet running state"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \\"$escaped_hook_script\\"",
            "timeout": 5,
            "statusMessage": "Updating pet approval state"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \\"$escaped_hook_script\\"",
            "timeout": 5,
            "statusMessage": "Updating pet review state"
          }
        ]
      }
    ]
  }
}
JSON

echo "Installed Global Pet Assistant Codex hooks:"
echo "  $HOOK_SCRIPT"
echo "  $HOOKS_FILE"
echo "Restart Codex sessions to load the user-level hook."
