# Changelog

## 0.3.1

First release intended for other Macs.

- Side pill: hover to reveal, drag to move, dock left or right, pick a display; gear circle under the pill.
- Rings: one per Claude account (Max, Enterprise) plus Copilot and Codex; hover cards; Fable-scoped weekly window.
- Dev servers: kind tags (web, api, postgres, ...), click to open, kill with confirm, restart, open in editor or terminal.
- Launch at Login.
- Security review: restart runs the kernel-reported executable with every argument quoted; kill and restart re-check process identity through the whole grace window; portless links only for *.localhost; the port probe never follows redirects; hardened runtime on Release builds.
- Usage providers honor Retry-After, persist their last snapshot across launches, and wait out the poll interval after a relaunch instead of fetching immediately.
- Rings colour by usage band; live agent sessions with a working arc and a waiting pulse, sessions listed on the card; reset copy reads "Resets Thu 12:00 AM"; stale readings dim; click a ring to pin its card; Hide for 1 Hour; Cursor provider; polling slows to five minutes when no agent is running.
- Claude token read from the login keychain, where Claude Code keeps it fresh; the file is the fallback.
- Homebrew cask and release pipeline.
