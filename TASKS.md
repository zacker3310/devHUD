# Notch DevHUD -- Implementation Build Plan

## Concept

A native macOS menu-bar utility that extends the notch (Codenotch-style pixel-perfect
shape) to show two categories of glanceable, read-only info:

1. **AI usage rings** -- Claude Code, GitHub Copilot, OpenAI Codex, percentage used +
   reset countdown.
2. **Dev servers** -- every listening localhost port, enriched with Portless's named
   routes when available, with process/project name, CPU, memory, uptime.

No accounts to manage beyond what's already on the machine. Read-only against all
three AI providers. Optional kill/open-terminal actions on the dev-server list only
(that's the one place a destructive action makes sense).

---

## Architecture

- **Distribution: Developer ID signed + notarized, NOT App Sandboxed, NOT App Store.**
  This is a decision, not an oversight -- process enumeration across PIDs, reading
  other apps' local credential files (`~/.claude/.credentials.json`,
  `~/.codex/auth.json`), and shelling out to `lsof`/`portless` are all blocked or
  crippled under App Sandbox. Codenotch and every prior-art tool referenced below
  ships this way for the same reason.
- **Min target: macOS 14 (Sonoma)** -- matches DynamicNotchKit's baseline and current
  notch geometry APIs.
- **App type:** `LSUIElement = true`, no Dock icon, menu bar item only, notch is the
  primary surface.
- **Shape/window layer:** [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)
  via SPM -- handles NSScreen safe-area math, compact/expanded states, continuous
  corner radius, floating-window fallback on notch-less Macs. Don't hand-roll this.
- **State model:** three independent `DataProvider` actors, each on its own poll
  timer, publishing into `@Observable` stores. Independent failure domains -- one
  provider going stale/erroring never blocks the others.

```
NotchController (owns DynamicNotch instance, compact/expand, hover/click)
├── AIUsageStore      (polls every 60-120s)
│   ├── ClaudeUsageProvider
│   ├── CodexUsageProvider
│   └── CopilotUsageProvider
├── PortsStore         (polls every 3-5s, cheap)
└── PortlessStore       (polls every 10-15s, joins into PortsStore)
```

---

## Module 1 -- AI Usage

```swift
protocol UsageProvider {
    var id: ProviderID { get }              // .claude, .codex, .copilot
    func fetchUsage() async throws -> UsageSnapshot
}

struct UsageSnapshot {
    let percentUsed: Double
    let windowLabel: String                 // "5h" / "weekly" / "monthly"
    let resetsAt: Date?
    let secondaryWindows: [UsageWindow]      // e.g. Claude's 7-day alongside 5h
}
```

**ClaudeUsageProvider**
- Read OAuth token from `~/.claude/.credentials.json` (auto-maintained by Claude
  Code, never write to this file).
- Call `/api/oauth/usage` with header `anthropic-beta: oauth-2025-04-20`.
- Unofficial -- reverse-engineered from Claude Code's bundled `cli.js`, matches what
  the `/usage` slash command hits. Will break if Anthropic changes it; degrade to
  cached last-good value on failure, don't crash.
- v2 optional: if Claude Code is actively running, its statusline stdin payload
  carries `rate_limits.five_hour` / `.seven_day` directly, zero network. Not useful
  for a passive background app since it only exists during an active session -- skip
  for v1.

**CodexUsageProvider**
- Read local OAuth creds from `~/.codex/auth.json`.
- v1: hit whatever OpenAI usage endpoint that token is valid against -- needs a spike
  (see Phase 0) since this is less documented than Claude's path.
- Fallback option: parse local Codex session JSONL the way `@ccusage/codex` does, if
  the API path proves unstable.

**CopilotUsageProvider**
- No supported individual-account usage API -- confirmed dead end via GitHub's own
  community discussion. Everyone doing this (VS Code's Copilot extension,
  `vscode-copilot-insights`, `pinkpixel-dev/quota`) hits the undocumented internal
  endpoint `api.github.com/copilot_internal/user`.
- **Pragmatic auth path:** you already have `gh` CLI installed and authenticated on
  both GitHub accounts (zacker3310 personal, zacker-kainos work). Shell
  `gh auth token` to grab the existing token rather than building a full OAuth
  device-flow UI from scratch. Zero new auth UX, reuses what's already trusted.
  Fall back to device flow only if `gh` isn't present or the token lacks scope.

