<div align="center">

# pandev

**What your AI coding agents actually cost — broken down by task, branch, model and file.**

Runs on your machine. No account, no daemon, no network.

[![status](https://img.shields.io/badge/status-pre--release-FF9500)](#not-released-yet)
[![platforms](https://img.shields.io/badge/platforms-macOS%20%C2%B7%20Linux%20%C2%B7%20Windows-333)](#requirements)
[![license](https://img.shields.io/badge/license-proprietary-333)](LICENSE)

```
npx pandev
```

[Website](https://pandev.io/cli) · [How to verify the privacy claim](docs/VERIFY.md) · [Changelog](CHANGELOG.md)

</div>

> ### Not released yet
>
> The package is not on npm, so the command above will not work — yet. This repository is up
> early so you can read what the tool does, how it is licensed, and how to check its privacy
> claims before deciding whether to run it.
>
> Watch this repository, or [pandev.io/cli](https://pandev.io/cli), for the release.

---

<div align="center">
  <img src="assets/summary.png" alt="pandev summary: payback multiple against subscription price, and where the token volume actually goes — cache reads, cache writes, fresh input, output" width="720">
</div>

---

## The problem

Your agent bills you per token. Your work is organised in tasks. Nothing connects the two.

Every tool in this space reports *sessions*: "yesterday you spent $61." Useful once. It never
answers the question you actually have — **which piece of work was expensive, and why.**

## What this does differently

**Cost lands on the task, not the session.** A session wanders across three tickets and two
branches. `pandev` splits it at every prompt you typed and attributes each slice to the task
that was actually being worked on.

**It recovers the branch that agents don't record.** Claude Code writes `HEAD` into its logs
instead of a branch name — every single event. So per-task numbers built naively from those
logs are wrong, and wrong by a lot: on our own data one task was overstated **70×**. `pandev`
reconstructs the real branch at each timestamp from `git reflog`, which is what makes the
attribution trustworthy.

**It shows the composition, not just the total.** Cache reads, cache writes, fresh input and
output are four different prices. A bill that looks alarming is usually cache reads, and the
fix is a prompt change — but you can't see that from one number.

<div align="center">
  <img src="assets/by-task.png" alt="pandev task: cost, call count, days and git branch for each ticket, with the unattributed remainder stated openly" width="720">
</div>

Note the last line. Work that happened outside a repository, or on a branch with no ticket key
in its name, **cannot** be attributed — so it is reported as its own number rather than spread
across the tasks to make the table look complete. `pandev task` breaks that remainder down by
project so you can see what it consists of.

## Commands

| | |
|---|---|
| `npx pandev` | summary for the last 14 days |
| `npx pandev today` | today only |
| `npx pandev task` | cost per task |
| `npx pandev task WEB-812` | one task: every prompt, time spent, files touched, tools used |
| `npx pandev files` | cost by file, with edit rounds |
| `npx pandev models` | cost and cache behaviour per model |
| `npx pandev why cache` | how prompt caching actually played out |
| `npx pandev why ratio` | context read per unit of output |
| `npx pandev web` | build and open the dashboard |
| `npx pandev privacy` | what is read, and what leaves this machine |

Add `--json` to any command for machine-readable output, `--days N` to change the window.

## Privacy

This tool reads your agent logs. Those logs contain your prompts, fragments of your code and
sometimes your secrets. You should not take anyone's word about what happens to them —
including ours.

So, plainly:

- **No network code.** The binary opens no sockets, contacts no host, and carries no telemetry,
  no version check and no analytics of any kind.
- **No account.** There is nothing to sign into.
- **Nothing is written** except the dashboard file you explicitly ask for with `pandev web` —
  created `0600`, owner-only, in your own home directory. It contains your prompt text, so
  treat it like the logs it came from.

`npx pandev privacy` prints the full list of what is read and what is taken from it.

**And here is how to check that for yourself, without trusting us** — network activity is
observable from outside the process, so the claim is verifiable even though this is not open
source: **[docs/VERIFY.md](docs/VERIFY.md)**.

## Requirements

Node 20 or newer for `npx`. Optional but recommended: `git` on your `PATH` — without it,
per-task attribution is switched off and you get totals only.

Reads logs from:

- Claude Code — `~/.claude/projects`
- Codex CLI — `~/.codex/sessions`

Nothing else is scanned.

## Working in a team?

This tool is deliberately single-player. It reads what is on *your* machine and answers
questions about *your* work.

If the question turned into "how does this compare across the team", "which projects burn the
most", or "what does AI actually cost us per delivered ticket" — that is
[PanDev Metrics](https://pandev.io), and it is a different product.

## License

Proprietary — see [LICENSE](LICENSE). Free to install and run on machines you own or control,
including at work. Redistribution, modification and derivative works are not permitted.

Cost figures are estimates computed from published provider rate tables. They are not an
invoice. Reconcile against your provider's own billing.

---

<div align="center">
<sub>Built by <a href="https://pandev.io">PanDev</a> · Found a bug? <a href="../../issues/new/choose">Open an issue</a></sub>
</div>
