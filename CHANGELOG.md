# Changelog

## 0.3.1

First release intended for other Macs.

- Side pill: hover to reveal, drag to move, dock left or right, pick a display; gear circle under the pill.
- Rings: one per Claude account (Max, Enterprise) plus Copilot and Codex; hover cards; Fable-scoped weekly window.
- Dev servers: kind tags (web, api, postgres, ...), click to open, kill with confirm, restart, open in editor or terminal.
- Launch at Login.
- Security review: restart runs the kernel-reported executable with every argument quoted; kill and restart re-check process identity through the whole grace window; portless links only for *.localhost; the port probe never follows redirects; hardened runtime on Release builds.
- Usage providers honor Retry-After, persist their last snapshot across launches, and wait out the poll interval after a relaunch instead of fetching immediately.
- Homebrew cask and release pipeline.
