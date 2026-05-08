#!/usr/bin/env python3
"""Structured kitty terminal event emitter for Global Pet Assistant."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request


DEFAULT_ENDPOINT = "http://127.0.0.1:17321/terminal-plugin/events"


def token() -> str:
    explicit = os.environ.get("GPA_TOKEN")
    if explicit:
        return explicit.strip()

    token_path = os.path.expanduser("~/.global-pet-assistant/token")
    try:
        with open(token_path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def terminal_context(args: argparse.Namespace) -> dict[str, object]:
    window_id = args.window_id or os.environ.get("KITTY_WINDOW_ID")
    listen_on = args.control_endpoint or os.environ.get("KITTY_LISTEN_ON")
    session_id = args.session_id or (f"kitty-{window_id}" if window_id else f"kitty-{os.getpid()}")
    return {
        "kind": "kitty",
        "sessionId": session_id,
        "windowId": window_id,
        "tabId": args.tab_id or os.environ.get("KITTY_TAB_ID"),
        "cwd": args.cwd or os.getcwd(),
        "command": args.command,
        "controlEndpoint": listen_on,
    }


def emit(args: argparse.Namespace) -> int:
    auth_token = token()
    if not auth_token:
        print("global_pet_assistant.py: missing GPA_TOKEN or ~/.global-pet-assistant/token", file=sys.stderr)
        return 2

    payload = {
        "schemaVersion": 1,
        "kind": args.kind,
        "terminal": {key: value for key, value in terminal_context(args).items() if value},
        "command": args.command,
        "exitCode": args.exit_code,
        "durationMs": args.duration_ms,
        "outputSummary": args.output_summary,
        "providerHint": args.provider_hint,
        "occurredAt": time.time(),
    }
    payload = {key: value for key, value in payload.items() if value is not None}
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        args.endpoint,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {auth_token}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            response.read()
        return 0
    except urllib.error.HTTPError as error:
        print(f"global_pet_assistant.py: app rejected event with HTTP {error.code}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"global_pet_assistant.py: could not reach app: {error}", file=sys.stderr)
        return 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", default=os.environ.get("GPA_TERMINAL_PLUGIN_ENDPOINT", DEFAULT_ENDPOINT))
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--kind", choices=["command-started", "command-completed", "agent-observed"], required=True)
    parser.add_argument("--command")
    parser.add_argument("--exit-code", type=int)
    parser.add_argument("--duration-ms", type=int)
    parser.add_argument("--output-summary")
    parser.add_argument("--provider-hint", choices=["codex", "claude-code", "opencode"])
    parser.add_argument("--session-id")
    parser.add_argument("--window-id")
    parser.add_argument("--tab-id")
    parser.add_argument("--cwd")
    parser.add_argument("--control-endpoint")
    return emit(parser.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
