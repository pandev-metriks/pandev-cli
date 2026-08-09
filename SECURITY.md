# Security

## Reporting

Email **security@pandev.io**. If you prefer, open a
[draft security advisory](../../security/advisories/new) instead — that keeps the report
private until a fix ships.

Please do not open a public issue for anything that touches user data.

We aim to acknowledge within two working days.

## What we consider a security issue here

This tool reads files that contain prompts, code fragments and sometimes credentials. Anything
that widens the blast radius of that is in scope:

- **Any outbound network activity.** There should be none, ever. If you observe a connection
  attempt, that is the highest-severity report we can receive — see [docs/VERIFY.md](docs/VERIFY.md)
  for how to capture it.
- **The dashboard file being written world-readable**, outside the user's home directory, or to
  a predictable shared path. It is meant to be `0600` in your own home directory and it contains
  prompt text.
- **Prompt text or file contents appearing anywhere they should not** — in logs, in temporary
  files, in `--json` output that documents itself as counts-only.
- **Command injection through file paths, branch names or task keys.** This tool shells out to
  `git` and reads attacker-influenceable strings from repositories.
- **Path traversal** when resolving log directories from `CLAUDE_CONFIG_DIR` or `CODEX_HOME`.
- **A checksum mismatch** between a published release artifact and what the registry serves.

## Not in scope

- Inaccurate cost figures. They are estimates from published rate tables and are explicitly not
  an invoice — see the LICENSE. Report those as ordinary issues; we do want them.
- The contents of your own dashboard file after you have shared it yourself.
- Vulnerabilities in Node, npm or your terminal emulator.

## Supported versions

The latest published version is supported. Because this tool has no update check and no version
telemetry by design, we cannot notify you — fixes are announced on the
[Releases](../../releases) page and older broken versions are marked with `npm deprecate`, which
your package manager will print at install time.

If you install with `npx pandev`, you get the current version on every run.
