# Mac Proxy Porter

Mac Proxy Porter (this repository, `mac-proxy-porter`) packages the
**`mac-proxy-sync`** skill — a small Claude Code / Codex skill and script
bundle for macOS users who run command-line tools behind a local or
system-configured proxy. It reads the
active macOS proxy settings with `scutil --proxy`, exports the matching shell
environment variables, and can mirror them into `launchctl` for GUI-launched
subprocesses.

It is useful when proxy ports change, when new Terminal tabs lose proxy access,
or when tools such as `curl`, `git`, `npm`, `pip`, `codex`, and `claude` need
the same proxy that macOS already knows about.

## What It Installs

Mac Proxy Porter installs two marker-bounded zsh blocks:

1. `~/.zshenv`: defines the `_mac_proxy_sync` resolver and runs it once for
   every zsh invocation, including non-interactive shells.
2. `~/.zshrc`: adds a `preexec` hook (2 s TTL) that re-resolves the proxy
   right before each interactive command executes, a 60-second `precmd`
   backstop, and a `syncproxy` command that pushes the current proxy env
   into `launchctl setenv`.

It also installs two user LaunchAgents:

1. `com.pan.codex.quickq-stable-relay`: a localhost TCP relay on fixed ports
   (HTTP 17890, SOCKS 17891) that follows QuickQ's rotating listeners, so a
   long-running agent keeps working across reconnects.
2. `com.pan.codex.quickq-proxy-env`: runs `~/.codex/quickq-proxy-env.sh` at
   login, every 60 s, and on system-proxy changes to mirror the resolved env
   into `launchctl setenv`, so GUI apps and the CLIs they spawn inherit it.

The blocks are managed by these scripts:

- `scripts/bootstrap.sh`: one-shot placement + Claude Code link + install.
- `scripts/install.sh`: install or update the zsh blocks and LaunchAgents.
- `scripts/status.sh`: print a read-only diagnostic report (includes a
  per-GUI-app relaunch detector).
- `scripts/uninstall.sh`: remove the zsh blocks and LaunchAgents and clear
  launchctl proxy env.

## Requirements

- macOS
- zsh
- Bash for the installer scripts
- A proxy configured in macOS System Settings when proxy env vars are needed

## Install

One-shot (clones into the Codex skills directory, links it into Claude Code's
skills directory, installs the shell blocks and both LaunchAgents):

```bash
git clone https://github.com/Lego1997/mac-proxy-porter.git ~/.codex/skills/mac-proxy-sync
bash ~/.codex/skills/mac-proxy-sync/scripts/bootstrap.sh
source ~/.zshenv && source ~/.zshrc && syncproxy
```

`bootstrap.sh` can also be run from any other checkout; it copies the files
into `~/.codex/skills/mac-proxy-sync` first. Pass `--update` after pulling a
new version.

Open a new Terminal tab after installing. GUI apps (Claude Desktop, ChatGPT
Desktop, Cursor, Grok Bot, Codex Desktop) read the proxy env from launchd when
they start, so quit and reopen any that were already running.

## Usage

Check the current setup:

```bash
bash ~/.codex/skills/mac-proxy-sync/scripts/status.sh
```

Force a refresh in the current shell and mirror the result to `launchctl`:

```bash
syncproxy
```

Update the managed zsh blocks after pulling a new version:

```bash
bash ~/.codex/skills/mac-proxy-sync/scripts/install.sh --update
```

Uninstall:

```bash
bash ~/.codex/skills/mac-proxy-sync/scripts/uninstall.sh
```

The uninstall script removes the managed blocks and prints the final command to
clear proxy variables from the current parent shell.

## How It Works

`scutil --proxy` exposes the active macOS proxy configuration for the current
network service. Mac Proxy Porter parses that output and exports:

