# Privacy

Global Pet Assistant is local-first.

- The app listens on `127.0.0.1:17321`.
- It does not send telemetry to a hosted service.
- It stores app state and logs under `~/.global-pet-assistant`.
- It stores the local event API bearer token at `~/.global-pet-assistant/token`.
- At startup it reads pet packages from `~/.global-pet-assistant/pets`.
- `petctl import-pet` may read from configured import source directories, which default to `~/.codex/pets`, only when explicitly invoked.

Event senders can include titles, message previews, working directories, and
click actions in local event payloads. Those values can appear in JSONL logs
under `~/.global-pet-assistant/logs`.

Third-party tools that call the local event API are responsible for deciding
what event text they send.
