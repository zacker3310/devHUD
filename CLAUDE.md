# CLAUDE.md

<!-- Institutional knowledge for this repo, read at the start of every session.
     Keep it short enough to be read. Update it whenever the agent repeats a
     mistake - a repeated mistake is a missing line here, not a character flaw. -->

## What this is

devHUD is a macOS menu-bar utility (SwiftUI + AppKit panels, no dependencies)
that shows AI usage rings for Claude Code, Codex and Copilot plus a list of
listening localhost dev servers in a Codenotch-style pill docked to the right
screen edge. It hides to a sliver when idle and pops a detail card on tap.
Zac is the only user. Every data source is unofficial and local: it reads
`~/.claude/.credentials.json`, `~/.codex/sessions/*.jsonl`, `gh auth token`,
`lsof`, libproc and `~/.portless/routes.json`. It never writes to any of them.
TASKS.md is the original build plan; `.buildloop/` holds the artifact chain.

## Commands

Run these, do not guess them. Healthy output is shown so a wrong result is obvious.

| Job | Command | Healthy output |
|---|---|---|
| generate | `xcodegen generate` | `Created project at .../devHUD.xcodeproj` |
| build | `xcodebuild -project devHUD.xcodeproj -scheme devHUD -configuration Debug -derivedDataPath build/DerivedData build` | `** BUILD SUCCEEDED **` |
| test | `xcodebuild -project devHUD.xcodeproj -scheme devHUD -configuration Debug -derivedDataPath build/DerivedData test` | `Executed 73 tests, with 0 failures`, `** TEST SUCCEEDED **` |
| run | `open build/DerivedData/Build/Products/Debug/devHUD.app` | menu-bar gauge icon; black pill peeks at the right screen edge, slides in on hover |
| install | `scripts/install.sh` | `installed /Applications/devHUD.app and launched it` (Release; `CONFIGURATION=Debug` for the hook) |
| release | `scripts/release.sh <version>` | `built dist/devHUD-<v>.zip`, `signed=1 notarized=1`, `tagged v<v>`; exit 2 with a warning when unsigned or unnotarized |
| stop | `pkill -x devHUD` | no output |

Filter xcodebuild with `grep -E " error:|BUILD (SUCCEEDED|FAILED)"`. The
`linkd.autoShortcut` XPC noise in test output is macOS, not us.

## Architecture

- `App/DevHUDApp.swift` is the `@main` `MenuBarExtra`; `AppDelegate` starts `HUDController`.
- `App/HUDController.swift` owns two `HUDPanel`s (borderless, non-activating,
  `.statusBar` level, all Spaces): the pill docked at the right screen edge and
  the detail card that pops out to its left. State machine: concealed (window
  `PillMetric.peek` wide at the edge) / revealed / card open. The cursor is
  tracked by global + local mouse-move monitors and resolved against the two
  window frames by `HoverResolver` (pure, tested); rings take no clicks, the
  gear is the only click target. Both panels use the window's own shadow so
  transparent pixels pass clicks through.
- Geometry lives in `PillMetric` (`App/Models/HUDState.swift`), including
  `ringCenterY(index:)` and `cardPlacement`, so the pointer lands on the ring
  without measuring views. Change sizes there, nowhere else.
- Stores (`App/Stores`, `App/Portless`) are `@MainActor @Observable` classes with
  one `Task` poll loop each. Providers are `Sendable` structs that only return values.
  A provider instance is a `ProviderSlot`; `ProviderID` is the kind (color, mark).
- Claude token: on macOS Claude Code keeps the live OAuth token in the login
  keychain item "Claude Code-credentials" and refreshes it there; the
  `.credentials.json` file can be a stale copy. `ClaudeUsageProvider` reads the
  keychain first (never at launch on the main thread, never under XCTest,
  because the access prompt is modal) and falls back to the file. The first
  read prompts; ad-hoc builds prompt again after every rebuild.
- Live sessions (`App/Sessions`): Claude Code writes `~/.claude/sessions/<pid>.json`
  with cwd, status (busy | waiting), startedAt and name; `ActivityStore` keeps
  the ones whose pid is alive with a matching start time and treats a Codex
  rollout written in the last 8 s as busy. The ring shows a spinning arc while
  working and pulses amber while waiting; usage polls every 120 s while any
  agent is live, 300 s otherwise.
