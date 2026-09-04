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

Pre-Phase 0. Nothing is built yet — [TASKS.md](TASKS.md) is the full implementation
plan: architecture, provider contracts, the sampled color tokens, build phases, and
the open questions that need answers before code starts.

## Architecture at a glance

```
NotchController (owns DynamicNotch instance, compact/expand, hover/click)
├── AIUsageStore      (polls every 60-120s)
│   ├── ClaudeUsageProvider
│   ├── CodexUsageProvider
│   └── CopilotUsageProvider
├── PortsStore        (polls every 3-5s, cheap)
└── PortlessStore     (polls every 10-15s, joins into PortsStore)
```

Three independent provider actors on their own poll timers, publishing into
`@Observable` stores. One provider going stale never blocks the others.

## Constraints

- **macOS 14 (Sonoma)** minimum — matches DynamicNotchKit's baseline.
- **`LSUIElement = true`** — no Dock icon, menu bar item only.
- **Developer ID signed + notarized, not App Sandboxed, not App Store.** Deliberate:
  process enumeration across PIDs, reading local credential files, and shelling out
  to `lsof`/`portless` are all blocked under App Sandbox.
- Every AI-usage integration point is unofficial. All of them cache last-good state,
  back off on repeated failure, and show a neutral `--` rather than an error.

## Reading

- [TASKS.md](TASKS.md) — implementation build plan
