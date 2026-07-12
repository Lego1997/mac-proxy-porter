# Why Claude Code froze inside Otty (RCA, 2026-07-10)

> **Scope note:** this is a root-cause analysis from the author's specific
> setup — Otty as the terminal, QuickQ as the proxy app, and a `~/.claude`
> directory synced by a cloud drive. The three mechanisms below are general,
> though: they can bite any Claude Code install whose hooks, proxy ports, or
> config files behave the same way, and they are what the freeze detectors in
> `scripts/status.sh` check for.

Multi-agent investigation of: *"In Otty, `claude` renders its TUI, but the
moment I type it becomes unresponsive — consistently. Codex in Otty is fine.
Claude in Apple Terminal is fine."*

**Verdict: the mac-proxy-sync zsh blocks were exonerated.** The blocks are
silent, add ~no preexec latency in the healthy path, never touch a TTY, and
Otty tabs get the same TERM (`xterm-256color`) and login-shell init as Apple
Terminal. Three real mechanisms were found, all with hard local evidence.

## Mechanism 1 — Otty's Claude hook holds Claude's stdout pipe (the Otty-specific freeze)

Otty (Settings → Agents → Install Hooks) registers
`/Applications/Otty.app/Contents/Resources/agent-integration/claude/otty-hook.sh`
in `~/.claude/settings.json` on six events (UserPromptSubmit, PreToolUse,
PostToolUse, SessionStart, Stop, PermissionRequest), **without a timeout**.
The stock script backgrounds `otty-cli state:claude … 2>/dev/null &` — only
stderr is redirected, so the backgrounded `otty-cli` inherits the hook's
stdout pipe. Claude Code waits for EOF on that pipe. When the Otty app's IPC
endpoint wedges, `otty-cli` never exits → every hook event stalls Claude
indefinitely.

Evidence: transcripts with a command **enqueued**, silence for 7–33 minutes,
then a one-second "death rattle" (`hook_success` → dequeue → EOF) at the
exact moment the tab was killed (e.g. sessions d87f424c Jul 6, 1dbccd5 Jul 8).
Codex is immune (no hook system); Apple Terminal is immune in practice
(`otty-cli` answers unknown sessions in ~0.3 s; only Otty-hosted sessions hit
the wedged pane path).

**Fix (applied 2026-07-10):** `~/.claude/hooks/otty-hook-safe.sh` execs the
stock script with stdout+stderr detached (`>/dev/null 2>&1`), so nothing it
backgrounds can hold Claude's pipes. Repoint the six stanzas:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-otty-hook
sed -i '' "s|/Applications/Otty.app/Contents/Resources/agent-integration/claude/otty-hook.sh|$HOME/.claude/hooks/otty-hook-safe.sh|g" ~/.claude/settings.json
```

If an Otty update re-registers the bundle path, `status.sh` will flag it —
re-run the sed. (The bundle script itself must not be edited: hardened
runtime, breaking the code signature can stop Otty from launching.)

## Mechanism 2 — dataless cloud placeholders block Claude in-kernel

A claude whose project lives under `~/Library/CloudStorage/…` (Google Drive)
was observed **live** (pid 32287) with its main thread parked in
`__pread_nocancel` on `.claude/settings.local.json` — a `compressed,dataless`
placeholder whose materialization was orphaned when DriveFS's FileProvider
extension restarted. The event loop never runs again: no input, no output,
no network. This freezes claude in ANY terminal; Otty just hosted the tabs.

Fix: restart the Google Drive app when placeholders stop materializing; keep
project `.claude/` folders "Available offline"; ideally keep agent projects
off cloud-synced mounts entirely. `status.sh` now flags running claudes with
dataless `.claude/*.json` in their cwd.

## Mechanism 3 — QuickQ port rotation stranded long-running processes

QuickQ rotates its local ports on every reconnect. Earlier versions fixed
new shells and commands, but an already-running claude/codex kept its direct
launch-time port. After a rotation its API calls refused or hung, which read
as "frozen" (observed: agents holding 10901/10902 while live listeners were
10905/10025).

Version 4 adds a localhost-only stable TCP relay on 17890/17891. New agents
keep those fixed endpoints while the relay follows QuickQ's current upstream
listeners per connection. Processes launched before v4 need one final
restart. `status.sh` identifies both stable-relay and legacy direct-port
processes.

## Otty itself (v1.2.3, latest as of 2026-07-10)

Real but secondary: leaks a zombie per closed tab (`waitpid` called once,
WNOHANG, never reaped), ships panic-recovery strings for its PTY reader
("term mutex poisoned in PTY reader"), and 1.2.2 rewrote PTY/input threading
(new modifyOtherKeys support — the path Claude actually uses here, since
Claude's kitty-protocol allow-list does not include Otty). Closed source, no
public tracker; report via the vendor. The older "Otty kills its PTY reader"
theory was NOT confirmed for the July incidents (all live tabs had intact
PTY masters); keep it as a historical suspect for output-side freezes only.

## Probe kit for the next live freeze (run from a second terminal)

1. `bash ~/.codex/skills/mac-proxy-sync/scripts/status.sh` — catches stale
   proxy env, unsafe hook registration, and dataless placeholders in one shot.
2. Find the tab's tty and claude pid: `ps -axww -o pid,tty,stat,etime,command | grep -E 'claude' | grep -v grep`
3. Where is it stuck? `sample <pid> 2 -file /tmp/claude-sample.txt && grep -A3 'Call graph' /tmp/claude-sample.txt | head`
   - `__pread_nocancel` on a CloudStorage file → Mechanism 2.
   - idle `kevent64` + dead proxy port in `ps eww <pid>` → Mechanism 3.
   - healthy-looking process + enqueued-but-unprocessed input → Mechanism 1
     (check `ps -axww | grep otty-cli` for a lingering hook child).
4. Is the terminal still rendering? `printf 'PING\n' > /dev/ttys00N` (the
   tab's tty). Text appears → app fine, process wedged. Nothing appears →
   Otty-side output freeze (only then suspect the PTY reader / renderer).
5. Keystroke-free live check of a suspect tab:
   `/Applications/Otty.app/Contents/MacOS/otty-cli pane capture` (read-only).

## Bug report material for the Otty vendor

- Hook: `otty-hook.sh` backgrounds `otty-cli` without redirecting stdout —
  hook consumers (Claude Code) block on the held pipe when IPC hangs; also
  register hooks with a `timeout`.
- IPC: `otty-cli state:claude` can block indefinitely when the app wedges —
  needs a client-side deadline.
- Lifecycle: one `waitpid(WNOHANG)` at session destroy leaks a zombie per
  closed tab (11 observed in ~30 h).
