#!/bin/zsh
# mac-proxy-sync: mirror the resolved proxy env into `launchctl setenv` so
# GUI apps launched by launchd (Claude, ChatGPT, Cursor, Grok Bot, Codex
# Desktop, editors) and the CLIs they spawn inherit a working proxy.
#
# Run by the LaunchAgent com.pan.codex.quickq-proxy-env at login, every 60 s,
# and whenever the system proxy changes. Resolution itself lives in the
# ~/.zshenv block (zsh reads ~/.zshenv for this script automatically); this
# file only copies the result into the launchd gui domain. Only writes when a
# value changed, so the log stays quiet.
emulate -L zsh

if (( ! $+functions[_mac_proxy_sync] )); then
  [[ -r "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
fi
if (( ! $+functions[_mac_proxy_sync] )); then
  print -u2 -- "mac-proxy-sync: resolver missing from ~/.zshenv; run scripts/install.sh"
  exit 1
fi
_mac_proxy_sync

typeset -a vars
vars=(http_proxy HTTP_PROXY https_proxy HTTPS_PROXY grpc_proxy GRPC_PROXY
      no_proxy NO_PROXY no_grpc_proxy NO_GRPC_PROXY ALL_PROXY all_proxy)
typeset v val cur changed=0
for v in $vars; do
  val="${(P)v:-}"
  cur="$(/bin/launchctl getenv "$v" 2>/dev/null)"
  [[ "$val" == "$cur" ]] && continue
  changed=1
  if [[ -n "$val" ]]; then
    /bin/launchctl setenv "$v" "$val"
  else
    /bin/launchctl unsetenv "$v" 2>/dev/null
  fi
done
if (( changed )); then
  print -r -- "$(date '+%F %T') launchctl env updated: https_proxy=${https_proxy:-unset} ALL_PROXY=${ALL_PROXY:-unset}"
fi
exit 0
