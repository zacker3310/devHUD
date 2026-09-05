# devHUD

A native macOS menu-bar utility that extends the notch (Codenotch-style pixel-perfect
shape) into a glanceable, read-only dev HUD.

Two things live in the notch:

1. **AI usage rings** — Claude Code, GitHub Copilot, OpenAI Codex: percentage used
   and reset countdown.
2. **Dev servers** — every listening localhost port, enriched with
   [Portless](https://github.com/vercel-labs/portless) named routes when available,
   plus process/project name, CPU, memory, and uptime.

No new accounts. Every data source is already on the machine.

## Status

Version 0.2, running as a login item from `/Applications/devHUD.app` on Zac's
Mac mini. Built with `scripts/install.sh` (XcodeGen + xcodebuild, Release,
ad-hoc signed). Not notarized: this-machine only until Phase 5.

What works: the Codenotch-style side pill (hover to reveal, drag to move,
dock left or right, pick a display), one ring per Claude account plus Copilot
and Codex with hover cards, the Fable-scoped weekly window, a dev-servers card
with kind tags, click-to-open, kill, restart, open in editor or terminal, and a
gear circle under the pill for settings. Build-loop artifacts live in
`.buildloop/`; the working notes for agents are in `CLAUDE.md`.

## Architecture at a glance

```
HUDController (two NSPanels: pill + card; hover resolved from window frames)
├── AIUsageStore      (polls every 120s; one slot per provider instance)
│   ├── ClaudeUsageProvider   (one per Claude Code config directory)
│   ├── CodexUsageProvider    (local session JSONL, no network)
│   └── CopilotUsageProvider  (gh auth token)
├── PortsStore        (lsof every 4s, libproc enrichment, kind probe once per port)
├── PortlessStore     (~/.portless/routes.json every 12s, joins into PortsStore)
└── ServerActions     (kill, restart, open editor / terminal)
```

Three independent provider actors on their own poll timers, publishing into
`@Observable` stores. One provider going stale never blocks the others.

## Constraints

- **macOS 14 (Sonoma)** minimum. No third-party dependencies.
- **`LSUIElement = true`** — no Dock icon, menu bar item only.
- **Developer ID signed + notarized, not App Sandboxed, not App Store.** Deliberate:
  process enumeration across PIDs, reading local credential files, and shelling out
  to `lsof`/`portless` are all blocked under App Sandbox.
- Every AI-usage integration point is unofficial. All of them cache last-good state,
  back off on repeated failure, and show a neutral `--` rather than an error.

## Reading

- [TASKS.md](TASKS.md) — the original build plan
- [CLAUDE.md](CLAUDE.md) — commands, architecture, and the mistakes already made
- [THIRD_PARTY.md](THIRD_PARTY.md) — icon attribution
