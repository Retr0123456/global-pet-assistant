# Security Policy

## Supported Versions

The project is pre-1.0. Security fixes target the `main` branch until release
branches exist.

## Reporting A Vulnerability

Please report vulnerabilities privately to the repository owner instead of
opening a public issue. Include:

- affected commit or release;
- reproduction steps;
- expected and observed behavior;
- any logs that do not contain private tokens or local secrets.

## Security Model

Global Pet Assistant is designed as a local macOS utility:

- the HTTP event server binds to `127.0.0.1`;
- incoming request bodies are size-limited;
- noisy sources are rate-limited;
- click actions are allowlisted by source;
- unknown sources may send state notifications but cannot open URLs, files, folders, apps, or terminal windows.

The app must not execute arbitrary shell commands from event payloads. If command
execution is ever added, it needs explicit user approval, source allowlisting,
and separate documentation.

## Sensitive Local Data

Runtime logs live under `~/.global-pet-assistant/logs`. They may include event
titles, short message previews, source identifiers, working-directory paths, and
action metadata. Do not attach those logs to public issues without reviewing
them first.