- Ring colour is the usage band (`UsageBand`: ample, watch, critical,
  exhausted); the brand mark identifies the provider. Stale or rate-limited
  readings dim to 55 percent. Provider cards are hover-only; only the servers
  badge pins on click. Gear menu and right-click offer Hide for 1 Hour.
- Cursor: `CursorUsageProvider` reads the session from Cursor's SQLite state
  store read-only and asks cursor.com's usage summary; no slot without a token.
- Docker (`App/Docker`): `docker ps --format '{{json .}}'` every 5 s and
  `docker stats --no-stream` every 15 s through the CLI found in fixed paths.
  Containers are a section of the Dev Servers card; the badge counts them. A
  non-zero exit means the daemon is off and is shown as one quiet line.
- Watch rows (`App/Watch`): Vercel through `vercel ls --json` (run via
  `/bin/zsh -lc`, since the CLI needs node on PATH) every 120 s, 30 s while a
  build runs; GitHub through `gh api` (notifications, review requests, your
  PRs, latest run on the four most recently pushed repos) every 120 s. The app
  holds no token for either; the CLIs do. No CLI, no row.
- Claude accounts: one `ClaudeUsageProvider` per Claude Code config directory.
  Discovery: `claudeConfigDirs` in UserDefaults if set, else `$CLAUDE_CONFIG_DIR`,
  `~/.claude`, and any `~/.claude-*` holding `.credentials.json`. To add the work
  login: `CLAUDE_CONFIG_DIR=~/.claude-work claude` and sign in; devHUD picks it
  up on next launch as "Claude Enterprise" (title comes from `subscriptionType`).
- Dev server kinds (`App/Ports/ServerProbe.swift`): known commands map directly,
  portless routes are web, everything else gets one GET on 127.0.0.1 with a
  1.5 s timeout. Web and api rows open in the browser on click.
- Placement (`PillPlacement` in `App/Models/HUDState.swift`): edge, anchor and
  display persist in UserDefaults. Drag the pill anywhere; release snaps to the
  nearer edge of the display under the cursor. Gear menu has Dock Left/Right,
  Display, Reset Position. The gear is its own panel under the pill, shown on
  hover. Frames come from `screen.visibleFrame` with `gearReserve` below.
- Launch at Login is `SMAppService.mainApp` (`App/LoginItem.swift`), toggled from
  either menu. It pins the bundle path, so only register the /Applications copy.
- Server actions (`App/Ports/ServerActions.swift`): hover a row for editor,
  terminal, restart, kill. Kill confirms in the row, SIGTERM then SIGKILL after
  3 s. Restart re-runs the listener's argv in its cwd through `/bin/zsh -lc`,
  detached with nohup, output to `~/Library/Logs/devHUD/<name>-<port>.log`.
  Editor is the `editorApp` default ("Visual Studio Code");
  `defaults write cloud.acker.devhud editorApp Cursor` changes it.
- Parsers and geometry are pure functions and are the only things unit tested:
  `LsofParser`, `CodexSessionParser`, `ClaudeUsageDecoder`,
  `CopilotUsageDecoder`, `PortlessRoutes`, `UsageFormat`, `ProjectName`,
  `CPUDelta`, `PillMetric`.
- `devHUD.xcodeproj` is generated from `project.yml` (gitignored); edit the yml.
- DEBUG builds listen for the distributed notification
  `cloud.acker.devhud.action` (object: `reveal`, `conceal`, `close`,
  `select:claude|copilot|codex|servers`) so the state machine can be driven
  without Accessibility rights. Screenshots verify the result.

## Conventions

- Swift 5 language mode, macOS 14 floor, `@Observable` not `ObservableObject`.
- Colors come from `HUDColor` in `App/Design/Tokens.swift` (sampled from the
  Codenotch reference in TASKS.md). Do not add a hex literal in a view.
- Ad-hoc signed, not sandboxed, not hardened. Developer ID is Phase 5.
- Read-only against every provider. A new provider caches last-good, backs off
  through `Backoff.delay`, and renders `--` on failure. No error toasts.

