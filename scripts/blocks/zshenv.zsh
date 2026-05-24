# >>> mac-proxy-sync BEGIN >>> do not edit; managed by ~/.codex/skills/mac-proxy-sync
# macOS system-proxy auto-sync. Reads scutil --proxy, exports http_proxy /
# https_proxy / no_proxy / ALL_PROXY. Runs for every zsh invocation so
# non-interactive shells (zsh -c ..., scripts, subprocesses spawned by CLI
# tools) also get the proxy.
_mac_proxy_sync() {
  emulate -L zsh
  local out eval_line
  out="$(/usr/sbin/scutil --proxy 2>/dev/null)" || return 0
  eval_line="$(print -r -- "$out" | awk '
    $1 == "HTTPEnable"   { he = $3 }
    $1 == "HTTPProxy"    { hh = $3 }
    $1 == "HTTPPort"     { hp = $3 }
    $1 == "HTTPSEnable"  { se = $3 }
    $1 == "HTTPSProxy"   { sh = $3 }
    $1 == "HTTPSPort"    { sp = $3 }
    $1 == "SOCKSEnable"  { ke = $3 }
    $1 == "SOCKSProxy"   { kh = $3 }
    $1 == "SOCKSPort"    { kp = $3 }
    END {
      if (he == "1" && hh != "" && hp != "") \
        printf "export http_proxy=http://%s:%s HTTP_PROXY=http://%s:%s; ", hh, hp, hh, hp
      else \
        printf "unset http_proxy HTTP_PROXY; "
      if (se == "1" && sh != "" && sp != "") \
        printf "export https_proxy=http://%s:%s HTTPS_PROXY=http://%s:%s; ", sh, sp, sh, sp
      else \
        printf "unset https_proxy HTTPS_PROXY; "
      if (ke == "1" && kh != "" && kp != "") \
        printf "export ALL_PROXY=socks5h://%s:%s all_proxy=socks5h://%s:%s; ", kh, kp, kh, kp
      else \
        printf "unset ALL_PROXY all_proxy; "
    }')"
  eval "$eval_line"
  export no_proxy="localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,169.254.0.0/16"
  export NO_PROXY="$no_proxy"
}
_mac_proxy_sync
# <<< mac-proxy-sync END <<<