**Shared behavior across all three:** cache last-good snapshot, exponential backoff
on repeated failure, show a neutral "--" state rather than an error glyph when data
is stale -- this is what every prior-art tracker in this space converges on because
all three integration points are unofficial and will occasionally 404 or reshape.

---

## Module 2 -- Ports (local dev servers)

No API to integrate against -- Ports (ports-app.com) is closed source. Its published
feature list is the spec to match, not a dependency:

- Every listening port, smart-filtered for Node/Vite/Next/Python/Rails/Go/Bun/Deno
- Live uptime, CPU, memory, energy-style badge
- One-click open-terminal / kill

**Implementation:**
- v1: shell out to `lsof -iTCP -sTCP:LISTEN -P -n`, parse PID + port + process name.
  Simplest, matches what tools in this space actually do under the hood.
- v1.x if subprocess-spawn overhead shows up in Activity Monitor during the polling
  loop: swap to native `libproc` (`proc_listpids` + `PROC_PIDLISTFDS`) to enumerate
  without spawning a process every 3-5 seconds.
- Enrich each PID: `proc_pidpath` for cwd, project name from directory basename or
  nearest `package.json`/`.git`, start time via `PROC_PIDTBSDINFO.pbi_start_tvsec`
  for uptime, CPU/RSS via `proc_pid_rusage`.
- Actions (confirm scope with Zac before building): kill (SIGTERM, SIGKILL after
  grace period) and open Terminal at cwd. These are the only destructive actions in
  the whole app -- needs a confirm step, not a bare click-to-kill.

---

## Module 3 -- Portless overlay

Real integration point, unlike Ports -- `vercel-labs/portless` is open source
(Apache-2.0), has a documented CLI surface and a state directory at `~/.portless`.

- **Spike first (Phase 0):** run `portless list --help` and check
  `packages/portless/src` for a `--json` flag or structured output mode before
  committing to a parser. If none exists, either parse the human-readable table or
  read the routes file directly from `~/.portless` state dir -- confirm its format
  during the spike, the README doesn't document the on-disk schema.
- **Purpose:** this is a join, not a second list. When a listening port from
  PortsStore matches a port registered in Portless's routes, show the friendly name
  (`myapp.localhost`) instead of the raw port number, tagged as Portless-managed.
  Everything else falls back to raw port + inferred project name.
- Single unified "Dev Servers" list in the UI -- no separate Portless tab.

---

## UI mapping (matches the reference screenshots exactly)

- **Compact notch:** unchanged from the AI-usage-only design -- three rings (Claude,
  Copilot, Codex icons), colored progress arc, percentage below each, settings gear
  at the bottom. Add a fourth compact element: a small badge showing active
  dev-server count, tap to expand the Dev Servers card.
- **Expanded popover:** existing "Claude Usage" card pattern (icon, title, progress
  bars, reset countdowns) extends directly to a "Dev Servers" card -- rows of
  name/port/CPU/uptime, kill button on hover per row.

---

## Visual design spec -- pixel-matched to Codenotch reference screenshots

Colors below were sampled directly from the reference screenshots (median RGB over
small pixel patches via PIL, not eyeballed). WEBP recompression + screenshot scaling
mean these land within roughly ±10 per channel of the source, not exact hex-for-hex.
For true pixel-for-pixel fidelity, pull a color from a *live running* Codenotch
install with Digital Color Meter -- screenshots go through lossy compression the app
itself doesn't. This gets you close enough to build against immediately and refine
later.

### Color tokens