## Common mistakes

- `proc_pid_rusage(pid, flavor, buffer)` takes the struct's own address cast to
  `rusage_info_t *`. Passing a pointer to a pointer writes 296 bytes onto the
  stack and aborts with "stack buffer overflow". Use `withMemoryRebound` on the
  struct pointer (see `ProcessInspector.resources`).
- `AppDelegate` must be `@MainActor` or constructing `HUDController` fails to compile.
- A GUI app launched from Finder has a bare PATH. Locate `gh` and `lsof` with `Shell.find`.
- `log show` never returned this app's `Logger` lines here, even with `--info`.
  Screenshots are the live check (`screencapture -x out.png`); for text, launch
  the binary from the terminal and use `NSLog`, not `print` (block-buffered).
- `NSHostingView.fittingSize` is zero with `sizingOptions = []`. Measure SwiftUI
  content with `NSHostingController.sizeThatFits(in:)`.
- Do not read `pillPanel.frame` for placement while a slide animation is in
  flight; compute from `pillFrame(revealed:)`.
- Synthetic mouse events (CGEvent, cliclick) need Accessibility rights the
  terminal does not have. Use the DEBUG notification hook instead.
- A SwiftUI `.shadow` on a transparent panel paints low-alpha pixels that
  capture clicks meant for the app underneath. Use `hasShadow = true` on the
  window and draw no shadow in SwiftUI.
- `NSMenu.popUp` runs a nested event loop; never call it inside a SwiftUI tap
  action, and hold the pill open via `NSMenuDelegate` while it is up.
- This Mac drives two DELL P2422HE displays. `NSScreen.main` follows the
  active app's key window and put the pill on the second display; use
  `NSScreen.screens.first` (menu bar display) as the default.
- The Claude usage endpoint rate-limits hard: a 429 carries `Retry-After`
  around 40 minutes. `ProviderError.rateLimited` turns it into a schedule
  (`ProviderState.nextAttempt`), the card says "rate limited, retry in N min",
  and `UsageCache` persists snapshots and schedules in UserDefaults so a
  relaunch shows the last numbers and does not spend another request.
- Under the hover model, any real mouse movement re-resolves state, so a
  screenshot after a debug-hook `select:` must be taken within about 0.4 s.
- The guard and deploy-gate hooks match on Bash command text. Authoring a
  script that contains publish or destructive commands must go through the
  Write tool, and test fixtures must not spell out destructive shell.
- `NSScreen.main` wanders (see below); `ps -o args=` loses quoting, so argv for
  a restart comes from `KERN_PROCARGS2` and every token is shell-quoted.
- `zsh` expands `====` at the start of a word. Do not use it as an echo separator.

## Shipping contract

- Work on a branch, PR into `main`. Green build and tests before a PR.
- Releases: `scripts/release.sh <version>` needs `DEVHUD_SIGN_IDENTITY` (a
  Developer ID Application identity) and a `devhud-notary` notarytool keychain
  profile, or it refuses to tag. Push the tag; `.github/workflows/release.yml`
  builds, notarizes and publishes; copy `packaging/homebrew/Casks/devhud.rb`
  into the `zacker3310/homebrew-tap` repo. Publishing needs `RELEASE_AUTHORIZED`.
- Homebrew downloads anonymously, so the repo or its releases must be public.
- Never commit `build/`, `dist/`, `DerivedData/`, or a token.

## Method

Builds follow `~/.claude/BUILD-METHODOLOGY.md` and the loop in
`~/.claude/skills/build-loop/SKILL.md`. This file adds only project-specific deltas.
Where a rule here conflicts with the method, the stricter one wins.

---

## Completion canary

This file is only useful if it is read to the end. The line below is the proof.

**When you have read this file through to its final line, type that line verbatim once —
in your first substantive response of the session, on its own line.** It is a read-proof
and nothing more: it does not mean a task is done or a test passed. Never type it if you
have not actually reached this line.

Nothing may be appended below it — a sentinel that is not last proves nothing about what
follows. `check-canary.sh` enforces that.

This is the Way.
