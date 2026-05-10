"""Kitty global watcher for Global Pet Assistant terminal events."""

from __future__ import annotations

import json
import os
import shlex
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_ENDPOINT = "http://127.0.0.1:17321/terminal-plugin/events"
DEFAULT_TIMEOUT = 0.8
COMMAND_STARTS: dict[str, tuple[float, str]] = {}


def _settings() -> dict[str, Any]:
    path = Path(__file__).with_name("env.json")
    try:
        with path.open("r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        return loaded if isinstance(loaded, dict) else {}
    except OSError:
        return {}
    except json.JSONDecodeError:
        return {}


SETTINGS = _settings()


def _configured(name: str, default: str = "") -> str:
    value = os.environ.get(name)
    if value:
        return value
    value = SETTINGS.get(name)
    return value if isinstance(value, str) else default


def _token() -> str:
    explicit = os.environ.get("GPA_TOKEN")
    if explicit:
        return explicit.strip()

    token_path = Path(os.environ.get("GPA_TOKEN_FILE", "~/.global-pet-assistant/token")).expanduser()
    try:
        return token_path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _window_id(window: Any) -> str:
    return str(getattr(window, "id", "") or "")


def _tab_id(window: Any) -> str:
    tabref = getattr(window, "tabref", None)
    if callable(tabref):
        tab = tabref()
        if tab is not None:
            return str(getattr(tab, "id", "") or "")
    return ""


def _cwd(window: Any) -> str:
    child = getattr(window, "child", None)
    if child is not None:
        for attr in ("current_cwd", "foreground_cwd", "cwd"):
            value = getattr(child, attr, "")
            if value:
                return str(value)
    return ""


def _exit_status(window: Any, data: dict[str, Any]) -> int | None:
    for key in ("exit_status", "exitStatus", "exit_code", "exitCode"):
        value = data.get(key)
        if value is not None:
            try:
                return int(value)
            except (TypeError, ValueError):
                return None
    value = getattr(window, "last_cmd_exit_status", None)
    if value is not None:
        try:
            return int(value)
        except (TypeError, ValueError):
            return None
    return None


def _provider_for_command(command: str) -> str | None:
    try:
        words = shlex.split(command)
    except ValueError:
        words = command.split()
    for word in words:
        if word in ("env", "command", "exec", "noglob", "time"):
            continue
        if "=" in word:
            continue
        executable = word.rsplit("/", 1)[-1]
        if executable in ("codex", "cdx"):
            return "codex"
        return None
    return None


def _terminal(window: Any, command: str) -> dict[str, str]:
    window_id = _window_id(window)
    terminal = {
        "kind": "kitty",
        "sessionId": f"kitty-{window_id}" if window_id else f"kitty-{os.getpid()}",
    }
    if window_id:
        terminal["windowId"] = window_id
    tab_id = _tab_id(window)
    if tab_id:
        terminal["tabId"] = tab_id
    cwd = _cwd(window)
    if cwd:
        terminal["cwd"] = cwd
    if command:
        terminal["command"] = command
    control_endpoint = _configured("GPA_KITTY_CONTROL_ENDPOINT")
    if control_endpoint:
        terminal["controlEndpoint"] = control_endpoint
    return terminal


def _emit(window: Any, kind: str, command: str, **fields: Any) -> None:
    if os.environ.get("GPA_KITTY_PLUGIN") == "0":
        return

    token = _token()
    if not token:
        return

    payload = {
        "schemaVersion": 1,
        "kind": kind,
        "terminal": _terminal(window, command),
        "command": command,
        "occurredAt": time.time(),
    }
    payload.update({key: value for key, value in fields.items() if value is not None})
    payload = {key: value for key, value in payload.items() if value not in (None, "")}

    endpoint = _configured("GPA_TERMINAL_PLUGIN_ENDPOINT", DEFAULT_ENDPOINT)
    timeout_value = _configured("GPA_KITTY_PLUGIN_TIMEOUT", str(DEFAULT_TIMEOUT))
    try:
        timeout = float(timeout_value)
    except ValueError:
        timeout = DEFAULT_TIMEOUT

    def post() -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(
            endpoint,
            data=data,
            method="POST",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                response.read()
        except (OSError, urllib.error.HTTPError):
            pass

    threading.Thread(target=post, daemon=True).start()


def on_cmd_startstop(boss: Any, window: Any, data: dict[str, Any]) -> None:
    command = str(data.get("cmdline") or getattr(window, "last_cmd_cmdline", "") or "").strip()
    window_id = _window_id(window)
    event_time = data.get("time")
    try:
        monotonic_time = float(event_time)
    except (TypeError, ValueError):
        monotonic_time = time.monotonic()

    if data.get("is_start"):
        provider = _provider_for_command(command)
        if window_id:
            COMMAND_STARTS[window_id] = (monotonic_time, command)
        if provider:
            _emit(window, "agent-observed", command, providerHint=provider)
        if os.environ.get("GPA_KITTY_PLUGIN_EMIT_COMMAND_STARTED") == "1":
            _emit(window, "command-started", command)
        return

    started_at, started_command = COMMAND_STARTS.pop(window_id, (monotonic_time, command))
    command = command or started_command
    provider = _provider_for_command(command)
    duration_ms = max(0, int((monotonic_time - started_at) * 1000))
    exit_status = _exit_status(window, data)
    if provider:
        _emit(window, "agent-observed", command, providerHint=provider, exitCode=exit_status)
    _emit(window, "command-completed", command, exitCode=exit_status, durationMs=duration_ms)
