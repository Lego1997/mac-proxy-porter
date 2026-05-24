# >>> mac-proxy-sync BEGIN >>> do not edit; managed by ~/.codex/skills/mac-proxy-sync
# Re-read macOS proxy at most once per 60 s between prompts, so long-running
# Terminal tabs pick up port rotations without manual intervention.
typeset -g _MAC_PROXY_LAST=0
_mac_proxy_sync_maybe() {
  emulate -L zsh
  local now=$EPOCHSECONDS
  (( now - _MAC_PROXY_LAST < 60 )) && return
  _MAC_PROXY_LAST=$now
  (( $+functions[_mac_proxy_sync] )) && _mac_proxy_sync
}
autoload -Uz add-zsh-hook 2>/dev/null
zmodload zsh/datetime 2>/dev/null
add-zsh-hook precmd _mac_proxy_sync_maybe 2>/dev/null

# syncproxy: force a re-read NOW + push env to launchctl so GUI apps launched
# after this inherit it. Already-running GUI apps need quit + relaunch to pick
# up the change.
syncproxy() {
  emulate -L zsh
  _MAC_PROXY_LAST=0
  (( $+functions[_mac_proxy_sync] )) && _mac_proxy_sync
  local v val
  for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
           no_proxy NO_PROXY ALL_PROXY all_proxy; do
    val="${(P)v}"
    if [[ -n "$val" ]]; then
      launchctl setenv "$v" "$val"
    else
      launchctl unsetenv "$v" 2>/dev/null || true
    fi
  done
  print -r -- "proxy synced to current shell + launchctl:"
  print -r -- "  http_proxy  = ${http_proxy:-unset}"
  print -r -- "  https_proxy = ${https_proxy:-unset}"
  print -r -- "  ALL_PROXY   = ${ALL_PROXY:-unset}"
  print -r -- "  no_proxy    = ${no_proxy:-unset}"
  print -r -- "Note: already-running GUI apps need quit + relaunch."
}
# <<< mac-proxy-sync END <<<
