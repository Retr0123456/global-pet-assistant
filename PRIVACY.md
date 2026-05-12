# Privacy

Global Pet Assistant is local-first. It does not require a hosted account and it
does not send telemetry to a hosted service.

## Local Runtime

- The app listens on `127.0.0.1:17321`.
- Event writes require the local bearer token stored at
  `~/.global-pet-assistant/token`.
- App state, logs, imported pets, and preferences live under
  `~/.global-pet-assistant`.
- At startup the app reads pet packages from `~/.global-pet-assistant/pets`.
- `petctl import-pet` may read from configured import source directories, which
  default to `~/.codex/pets`, only when explicitly invoked.

## Data In Logs

Event senders can include titles, message previews, working directories, source
identifiers, and click actions in local event payloads. Those values can appear
in JSONL logs under `~/.global-pet-assistant/logs`.

Third-party tools that call the local event API are responsible for deciding
what event text they send.

Review local logs before sharing them in public issues, screenshots, or support
threads.
