# Verify it yourself

`pandev` claims it sends nothing. This page shows you how to confirm that without taking our
word for it, and without reading the source.

The reasoning is simple: **network activity is observable from outside a process.** You don't
need to see the code to know whether it opens a socket — you can just take the network away
and watch it keep working.

That test is stronger than reading code, because it also covers anything the code pulls in.

---

## The one-minute check

Run `pandev` with the network removed. If it produces the same output, it did not need the
network to produce it.

### macOS

```bash
sandbox-exec -p '(version 1)(allow default)(deny network*)' npx pandev
```

First confirm the sandbox is really blocking, otherwise the test proves nothing:

```bash
sandbox-exec -p '(version 1)(allow default)(deny network*)' curl -sS --max-time 5 https://example.com
```

That must fail. Then the `pandev` run above must succeed, and print exactly what it prints
normally.

> Note: `npx` itself downloads the package, so fetch it once with plain `npx pandev --version`
> before running the sandboxed command — otherwise you are testing npx's download, not the tool.

> One exception by design: `pandev web` binds a **loopback-only** server on `127.0.0.1:4976`,
> and `(deny network*)` blocks that bind too — so run the sandbox test with the report
> commands (`pandev`, `pandev task`, `pandev files`, …), which are the ones that touch your
> log data. What the dashboard adds on top is covered in
> [the sockets you should expect](#the-sockets-you-should-expect) below.

### Linux

Run it in a network namespace with no interfaces at all:

```bash
unshare --user --map-root-user --net -- npx pandev
```

Or, if you have firejail:

```bash
firejail --net=none npx pandev
```

### Windows

Block the executable in Windows Firewall and run it:

```powershell
New-NetFirewallRule -DisplayName "pandev test block" -Direction Outbound `
  -Program "$env:LOCALAPPDATA\npm-cache\_npx\...\pandev.exe" -Action Block
```

Remove the rule afterwards with `Remove-NetFirewallRule -DisplayName "pandev test block"`.

Alternatively, run it inside Windows Sandbox with networking disabled — one line in the `.wsb`
configuration file.

---

## Watching instead of blocking

If you would rather observe than restrict, any of these work and require no trust in us:

- **Little Snitch**, **LuLu** (macOS) or **OpenSnitch** (Linux) — outbound firewalls that prompt
  on any connection attempt. `pandev` should never produce a prompt.
- **`lsof -p <pid> -i`** while a long command such as `pandev web` is running.
- **`tcpdump`** or **Wireshark** on your interface, filtered to the machine.
- **Sysinternals TCPView** or **Process Monitor** on Windows.

### The sockets you should expect

`pandev web` (and the login dashboard service) is the one command that uses sockets at all,
and everything it does stays on `127.0.0.1`:

| What you will see | Why |
|---|---|
| `LISTEN` on `127.0.0.1:4976` (up to `:4985`) | the dashboard server — loopback only, unreachable from the network |
| short-lived connects to `127.0.0.1:4976–4985` | the CLI probing whether its own server is already running |
| your **browser** fetching `registry.npmjs.org` once per dashboard visit | an anonymous version check made by the served page, not by the binary; carries no data. The offline file `~/pandev-cost.html` never does this |

An outbound connection **from the `pandev` process** to anything that is not `127.0.0.1`
would contradict this page — report it.

---

## Verifying you got the binary we published

Every release publishes SHA-256 checksums for each platform artifact. Compare them:

```bash
# macOS / Linux
shasum -a 256 <path-to-binary>

# Windows
Get-FileHash <path-to-binary> -Algorithm SHA256
```

The expected values are on the [Releases](../../releases) page for the version you installed.
A mismatch means the file you have is not the file we shipped — stop and tell us.

---

## What the tool reads

Blocking the network proves nothing leaves. This is the other half — what it touches at all:

| | |
|---|---|
| `~/.claude/projects` | Claude Code session logs |
| `~/.codex/sessions` | Codex CLI session logs |
| `git rev-parse`, `git reflog` | in the working directories those logs point at |

From those files it takes token counts, model names, timestamps, session ids, branch names,
tool names and file paths. Prompt text is read only by `pandev task <KEY>` and `pandev web`,
printed, and never stored anywhere else.

Model replies, file contents and shell output are not read.

You can watch this too:

```bash
# macOS — every file the process opens
sudo fs_usage -w -f filesystem | grep pandev

# Linux
strace -f -e trace=openat,connect -o /tmp/pandev.trace npx pandev
```

In that Linux trace of a report command, `connect` should never appear. For `pandev web` the
only `connect` targets you should ever see are `127.0.0.1:4976`–`4985` — the CLI checking on
its own server. Anything else contradicts this page.

---

## What it writes

`pandev web` creates a dashboard file in your home directory: `~/pandev-cost.html`,
mode `0600`, owner-only. It is a single self-contained HTML file: fonts are embedded, it
makes no network requests at all when you open it. **It contains your prompt text** — treat
it exactly like the logs it was built from. Delete it whenever you like; the tool rebuilds
it on demand.

If you turn the login dashboard on (`pandev autostart on`, or by accepting the offer on the
first interactive run), it also writes the login item itself:

- macOS — `~/Library/LaunchAgents/io.pandev.b2c.dashboard.plist` + `~/.config/pandev/b2c-dashboard.sh`
- Linux — `~/.config/systemd/user/pandev-b2c-dashboard.service` + the same shim script

`pandev autostart off` removes all of it. Nothing else is ever written.

---

## Why this page exists

`pandev` ships as a compiled binary, so you cannot read the source to check these claims.
That is a deliberate trade — and it puts the burden on us to give you a way to check anyway.

The tests above are that way. They are better than source review in one important respect:
they measure what the program *does*, not what it appears to say.

Found a discrepancy between this page and what you observe? That is a security issue — see
[SECURITY.md](../SECURITY.md). We want to hear about it before anyone else does.
