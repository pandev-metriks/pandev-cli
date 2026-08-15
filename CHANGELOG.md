# Changelog

All notable changes to `pandev` are documented here. Dates are ISO, newest first.

## 2.4.13 — 2026-08-15 (stable)

- **First stable release of the npx channel.** `npx pandev` now installs this version —
  no `@beta` tag needed. The beta channel keeps living at `npx pandev@beta`.
- Login is token-only now: `pandev login` prompts for a PanDev token (password sign-in
  was deprecated and has been removed). Already signed-in installs are unaffected.
- Hardened install: symlinked install/log directories are followed and secured instead
  of being refused; the Windows runtime carries the complete module set.
- Every release is now built and unit-tested on all four platforms (macOS arm64/Intel,
  Linux, Windows) and each artifact is smoke-tested on its own bundled runtime before
  anything is published.

## 2.4.12 — 2026-08-15 (beta)

- **Everything public now lives in this repository.** Releases (the binaries the installers
  download), the Homebrew formulas (`Formula/`) and the install scripts are published here —
  no more separate `homebrew-…` repos. Old installer URLs keep working via redirect stubs.
- Task heat map: agent time is the default view, with the multiplier shown in the header.

## 2.4.4 — 2026-08-10 (beta)

- **Live dashboard.** `pandev web` (alias `dashboard`) now serves your numbers at
  `http://127.0.0.1:4976` — loopback only — and opens the browser. Data refreshes from your
  logs on every visit. The fully offline copy `~/pandev-cost.html` is still written.
- **Dashboard at login.** `pandev autostart on|off|status` — a user-level login item
  (launchd / systemd user unit) starts the server and opens the dashboard once per login.
  The first interactive run enables it and says so; one command removes it.
- **`pandev team`** — the bridge to the team edition: opens
  [pandev-metrics.com/book](https://pandev-metrics.com/book).
- The served dashboard page shows an update chip when a newer beta is on npm (one anonymous
  request to `registry.npmjs.org` from the browser; the offline file never does this).
- Windows consoles: no more raw `←[36m` on legacy conhost, and ASCII stand-ins for glyphs
  when the console codepage cannot render `✓ █ ═` (they printed as `?`).
- Cross-links throughout: help and summary now point to the site, GitHub and npm; hints in
  the npx channel use the `pandev …` form instead of `pandev cost …`.

## 2.4.3 and earlier (beta)

The first public beta line. Cost attribution per task with the real branch reconstructed
from `git reflog` (agents log `HEAD`, which makes naive per-task numbers wrong by a wide
margin); `task`, `today`, `files`, `models`, `why cache`, `why ratio`, `privacy`, `web`;
Claude Code, Codex CLI, opencode and ZCode log sources, each verified against live logs;
macOS (arm64, x64) and Linux (x64) npm packages, Windows via the PowerShell beta installer.
