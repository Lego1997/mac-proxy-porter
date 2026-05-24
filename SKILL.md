---
name: mac-proxy-sync
description: Install, diagnose, update, or remove a macOS zsh setup that auto-syncs the active system proxy (scutil --proxy) into http_proxy/https_proxy/ALL_PROXY env vars on every shell start and every 60 seconds between prompts, plus a syncproxy command that mirrors env to launchctl setenv for GUI apps. Use when the user asks to "set up proxy auto-sync", is behind a changing-port local proxy (Clash, V2Ray, Shadowsocks, Mihomo, Surge), has trouble with CLI tools such as claude, codex, npm, git, curl, or pip from Terminal, wants to know why proxy env vars are stale or missing, or wants to disable the auto-sync on a no-proxy-needed network. Also triggers on "status of proxy sync", "update proxy sync", and "uninstall mac-proxy-sync".
---

# Mac Proxy Porter

Auto-sync macOS system proxy settings into shell env vars so CLI tools
(`claude`, `codex`, `curl`, `git`, `npm`, `pip`) and GUI-app subprocesses
inherit them without manual `export`.

## Context

Use this when a macOS user relies on a local proxy and the HTTP/HTTPS or SOCKS
ports may change over time. The active values must be read from
`scutil --proxy`, not memorized or hard-coded. The goal is to make new Terminal
tabs, non-interactive zsh subprocesses, and later-launched GUI subprocesses
inherit the current proxy without manual `export` commands.

## What it does

Places one marker-bounded block in `~/.zshenv` (function + one-shot load;
runs for every zsh invocation including non-interactive subshells) and one in
`~/.zshrc` (a 60-second TTL `precmd` hook that re-reads `scutil --proxy`
between prompts, plus a `syncproxy` command that additionally pushes the env
to `launchctl setenv` for GUI apps).

## Modes

When invoked, determine intent and call the matching script:

1. **install** (default for "set up", "enable", "install", "why is claude
   failing behind my proxy"):
   ```
   bash ~/.codex/skills/mac-proxy-sync/scripts/install.sh
   ```
   Idempotent. Safe to re-run. Aborts with a diff if marker regions exist
   but differ from the canonical block (user must uninstall first).

2. **status** (for "check proxy sync", "is my proxy set up", "diagnose"):
   ```
   bash ~/.codex/skills/mac-proxy-sync/scripts/status.sh
   ```
   Read-only. Dumps scutil output, current shell env, launchctl env, marker
   presence in `~/.zshenv` / `~/.zshrc`, PATH resolution for `claude` and
   `codex`, git proxy override if set.

3. **update** (for "update proxy sync", "refresh the blocks"):
   ```
   bash ~/.codex/skills/mac-proxy-sync/scripts/install.sh --update
   ```
   Replaces marker regions with current `scripts/blocks/*.zsh`. Use after
   editing the canonical blocks.

4. **uninstall** (for "disable proxy sync", "remove mac-proxy-sync", or a
   no-proxy-needed network):
   ```
   bash ~/.codex/skills/mac-proxy-sync/scripts/uninstall.sh
   ```
   Removes both marker regions, runs `launchctl unsetenv` for each var, and
   prints explicit `unset ...; exec zsh` commands the user must paste into
   their current shell (a subshell can't unset the parent's env).

## The canonical zsh blocks

Source of truth: `scripts/blocks/zshenv.zsh` and `scripts/blocks/zshrc.zsh`.
Both scripts read from these files; never hardcode the block bodies
elsewhere.

## Markers

`# >>> mac-proxy-sync BEGIN >>>` ... `# <<< mac-proxy-sync END <<<`

conda/pyenv convention. Do not change; `install.sh` / `uninstall.sh` match
on these exact strings.

## See also

- `README.md` in this skill; background on why this exists and when to
  disable it.
- `~/.codex/skills/mac-proxy-sync/scripts/status.sh`; run anytime to get
  a full diagnostic dump.
