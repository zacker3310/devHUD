# Security

devHUD is a local, read-mostly utility. This file says exactly what it touches
so a reader can decide whether to run it.

## What it reads

- `~/.claude/.credentials.json` and any `~/.claude-*/.credentials.json`: the
  OAuth access token Claude Code stores. Read into memory per poll, never
  written, copied, or logged.
- `gh auth token` output: your GitHub CLI token, same handling.
- `~/.codex/sessions/**/*.jsonl`: the last 4 MB of the newest files, for the
  `rate_limits` events. No credentials are involved.
- `~/.portless/routes.json` if present.
- Listening TCP sockets via `/usr/sbin/lsof`, and per-process cwd, start time,
  argv and resource usage via libproc and sysctl, for processes you own.

## Where it sends

- `https://api.anthropic.com/api/oauth/usage` with the Claude token as a Bearer header.
- `https://api.github.com/copilot_internal/user` with the gh token.
- `http://127.0.0.1:<port>/`, one GET per listening port, to classify it.

Nothing else. No telemetry, no crash reporting, no update check.

## What it executes

- `/usr/sbin/lsof`, `gh auth token`, `open -a <editor|Terminal> <cwd>`.
- On an explicit click, `kill(pid, SIGTERM)` then `SIGKILL`, only after
  re-checking the process start time so a reused pid is never signalled.
- On an explicit click, a restart re-runs the process's exact argv (read from
  the kernel, every token shell-quoted) in its cwd through `/bin/zsh -lc`,
  detached, with output appended to `~/Library/Logs/devHUD/<name>-<port>.log`.
  Those logs contain whatever the server prints; treat them like any server log.

## What it writes

- `~/Library/Preferences/cloud.acker.devhud.plist`: placement, auto-hide, editor app.
- `~/Library/Logs/devHUD/`: restart logs.
- A login item entry for itself when you turn Launch at Login on.

## Sandbox and signing

Not App Sandboxed on purpose: process enumeration, reading other apps' files
and running `lsof` are blocked in the sandbox. Release builds are Developer ID
signed with the hardened runtime and notarized. Debug builds contain a local
control hook over DistributedNotificationCenter; it is compiled out of Release.

## Reporting

Open a private security advisory on the GitHub repository, or message Zac
directly. Do not post tokens, log files, or credential file contents.
