#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

DEFAULT_ENDPOINT = "http://127.0.0.1:17321/events"
DISABLE_FILE = Path.home() / ".codex" / "global-pet-assistant-disabled"
HOOK_LOG_FILE = Path.home() / ".global-pet-assistant" / "logs" / "codex-hook-events.jsonl"
MAX_CONTEXT_CHARS = 240


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Forward Codex lifecycle hook events to Global Pet Assistant."
    )
    parser.add_argument(
        "--print-event",
        action="store_true",
        help="Print the mapped pet event instead of sending it. Intended for tests.",
    )
    args = parser.parse_args()

    if is_disabled() and not args.print_event:
        append_hook_log({"status": "disabled"})
        return 0

    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        append_hook_log({"status": "invalid_json"})
        return 0

    event = map_hook_to_pet_event(payload)
    if event is None:
        append_hook_log({
            "status": "ignored",
            "hookEventName": str(payload.get("hook_event_name") or ""),
        })
        return 0

    if args.print_event:
        print(json.dumps(event, ensure_ascii=False, sort_keys=True))
        return 0

    append_hook_log({
        "status": "mapped",
        "hookEventName": str(payload.get("hook_event_name") or ""),
        "source": event.get("source"),
        "type": event.get("type"),
        "state": event.get("state"),
        "level": event.get("level"),
        "dedupeKey": event.get("dedupeKey"),
    })
    return send_event(event)


def is_disabled() -> bool:
    value = os.environ.get("CODEX_PET_EVENTS_DISABLED", "")
    if value.strip().lower() in {"1", "true", "yes", "on"}:
        return True
    return DISABLE_FILE.exists()


def map_hook_to_pet_event(payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    hook_name = str(payload.get("hook_event_name") or "")
    cwd = str(payload.get("cwd") or "")
    session_id = first_nonempty(
        payload,
        ["session_id", "session-id", "thread_id", "thread-id", "conversation_id", "conversation-id"],
        fallback=f"unknown:{os.getppid()}:{cwd or 'no-cwd'}",
    )
    turn_id = first_nonempty(payload, ["turn_id", "turn-id"], fallback="")
    source = f"codex-cli:{stable_session_key(session_id)}"
    dedupe_key = f"codex:{session_id}"

    if hook_name == "SessionStart":
        source_name = str(payload.get("source") or "startup")
        return {
            "source": source,
            "type": "codex.session.start",
            "state": "running",
            "title": "Codex session started",
            "message": compact_context([source_name]),
            "cwd": cwd,
            "action": kitty_focus_action(),
            "ttlMs": 30000,
            "dedupeKey": dedupe_key,
        }

    if hook_name == "UserPromptSubmit":
        prompt = str(payload.get("prompt") or "")
        return {
            "source": source,
            "type": "codex.turn.running",
            "state": "running",
            "title": title_from_text(prompt, fallback="Codex is running"),
            "message": compact_context([prompt]),
            "cwd": cwd,
            "action": kitty_focus_action(),
            "ttlMs": 120000,
            "dedupeKey": dedupe_key,
        }

    if hook_name == "PermissionRequest":
        tool_name = str(payload.get("tool_name") or "tool")
        tool_input = payload.get("tool_input")
        description = ""
        if isinstance(tool_input, dict):
            description = str(tool_input.get("description") or tool_input.get("command") or "")
        return {
            "source": source,
            "type": "codex.permission.request",
            "level": "warning",
            "title": "Codex is waiting for approval",
            "message": compact_context([tool_name, description]),
            "cwd": cwd,
            "action": kitty_focus_action(),
            "ttlMs": 300000,
            "dedupeKey": dedupe_key,
        }

    if hook_name == "Stop":
        last_message = str(payload.get("last_assistant_message") or "")
        return {
            "source": source,
            "type": "codex.turn.review",
            "level": "success",
            "title": title_from_text(last_message, fallback="Codex task ready for review"),
            "message": compact_context([last_message]),
            "cwd": cwd,
            "action": kitty_focus_action(),
            "ttlMs": 300000,
            "dedupeKey": dedupe_key,
        }

    return None


def first_nonempty(payload: Dict[str, Any], keys: List[str], fallback: str) -> str:
    for key in keys:
        value = str(payload.get(key) or "").strip()
        if value:
            return value
    return fallback


def stable_session_key(value: str) -> str:
    cleaned = cleaned_id(value)
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:8]
    if cleaned == "unknown":
        return f"unknown-{digest}"
    return f"{cleaned[:8]}-{digest}"


def cleaned_id(value: str) -> str:
    cleaned = "".join(char for char in value if char.isalnum() or char in {"-", "_"})
    return cleaned or "unknown"


def kitty_focus_action() -> Optional[Dict[str, str]]:
    window_id = os.environ.get("KITTY_WINDOW_ID", "").strip()
    listen_on = os.environ.get("KITTY_LISTEN_ON", "").strip()
    if not window_id or not listen_on:
        return None
    return {
        "type": "focus_kitty_window",
        "kittyWindowId": window_id,
        "kittyListenOn": listen_on,
    }


def title_from_text(text: str, fallback: str) -> str:
    normalized = " ".join(text.split())
    if not normalized:
        return fallback
    first_line = normalized.splitlines()[0]
    return truncate(first_line, 54)


def compact_context(parts: List[str]) -> str:
    text = " · ".join(part.strip() for part in parts if part and part.strip())
    return truncate(" ".join(text.split()), MAX_CONTEXT_CHARS)


def truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def send_event(event: Dict[str, Any]) -> int:
    endpoint = os.environ.get("CODEX_PET_ENDPOINT", DEFAULT_ENDPOINT)
    data = json.dumps(event).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=2):
            append_hook_log({
                "status": "sent",
                "endpoint": endpoint,
                "source": event.get("source"),
                "type": event.get("type"),
            })
            return 0
    except (OSError, urllib.error.URLError, urllib.error.HTTPError) as error:
        append_hook_log({
            "status": "send_failed",
            "endpoint": endpoint,
            "source": event.get("source"),
            "type": event.get("type"),
            "error": str(error),
        })
        return 0


def append_hook_log(record: Dict[str, Any]) -> None:
    try:
        HOOK_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            **{key: value for key, value in record.items() if value is not None},
        }
        with HOOK_LOG_FILE.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True))
            handle.write("\n")
    except OSError:
        pass


if __name__ == "__main__":
    sys.exit(main())
