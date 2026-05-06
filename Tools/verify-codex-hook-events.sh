#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT_DIR/examples/codex-hooks/hooks/codex-pet-event.py"
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
if event.get("source") == "codex-cli:unknown":
    sys.exit(f"Expected stable session source, got {event.get('source')}")
if not event.get("dedupeKey", "").startswith("codex:"):
    sys.exit(f"Expected codex dedupe key, got {event.get('dedupeKey')}")
if event.get("cwd") != "/tmp/repo":
    sys.exit(f"Expected cwd /tmp/repo, got {event.get('cwd')}")
if "/tmp/repo" in str(event.get("message") or ""):
    sys.exit(f"Expected message preview without cwd, got {event.get('message')}")
PY
  echo "$name: ok"
}

check_event "SessionStart" "codex.session.start" "running" '{"hook_event_name":"SessionStart","session_id":"session-1234567890","source":"startup","cwd":"/tmp/repo"}'
check_event "UserPromptSubmit" "codex.turn.running" "running" '{"hook_event_name":"UserPromptSubmit","session_id":"session-1234567890","turn_id":"turn-1","cwd":"/tmp/repo","prompt":"Design personal knowledge base architecture"}'
check_event "PermissionRequest" "codex.permission.request" "warning" '{"hook_event_name":"PermissionRequest","session_id":"session-1234567890","turn_id":"turn-1","cwd":"/tmp/repo","tool_name":"Bash","tool_input":{"description":"Run outside sandbox","command":"swift test"}}'
check_event "Stop" "codex.turn.review" "success" '{"hook_event_name":"Stop","session_id":"session-1234567890","turn_id":"turn-1","cwd":"/tmp/repo","last_assistant_message":"Implementation complete. Please review."}'

source_a="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"019df293-afae-76d0-bcb1-c1c3bedb536d","cwd":"/tmp/repo","prompt":"A"}' | python3 "$HOOK" --print-event | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
source_b="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"019df293-afaf-76d0-bcb1-c1c3bedb536d","cwd":"/tmp/repo","prompt":"B"}' | python3 "$HOOK" --print-event | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
if [[ "$source_a" == "$source_b" ]]; then
  echo "Expected similar Codex session ids to map to distinct sources, got $source_a" >&2
  exit 1
fi
echo "Similar session source separation: ok"

thread_source="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","thread_id":"thread-abc","cwd":"/tmp/repo","prompt":"Thread alias"}' | python3 "$HOOK" --print-event | python3 -c 'import json,sys; print(json.load(sys.stdin)["dedupeKey"])')"
if [[ "$thread_source" != "codex:thread-abc" ]]; then
  echo "Expected thread_id alias to populate dedupe key, got $thread_source" >&2
  exit 1
fi
echo "thread_id alias mapping: ok"

fallback_source_a="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","cwd":"/tmp/repo","prompt":"Same cwd A"}' | env -u CODEX_SESSION_ID -u CODEX_THREAD_ID -u CODEX_CONVERSATION_ID KITTY_WINDOW_ID=41 KITTY_LISTEN_ON=unix:/tmp/mykitty python3 "$HOOK" --print-event | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
fallback_source_b="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","cwd":"/tmp/repo","prompt":"Same cwd B"}' | env -u CODEX_SESSION_ID -u CODEX_THREAD_ID -u CODEX_CONVERSATION_ID KITTY_WINDOW_ID=42 KITTY_LISTEN_ON=unix:/tmp/mykitty python3 "$HOOK" --print-event | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
if [[ "$fallback_source_a" == "$fallback_source_b" ]]; then
  echo "Expected fallback kitty windows in the same cwd to map to distinct sources, got $fallback_source_a" >&2
  exit 1
fi
echo "fallback kitty session separation: ok"

kitty_action="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"session-1234567890","cwd":"/tmp/repo","prompt":"Focus kitty"}' | KITTY_WINDOW_ID=42 KITTY_LISTEN_ON=unix:/tmp/mykitty python3 "$HOOK" --print-event)"
KITTY_ACTION="$kitty_action" python3 - <<'PY'
import json
import os
import sys

event = json.loads(os.environ["KITTY_ACTION"])
action = event.get("action") or {}
if action.get("type") != "focus_kitty_window":
    sys.exit(f"Expected focus_kitty_window action, got {action}")
if action.get("kittyWindowId") != "42":
    sys.exit(f"Expected kitty window 42, got {action}")
if action.get("kittyListenOn") != "unix:/tmp/mykitty":
    sys.exit(f"Expected kitty listen socket, got {action}")
PY
echo "kitty focus action mapping: ok"

SUBAGENT_TRANSCRIPT="$(mktemp "${TMPDIR:-/tmp}/gpa-codex-subagent-transcript.XXXXXX.jsonl")"
trap 'rm -f "$SUBAGENT_TRANSCRIPT"' EXIT
printf '%s\n' '{"timestamp":"2026-05-07T00:00:00Z","type":"session_meta","payload":{"id":"019df293-b000-76d0-bcb1-c1c3bedb536d","timestamp":"2026-05-07T00:00:00Z","cwd":"/tmp/repo","originator":"codex","cli_version":"test","source":{"subAgent":{"thread_spawn":{"parent_thread_id":"019df293-afae-76d0-bcb1-c1c3bedb536d","depth":1,"agent_nickname":"Scout","agent_role":"explorer"}}},"agent_nickname":"Scout","agent_role":"explorer","model_provider":"test-provider","base_instructions":null}}' > "$SUBAGENT_TRANSCRIPT"

parent_event="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"019df293-afae-76d0-bcb1-c1c3bedb536d","cwd":"/tmp/repo","prompt":"Parent prompt"}' | python3 "$HOOK" --print-event)"
subagent_event="$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"019df293-b000-76d0-bcb1-c1c3bedb536d","cwd":"/tmp/repo","prompt":"Inspect repo","transcript_path":"%s"}' "$SUBAGENT_TRANSCRIPT" | python3 "$HOOK" --print-event)"
PARENT_EVENT="$parent_event" SUBAGENT_EVENT="$subagent_event" python3 - <<'PY'
import json
import os
import sys

parent = json.loads(os.environ["PARENT_EVENT"])
subagent = json.loads(os.environ["SUBAGENT_EVENT"])
if subagent.get("source") != parent.get("source"):
    sys.exit(f"Expected subagent source to canonicalize to parent source, got {subagent}")
if subagent.get("dedupeKey") != "codex:019df293-afae-76d0-bcb1-c1c3bedb536d":
    sys.exit(f"Expected parent dedupe key, got {subagent.get('dedupeKey')}")
if "Scout (explorer)" not in str(subagent.get("message") or ""):
    sys.exit(f"Expected subagent label in message, got {subagent.get('message')}")
if "019df293-b000-76d0-bcb1-c1c3bedb536d" in subagent.get("source", ""):
    sys.exit(f"Expected child id to stay out of source, got {subagent.get('source')}")
PY
echo "subagent transcript parent-thread canonicalization: ok"

echo "Codex hook event mapping verified."
