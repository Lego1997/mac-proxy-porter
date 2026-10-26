# >>> mac-proxy-sync BEGIN >>> do not edit; managed by ~/.codex/skills/mac-proxy-sync
# macOS system-proxy auto-sync (v4). Runs for every zsh invocation
# (interactive, zsh -c, scripts, LaunchAgents), so anything started from a
# shell begins life with a live proxy env. Resolution cascade:
#   1. scutil --proxy (the system proxy QuickQ maintains) -- used only if
#      its port actually accepts connections right now;
#   2. otherwise, if QuickQ is running, adopt its live listeners found via
#      lsof (HTTP 10900-10999, SOCKS 10000-10099) -- QuickQ rotates ports
#      on every reconnect and clears the system proxy while reconnecting;
#   3. when QuickQ is running and the stable relay listens, export the fixed
#      relay ports (17890/17891) so an already-running agent survives future
#      rotations and a reconnect window;
#   4. otherwise unset all proxy vars (genuinely proxy-free network).
# If scutil itself fails (e.g. fork exhaustion) the inherited env is kept
# untouched. Port probes use the ztcp builtin: no fork needed.

_mac_proxy_probe() {  # host port -> 0 iff a TCP connect succeeds
  emulate -L zsh
  [[ -n "${1:-}" && "${2:-}" == <-> ]] || return 1
  # Only active-probe loopback: a connect to a remote/hung proxy could
  # block the shell. Non-loopback hosts are trusted as configured.
  [[ "$1" == (127.0.0.1|localhost|::1) ]] || return 0
  zmodload zsh/net/tcp 2>/dev/null
  (( $+builtins[ztcp] )) || return 0   # cannot probe: trust the config
  local REPLY
  if ztcp "$1" "$2" 2>/dev/null; then
    ztcp -c "$REPLY" 2>/dev/null
    return 0
  fi
  return 1
}

_mac_proxy_sync() {
  emulate -L zsh
  local out line
  out="$(/usr/sbin/scutil --proxy 2>/dev/null)" || return 0
  [[ -n "$out" ]] || return 0

  local he=0 se=0 ke=0 hh='' hp='' hsh='' hsp='' kh='' kp=''
  local -a w
  for line in ${(f)out}; do
    w=(${(z)line})
    (( $#w >= 3 )) || continue
    case "$w[1]" in
      HTTPEnable)  he=$w[3]  ;;
      HTTPProxy)   hh=$w[3]  ;;
      HTTPPort)    hp=$w[3]  ;;
      HTTPSEnable) se=$w[3]  ;;
      HTTPSProxy)  hsh=$w[3] ;;
      HTTPSPort)   hsp=$w[3] ;;
      SOCKSEnable) ke=$w[3]  ;;
      SOCKSProxy)  kh=$w[3]  ;;
      SOCKSPort)   kp=$w[3]  ;;
    esac
  done

  local http_host='' http_port='' socks_host='' socks_port=''
  if [[ "$he" == 1 && -n "$hh" && -n "$hp" ]]; then
    http_host=$hh http_port=$hp
  elif [[ "$se" == 1 && -n "$hsh" && -n "$hsp" ]]; then
    http_host=$hsh http_port=$hsp
  fi
  if [[ "$ke" == 1 && -n "$kh" && -n "$kp" ]]; then
    socks_host=$kh socks_port=$kp
  fi

  # Dead or missing entries -> hunt for QuickQ's live listeners.
  local need_http=0 need_socks=0
  _mac_proxy_probe "$http_host" "$http_port" || { need_http=1; http_host=''; http_port=''; }
  _mac_proxy_probe "$socks_host" "$socks_port" || { need_socks=1; socks_host=''; socks_port=''; }
  # NB: process is named "QuickQ For Mac" -> substring pgrep, prefix lsof -c.
  local quickq_running=0
  /usr/bin/pgrep -q QuickQ 2>/dev/null && quickq_running=1
  if (( need_http || need_socks )) && (( quickq_running )); then
    local lsout='' p
    lsout="$(/usr/sbin/lsof -nP -a -c QuickQ -iTCP@127.0.0.1 -sTCP:LISTEN 2>/dev/null)"
    for line in ${(f)lsout}; do
      [[ "$line" =~ '127\.0\.0\.1:([0-9]+)' ]] || continue
      p=$match[1]
      if (( need_http )) && [[ -z "$http_port" ]] && (( p >= 10900 && p <= 10999 )); then
        http_host=127.0.0.1 http_port=$p
      elif (( need_socks )) && [[ -z "$socks_port" ]] && (( p >= 10000 && p <= 10099 )); then
        socks_host=127.0.0.1 socks_port=$p
      fi
    done
  fi

  # QuickQ rotates its real ports. Whenever QuickQ is running and the stable
  # relay is listening, export the fixed relay ports instead: a process that
  # starts with the relay address keeps working across every later rotation,
  # and even when started inside a reconnect window (no upstream yet) it
  # recovers as soon as QuickQ is back. A non-QuickQ proxy (other port range,
  # or a remote host) is left exactly as configured.
  local relay_http_port=17890 relay_socks_port=17891
  if (( quickq_running )); then
    local want_relay=0
    if [[ -z "$http_port" ]]; then
      want_relay=1
    elif [[ "$http_host" == (127.0.0.1|localhost|::1) && "$http_port" == <-> ]] \
         && (( http_port >= 10900 && http_port <= 10999 )); then
      want_relay=1
    fi
    if (( want_relay )) && _mac_proxy_probe 127.0.0.1 "$relay_http_port"; then
      http_host=127.0.0.1 http_port=$relay_http_port
    fi
    want_relay=0
    if [[ -z "$socks_port" ]]; then
      want_relay=1
    elif [[ "$socks_host" == (127.0.0.1|localhost|::1) && "$socks_port" == <-> ]] \
         && (( socks_port >= 10000 && socks_port <= 10099 )); then
      want_relay=1
    fi
    if (( want_relay )) && _mac_proxy_probe 127.0.0.1 "$relay_socks_port"; then
      socks_host=127.0.0.1 socks_port=$relay_socks_port
    fi
  fi

  local nv="localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,169.254.0.0/16"
  if [[ -n "$http_host" && -n "$http_port" ]]; then
    local hv="http://${http_host}:${http_port}"
    export http_proxy="$hv" HTTP_PROXY="$hv" https_proxy="$hv" HTTPS_PROXY="$hv" \
           grpc_proxy="$hv" GRPC_PROXY="$hv"
  else
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY grpc_proxy GRPC_PROXY
  fi
  if [[ -n "$socks_host" && -n "$socks_port" ]]; then
    local sv="socks5h://${socks_host}:${socks_port}"
    export ALL_PROXY="$sv" all_proxy="$sv"
  else
    unset ALL_PROXY all_proxy
  fi
  export no_proxy="$nv" NO_PROXY="$nv" no_grpc_proxy="$nv" NO_GRPC_PROXY="$nv"
  return 0
}
_mac_proxy_sync
# <<< mac-proxy-sync END <<<
