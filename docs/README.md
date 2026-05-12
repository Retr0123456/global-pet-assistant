# Documentation

[README](../README.md) | [中文文档](README.zh-CN.md)

This directory is the project map for Global Pet Assistant. Start with the
runtime guides if you want to use the app, and the architecture guides if you
want to change how integrations or notifications work.

## User Guides

| Guide | Use it for |
| --- | --- |
| [Integration Setup](integrations.md) | Installing Kitty command flashes or Codex session hooks. |
| [Codex Hook Integration](codex-hook-integration.md) | Understanding Codex hook events and bundled examples. |
| [Kitty Plugin README](../plugins/kitty/README.md) | Kitty-specific install, verification, and cleanup. |
| [Assets and Licensing](assets-and-licensing.md) | App icon, bundled pet, and third-party pet asset rules. |
| [Privacy](../PRIVACY.md) | What the app stores locally and what logs may contain. |
| [Security Policy](../SECURITY.md) | Local event server, token model, and vulnerability reporting. |

## Architecture

| Document | Scope |
| --- | --- |
| [Architecture](architecture.md) | Product definition, native runtime, event API, state machine, actions, and security model. |
| [Agent Discovery Architecture](agent-discovery-architecture.md) | How coding-agent providers, sessions, and projections are modeled. |
| [Terminal Plugin Transport Architecture](terminal-plugin-transport-architecture.md) | Trusted terminal plugin transport and terminal-backed session context. |
| [Codex Session Listening Refactor Plan](codex-session-listening-refactor-plan.md) | Migration plan for Codex session listening and hook ingestion. |
| [Kitty Terminal Transport Implementation Plan](kitty-terminal-transport-implementation-plan.md) | Implementation detail for the first terminal plugin transport. |

## Planning And Maintenance

| Document | Scope |
| --- | --- |
| [Daily Driver MVP](daily-driver-mvp.md) | Product shape for using the app as a daily companion. |
| [Desktop Experience Plan](desktop-experience-plan.md) | Pet behavior, surface polish, and desktop interaction ideas. |
| [Release Candidate Plan](release-candidate-plan.md) | Pre-release stabilization checklist. |
| [Post-RC Roadmap](post-rc-roadmap.md) | Follow-up work after the release candidate track. |
| [Open Source Checklist](open-source-checklist.md) | Repository readiness and public-facing hygiene. |
| [TODO](../TODO.md) | Phase checklist for implementation progress. |

## Development Gates

Run these before publishing code changes:

```bash
swift build
swift test
```

Run focused checks when changing integration behavior:

```bash
Tools/verify-codex-hook-events.sh
Tools/verify-kitty-plugin.sh
Tools/verify-event-runtime.sh
```

`Tools/verify-event-runtime.sh` launches the app. Quit any already running copy
first if local port `17321` is busy.
