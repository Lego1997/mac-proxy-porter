---
name: mac-proxy-sync
description: Install, diagnose, update, or remove a macOS zsh setup that auto-syncs the active system proxy (scutil --proxy) into http_proxy/https_proxy/ALL_PROXY env vars on every shell start AND right before every interactive command launches (preexec), falling back to the proxy app's live listener (lsof scan, QuickQ-style rotating ports) when the system proxy is stale or momentarily cleared, plus a syncproxy command and companion LaunchAgent that mirror env to launchctl setenv for GUI apps. Use when the user asks to "set up proxy auto-sync", is behind a changing-port local proxy (Clash, V2Ray, Shadowsocks, Mihomo, Surge), has trouble with CLI tools such as claude, codex, npm, git, curl, or pip from Terminal, wants to know why proxy env vars are stale or missing, or wants to disable the auto-sync on a no-proxy-needed network. Also triggers on "status of proxy sync", "update proxy sync", and "uninstall mac-proxy-sync".
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

Places one marker-bounded block in `~/.zshenv` (resolver function + one-shot
load; runs for every zsh invocation including non-interactive subshells) and
one in `~/.zshrc` (a `preexec` hook with 2 s TTL that re-resolves the proxy
right before each interactive command executes — so a long-idle tab still
launches `claude`/`codex` with the CURRENT port — plus a 60 s `precmd`
backstop and a `syncproxy` command that additionally pushes the env to
`launchctl setenv` for GUI apps). The managed env set includes HTTP(S), gRPC,
SOCKS, and matching no-proxy variables.

Resolution cascade (v4): 1) `scutil --proxy`, used only if the configured
port actually accepts a TCP connect (probed with the fork-free `ztcp`
builtin); 2) otherwise, if the proxy app is running, adopt its live
listeners found via `lsof` (QuickQ convention: HTTP 10900-10999, SOCKS
10000-10099 — the app rotates ports on every reconnect and clears the
system proxy while reconnecting); 3) when QuickQ is active, export fixed
localhost relay ports (HTTP 17890, SOCKS 17891) whose LaunchAgent follows
the rotating upstream listeners per connection, allowing already-running
agents to recover after reconnect; 4) otherwise unset all proxy vars. If
`scutil` itself errors (e.g. fork exhaustion), the inherited env is kept
untouched rather than clobbered.

A companion LaunchAgent (`~/Library/LaunchAgents/com.pan.codex.quickq-proxy-env.plist`
running `~/.codex/quickq-proxy-env.sh`) mirrors the same resolved env into
`launchctl setenv` at login, every 60 s, and immediately on system-proxy
changes (WatchPaths on `/Library/Preferences/SystemConfiguration/preferences.plist`),
so GUI-launched apps (Codex Desktop, editors) inherit a live proxy too. The
script relies on the `~/.zshenv` block for resolution, so keep both in sync.
Limitation (by design): an already-running process keeps the env it started
with — restart the app/CLI after a proxy change mid-session.

## Modes

When invoked, determine intent and call the matching script:

1. **install** (default for "set up", "enable", "install", "why is claude
   failing behind my proxy"):
   ```
   bash ~/.codex/skills/mac-proxy-sync/scripts/install.sh
   ```
   Idempotent. Safe to re-run. Aborts with a diff if marker regions exist
   but differ from the canonical block (user must uninstall first).

2. **status** (for "check proxy sync", "is my proxy set up", "diagnose",
   "claude/codex looks frozen"):
   ```
   bash ~/.codex/skills/mac-proxy-sync/scripts/status.sh
   ```
   Read-only. Dumps scutil output, current shell env, launchctl env, marker
   presence in `~/.zshenv` / `~/.zshrc`, PATH resolution for `claude` and
   `codex`, git proxy override if set. v4 also detects three agent-freeze
   hazards: an unsafe Otty→Claude hook registration in
   `~/.claude/settings.json`, running claude/codex processes whose proxy env
   points at rotated-away ports (they need a restart, not a fix), and
   dataless cloud-storage placeholders under a running claude's `.claude/`
   directory. See `TROUBLESHOOTING-otty-claude.md` for the full root-cause
   chain behind each detector.

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
- `TROUBLESHOOTING-otty-claude.md`; the 2026-07-10 root-cause analysis of
  "Claude Code freezes on first keystroke inside Otty" (spoiler: this
  skill's zsh blocks were exonerated), the three real freeze mechanisms,
  their fixes, and a copy-paste probe kit for the next live freeze.

## Claude Code visibility

This directory is symlinked from `~/.claude/skills/mac-proxy-sync`, so the
same skill appears as `/mac-proxy-sync` in Claude Code (which only scans
`~/.claude/skills`) while Codex keeps reading `~/.codex/skills`. If the
slash command disappears, recreate the symlink:
`ln -s ~/.codex/skills/mac-proxy-sync ~/.claude/skills/mac-proxy-sync`