| Token | Hex | Sampled from |
|---|---|---|
| `notchBackground` | `#000000` | Pill/card fill -- pure black, not dark gray |
| `ringTrack` | `#2C2D2C` | Unfilled ring arc AND unfilled progress bar track -- same token reused in both places |
| `claudeAccent` (orange) | `#F04A15` | Ring stroke + popover bar fill (averaged from two readings, ~#D44717 / #F24A0F) |
| `codexAccent` (green) | `#2BE99A` | Ring stroke -- spring/mint green, not OpenAI's teal brand green |
| `copilotAccent` (yellow) | `#EFFD31` | Ring stroke -- saturated lime-yellow |
| `iconWhite` | `#E8E8E8` | Icon glyphs -- slightly off pure white |
| `textPrimary` | `#FFFFFF` | Titles, percentage labels |
| `textSecondary` | `.white.opacity(0.55)` | Reset countdowns, e.g. "Resets in 51 min" -- render as opacity over white rather than a flat gray hex, holds up better against the notch's always-black background |

The orange/green/yellow-to-provider mapping in the reference image is arbitrary, not
brand-tied -- assign freely across Claude/Codex/Copilot. Keep the palette itself
though: this specific triad holds contrast at small ring sizes against pure black.
Swapping in a literal brand color (e.g. OpenAI's teal) risks looking muddy at 24pt.

### Shape & layout

- **Ring style:** Apple Activity-ring pattern -- thick stroke (~13-15% of ring
  diameter), round line cap, unfilled track always visible underneath at
  `ringTrack`, filled arc starts at 12 o'clock and sweeps clockwise.
- **Icon-in-ring:** centered, ~40-45% of the ring's inner diameter, single-color
  glyph at `iconWhite`, no background fill behind it.
- **Notch pill:** continuous/squircle corners, not fixed-radius iOS-style rounded
  rects -- `RoundedRectangle(cornerRadius:, style: .continuous)`. Concave "ear"
  curves flow from the menu bar's top edge into the pill; this is DynamicNotchKit's
  default shape behavior already, validate against it rather than reinventing the
  curve math.
- **Popover card:** rounded-rect speech bubble, `notchBackground` fill, triangular
  pointer on the trailing edge connecting to the notch, ~16-20pt internal padding.
  Title row = icon + bold text (~16-17pt). Each usage row = label + secondary reset
  text on one line, progress bar below, "X% Used" caption under that.
- **Typography:** SF Pro (system default), no custom font. Title semibold, body
  regular, secondary text regular-weight at reduced opacity rather than a separate
  lighter weight or gray hex.

### Deliberately not chasing exact fidelity on

- The small decorative arc/swoosh at the very bottom of the compact pill (visible in
  the closeup reference) -- cosmetic flourish, low priority, fold into the Phase 5
  polish pass if full fidelity matters to you.
- Exact pixel dimensions of the notch pill -- that's screen-size-dependent (14" vs
  16" MacBook Pro notch geometry differs) and DynamicNotchKit already handles this
  correctly. Don't hardcode a size pulled from a screenshot.

---

## Build phases

**Phase 0 -- Scaffolding & spikes (resolve unknowns before committing code)**
- Xcode project, DynamicNotchKit via SPM
- Spike: `portless list` output format / JSON flag check
- Spike: manually curl the Claude Code OAuth usage endpoint with your own token to
  confirm current response shape
- Spike: confirm Codex's usage endpoint / decide API vs local JSONL parse
- Spike: `gh auth token` -- confirm scope covers `copilot_internal/user`
- Decision lock: Developer ID distribution, App Sandbox disabled in entitlements

**Phase 1 -- Notch shell**
- DynamicNotchKit wired up, compact/expand states, menu bar presence (`LSUIElement`)
- Settings gear, empty-state UI

**Phase 2 -- AI usage module**
- `UsageProvider` protocol + three implementations
- Keychain storage only for anything new (Copilot fallback token, if device flow is
  needed); Claude/Codex tokens are read-only from their own credential files, never
  copied or written elsewhere
- Rings UI + popover detail cards, pixel-matched to reference screenshots

**Phase 3 -- Ports module**
- `lsof`-based enumeration, PID enrichment, polling loop
- Dev Servers list UI, kill/open-terminal actions (confirm dialog on kill)

**Phase 4 -- Portless overlay**
- Parse `portless list` / read state dir per Phase 0 spike result
- Join into Ports UI, friendly-name display

**Phase 5 -- Polish**
- Pixel-match validation against real MacBook Pro notch geometry (multiple screen
  sizes -- 14"/16" notch dimensions differ)
- Graceful degradation for all four unofficial data sources -- stale-cache display,
  no crashes, no error toasts for routine transient failures
- Developer ID signing + notarization pipeline

---

## Open questions to settle before Fable starts building

1. **Portless integration mode** -- live shell-out to `portless list` on each poll,
   or read `~/.portless` state directly? Depends on what Phase 0's spike finds.
2. **Kill/open-terminal scope** -- v1 or deferred to v1.x? These are the only
   destructive actions in the app; worth deciding up front since they change the
   confirmation-UI requirements.
3. **Copilot auth** -- confirm `gh auth token` reuse is acceptable, or is a fully
   separate device-flow auth preferred for isolation from your existing `gh` setup
   (e.g. so Copilot polling doesn't ride on the same token as anything else you use
   `gh` for)?
4. **App name / bundle ID / icon** -- not blocking for Phase 0-2, but needed before
   Phase 5 notarization.
