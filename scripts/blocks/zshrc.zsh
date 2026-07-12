# >>> mac-proxy-sync BEGIN >>> do not edit; managed by ~/.codex/skills/mac-proxy-sync
# Launch-time freshness: QuickQ rotates its local port on every reconnect.
# The stable relay keeps already-running agents alive across rotations, while
# preexec still re-reads system state before each new interactive command.
# precmd (60 s TTL) additionally keeps idle prompts fresh. TTLs use $SECONDS
# (shell-local, always available).
typeset -g _MAC_PROXY_LAST=-999999
_mac_proxy_sync_maybe() {  # $1 = min seconds between re-reads
  emulate -L zsh
  (( $+functions[_mac_proxy_sync] )) || return 0
  # The TTL only ever SKIPS a re-read while the current env looks healthy
  # (proxy set and its loopback port accepts connections). Empty or dead
  # env is repaired immediately, TTL or not.
  if [[ -n "${https_proxy:-}" ]] \
     && [[ "$https_proxy" =~ '://([^:/]+):([0-9]+)' ]] \
     && _mac_proxy_probe "$match[1]" "$match[2]"; then
    (( SECONDS - _MAC_PROXY_LAST >= ${1:-60} )) || return 0
  fi
  typeset -g _MAC_PROXY_LAST=$SECONDS
  _mac_proxy_sync
  return 0
}
_mac_proxy_sync_preexec() { _mac_proxy_sync_maybe 2; return 0 }
_mac_proxy_sync_precmd()  { _mac_proxy_sync_maybe 60; return 0 }
autoload -Uz add-zsh-hook 2>/dev/null
add-zsh-hook preexec _mac_proxy_sync_preexec 2>/dev/null
add-zsh-hook precmd  _mac_proxy_sync_precmd  2>/dev/null
# Run our preexec first so another hook erroring can't starve the sync.
(( ${preexec_functions[(I)_mac_proxy_sync_preexec]} )) && \
  preexec_functions=(_mac_proxy_sync_preexec ${preexec_functions:#_mac_proxy_sync_preexec})

# syncproxy: force a re-read NOW + push env to launchctl so GUI apps
# launched after this inherit it. (A LaunchAgent, com.pan.codex.quickq-
# proxy-env, does the same automatically at login, every 60 s, and on
# system-proxy changes.) Apps launched with the stable relay keep working
# across future QuickQ rotations; apps holding an old direct port need one
# final restart after this update.
syncproxy() {
  emulate -L zsh
  (( $+functions[_mac_proxy_sync] )) && _mac_proxy_sync
  typeset -g _MAC_PROXY_LAST=$SECONDS
  local v val
  for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
           grpc_proxy GRPC_PROXY no_proxy NO_PROXY \
           no_grpc_proxy NO_GRPC_PROXY ALL_PROXY all_proxy; do
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
  print -r -- "  grpc_proxy  = ${grpc_proxy:-unset}"
  print -r -- "  ALL_PROXY   = ${ALL_PROXY:-unset}"
  print -r -- "  no_proxy    = ${no_proxy:-unset}"
  print -r -- "Note: restart apps once if they still hold a direct 109xx/100xx port."
}
# <<< mac-proxy-sync END <<<
