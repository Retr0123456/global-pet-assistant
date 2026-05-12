# Security Policy

Global Pet Assistant is a local macOS utility. Its security model is built
around a narrow local event boundary, source-aware action handling, and readable
logs that users can inspect.

## Supported Versions

The project is pre-1.0. Security fixes target the `main` branch until release
branches exist.

## Reporting A Vulnerability

Please report vulnerabilities privately to the repository owner instead of
opening a public issue. Include:

- affected commit or release;
- reproduction steps;
- expected and observed behavior;
- whether the issue involves event ingestion, action handling, logs, tokens, or
  integration installers;
- any logs that do not contain private tokens or local secrets.

## Security Model

Global Pet Assistant is designed to be local by default:

- the HTTP event server binds to `127.0.0.1`;
- mutating event writes require `Authorization: Bearer <token>`;
- incoming request bodies are size-limited;
- noisy sources are rate-limited;
- repeated events can be deduplicated;
- click actions are allowlisted by source;
- unknown sources may send state notifications but cannot open URLs, files,
  folders, apps, or terminal windows.

The app must not execute arbitrary shell commands from event payloads. If command
execution is ever added, it needs explicit user approval, source allowlisting,
and separate security documentation.

## Sensitive Local Data

Runtime data lives under `~/.global-pet-assistant`.

| Path | Sensitivity |
| --- | --- |
| `~/.global-pet-assistant/token` | Local bearer token for event writes. Keep private. |
| `~/.global-pet-assistant/config.json` | Source allowlist, import paths, and preferences. May reveal local paths. |
| `~/.global-pet-assistant/logs/runtime.jsonl` | Runtime diagnostics. May include local paths or integration details. |
| `~/.global-pet-assistant/logs/events.jsonl` | Event titles, previews, sources, actions, and working-directory paths. |
| `~/.global-pet-assistant/logs/agent-hooks.jsonl` | Hook ingestion diagnostics for coding-agent integrations. |

The local bearer token should have `0600` permissions. Do not paste it into
issues, logs, screenshots, or chat transcripts.

Review logs before attaching them to public issues. Event senders decide what
text they place in titles, messages, action metadata, and working-directory
fields; that data can appear in JSONL logs.

## Integration Installers

Bundled installers should write managed, reversible configuration:

- Kitty installer files live under `~/.config/kitty/global-pet-assistant/` and
  add one marked include block to `~/.config/kitty/kitty.conf`.
- Codex hook installation writes managed commands to `~/.codex/hooks.json` and
  enables the `codex_hooks` feature.

Installers should not silently overwrite unrelated user configuration.