- `http_proxy` and `HTTP_PROXY` when HTTP proxy settings are enabled.
- `https_proxy` and `HTTPS_PROXY` when HTTPS proxy settings are enabled.
- `grpc_proxy` and `GRPC_PROXY` from the active HTTP(S) proxy.
- `ALL_PROXY` and `all_proxy` when SOCKS proxy settings are enabled.
- `no_proxy` / `NO_PROXY` and `no_grpc_proxy` / `NO_GRPC_PROXY` for localhost,
  common LAN ranges, and `.local`.

The zsh block avoids exporting incomplete values such as `http://:`.

The resolver does not blindly trust `scutil`: it first TCP-probes the
configured port (via the fork-free zsh `ztcp` builtin). If the port is dead,
or the system proxy is momentarily cleared (proxy apps like QuickQ rotate
their local port on every reconnect and clear the system proxy while
reconnecting), it adopts the app's live listener found via `lsof`
(HTTP 10900-10999, SOCKS 10000-10099). Only when neither source yields a
working proxy are the variables unset. If `scutil` itself fails to run, the
inherited environment is left untouched.

When QuickQ is connected, the exported values use fixed local relay ports
(`127.0.0.1:17890` for HTTP and `127.0.0.1:17891` for SOCKS). The relay is a
localhost-only raw TCP forwarder managed by launchd. It re-discovers QuickQ's
current listeners every 500 ms and retries discovery when a connection races
with a rotation. This lets a long-running Claude or Codex process reconnect
after QuickQ changes ports without restarting the agent.

While QuickQ is running and the relay is listening, the relay address is
used even during a reconnect window when QuickQ has no live listener yet, so
a process started in that window recovers on its own once QuickQ is back.

The `preexec` hook re-resolves right after you press Enter and before the
command runs — so even a tab that sat idle across several proxy restarts
launches `claude` / `codex` with the current port. Its 2-second TTL only
ever skips a re-read while the current env is confirmed healthy (proxy set
and its loopback port accepting connections); an empty or dead env is
repaired immediately.
A process launched before the stable relay was installed may still hold a
direct 109xx/100xx port. Restart it once; processes launched afterward keep a
fixed relay address across future QuickQ reconnects.

## Safety Notes

- The installer only edits marker-bounded regions between:
  `# >>> mac-proxy-sync BEGIN >>>` and `# <<< mac-proxy-sync END <<<`.
- Re-running the installer is idempotent when the installed blocks match the
  bundled blocks.
- If an existing marker block differs, the installer prints a diff and stops
  unless you pass `--update`.
- `status.sh` is read-only except for normal network requests made by its
  connectivity probe.

## Troubleshooting

Run the status script first:

```bash
bash ~/.codex/skills/mac-proxy-sync/scripts/status.sh
```

It reports `scutil --proxy`, current shell proxy variables, `launchctl` proxy
variables, marker presence in `~/.zshenv` and `~/.zshrc`, common tool
resolution, global git proxy overrides, and a quick HTTPS connectivity probe.

If `git config --global http.proxy` or `git config --global https.proxy` is set,
git may ignore the environment variables. Unset those overrides if they are
stale.

SSH does not use `HTTPS_PROXY`. If you need git-over-SSH through a SOCKS proxy,
configure `ProxyCommand` in `~/.ssh/config` separately.

## Repository Layout

```text
.
|-- SKILL.md
|-- README.md
|-- TROUBLESHOOTING-otty-claude.md
|-- scripts
|   |-- blocks
|   |   |-- zshenv.zsh
|   |   `-- zshrc.zsh
|   |-- bootstrap.sh
|   |-- install.sh
|   |-- quickq-proxy-env.sh
|   |-- quickq-stable-relay.js
|   |-- status.sh
|   |-- test-quickq-stable-relay.js
|   `-- uninstall.sh
`-- LICENSE
```

## Contributing

Issues and pull requests are welcome. Please keep changes focused on the macOS
proxy-sync workflow and test installer behavior on a disposable zsh profile when
possible.

## License

MIT. See [LICENSE](LICENSE).
