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

The blocks are managed by these scripts:

- `scripts/install.sh`: install or update the zsh blocks.
- `scripts/status.sh`: print a read-only diagnostic report.
- `scripts/uninstall.sh`: remove the zsh blocks and clear launchctl proxy env.

## Requirements

- macOS
- zsh
- Bash for the installer scripts
- A proxy configured in macOS System Settings when proxy env vars are needed

## Install

Clone or copy this repo into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
git clone https://github.com/Lego1997/mac-proxy-porter.git ~/.codex/skills/mac-proxy-sync

# Optional: expose the same skill to Claude Code
mkdir -p ~/.claude/skills
ln -s ~/.codex/skills/mac-proxy-sync ~/.claude/skills/mac-proxy-sync
```

Then install the shell integration:

```bash
bash ~/.codex/skills/mac-proxy-sync/scripts/install.sh
source ~/.zshenv && source ~/.zshrc && syncproxy
```

Open a new Terminal tab after installing. Later-launched GUI apps inherit values
set through `launchctl`; already-running GUI apps need to be quit and reopened.

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
|   |-- install.sh
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
