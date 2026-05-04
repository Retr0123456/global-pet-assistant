#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT_DIR/.codex/hooks/codex-pet-event.py"
export PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/gpa-codex-hook-pycache"

python3 -m py_compile "$HOOK"

check_event() {
  local name="$1"
  local expected_type="$2"
  local expected_state_or_level="$3"
  local payload="$4"

  local output
  output="$(printf '%s' "$payload" | python3 "$HOOK" --print-event)"
  EVENT_OUTPUT="$output" EXPECTED_TYPE="$expected_type" EXPECTED_STATE_OR_LEVEL="$expected_state_or_level" python3 - <<'PY'
import json
import os
import sys

event = json.loads(os.environ["EVENT_OUTPUT"])
expected_type = os.environ["EXPECTED_TYPE"]
expected_state_or_level = os.environ["EXPECTED_STATE_OR_LEVEL"]
if event.get("type") != expected_type:
    sys.exit(f"Expected type {expected_type}, got {event.get('type')}")
if event.get("state") != expected_state_or_level and event.get("level") != expected_state_or_level:
    sys.exit(f"Expected state/level {expected_state_or_level}, got {event}")
if not event.get("source", "").startswith("codex-cli:"):
    sys.exit(f"Expected codex-cli source, got {event.get('source')}")
if not event.get("dedupeKey", "").startswith("codex:"):
    sys.exit(f"Expected codex dedupe key, got {event.get('dedupeKey')}")
PY
  echo "$name: ok"
}

check_event "SessionStart" "codex.session.start" "running" '{"hook_event_name":"SessionStart","session_id":"session-1234567890","source":"startup","cwd":"/tmp/repo"}'
check_event "UserPromptSubmit" "codex.turn.running" "running" '{"hook_event_name":"UserPromptSubmit","session_id":"session-1234567890","turn_id":"turn-1","cwd":"/tmp/repo","prompt":"Design personal knowledge base architecture"}'
check_event "PermissionRequest" "codex.permission.request" "warning" '{"hook_event_name":"PermissionRequest","session_id":"session-1234567890","turn_id":"turn-1","cwd":"/tmp/repo","tool_name":"Bash","tool_input":{"description":"Run outside sandbox","command":"swift test"}}'
check_event "Stop" "codex.turn.review" "success" '{"hook_event_name":"Stop","session_id":"session-1234567890","turn_id":"turn-1","cwd":"/tmp/repo","last_assistant_message":"Implementation complete. Please review."}'

echo "Codex hook event mapping verified."
