# Mac Proxy Porter

Mac Proxy Porter is a small Codex skill and script bundle for macOS users who
run command-line tools behind a local or system-configured proxy. It reads the
active macOS proxy settings with `scutil --proxy`, exports the matching shell
environment variables, and can mirror them into `launchctl` for GUI-launched
subprocesses.

It is useful when proxy ports change, when new Terminal tabs lose proxy access,
or when tools such as `curl`, `git`, `npm`, `pip`, `codex`, and `claude` need
the same proxy that macOS already knows about.

## What It Installs

Mac Proxy Porter installs two marker-bounded zsh blocks:

1. `~/.zshenv`: defines `_mac_proxy_sync` and runs it once for every zsh
   invocation, including non-interactive shells.
2. `~/.zshrc`: adds a 60-second `precmd` refresh hook and a `syncproxy`
   command that pushes the current proxy env into `launchctl setenv`.

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
- `ALL_PROXY` and `all_proxy` when SOCKS proxy settings are enabled.
- `no_proxy` and `NO_PROXY` for localhost, common LAN ranges, and `.local`.

The zsh block avoids exporting incomplete values such as `http://:`. The
interactive prompt hook refreshes at most once every 60 seconds so long-running
Terminal tabs can pick up proxy changes without calling `scutil` at every
prompt.

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
|-- scripts
|   |-- blocks
|   |   |-- zshenv.zsh
|   |   `-- zshrc.zsh
|   |-- install.sh
|   |-- status.sh
|   `-- uninstall.sh
`-- LICENSE
```

## Contributing

Issues and pull requests are welcome. Please keep changes focused on the macOS
proxy-sync workflow and test installer behavior on a disposable zsh profile when
possible.

## License

MIT. See [LICENSE](LICENSE).
