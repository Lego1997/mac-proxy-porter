#!/usr/bin/env bash
# Pure diagnostic: dump everything a human or agent needs to understand the
# current state of proxy sync on this machine. Read-only.
#
# v4 (2026-07-10) adds three agent-freeze detectors born from a root-cause
# investigation of "claude TUI freezes on first keystroke inside Otty":
#   - Otty agent-hook safety (stock hook can hold Claude's hook stdout pipe)
#   - running claude/codex processes whose proxy env points at rotated-away
#     QuickQ ports (they look frozen; they need a restart)
#   - dataless cloud-storage placeholders under a running claude's .claude/
#     (a synchronous read of one blocks claude's main thread in-kernel)
# Details: ../TROUBLESHOOTING-otty-claude.md
set -u

BEGIN_MARK='# >>> mac-proxy-sync BEGIN >>>'

hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }
bad() { printf '\033[31m%s\033[0m\n' "$*"; }
dim() { printf '\033[2m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }

RELAY_HTTP_PORT=17890
RELAY_SOCKS_PORT=17891

hdr "scutil --proxy"
/usr/sbin/scutil --proxy 2>/dev/null || bad "  (scutil failed)"

hdr "Current shell env"
# We print even if running in bash; the parent zsh's env is passed through.
for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
         grpc_proxy GRPC_PROXY no_proxy NO_PROXY \
         no_grpc_proxy NO_GRPC_PROXY ALL_PROXY all_proxy; do
  printf '  %-14s = %s\n' "$v" "${!v:-<unset>}"
done

hdr "launchctl getenv (GUI-inherited)"
for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
         grpc_proxy GRPC_PROXY no_proxy NO_PROXY \
         no_grpc_proxy NO_GRPC_PROXY ALL_PROXY all_proxy; do
  val="$(launchctl getenv "$v" 2>/dev/null || true)"
  printf '  %-14s = %s\n' "$v" "${val:-<unset>}"
done

hdr "Marker presence in dotfiles"
for f in "$HOME/.zshenv" "$HOME/.zshrc"; do
  if [[ -f "$f" ]] && grep -qF "$BEGIN_MARK" "$f"; then
    ok "  $f: installed"
  elif [[ -f "$f" ]]; then
    bad "  $f: NO marker block"
  else
    bad "  $f: file does not exist"
  fi
done

hdr "Tool resolution"
for t in claude codex node npm git curl; do
  p="$(command -v "$t" 2>/dev/null || true)"
  if [[ -n "$p" ]]; then
    ok "  $t -> $p"
  else
    bad "  $t NOT on PATH"
  fi
done

hdr "Git proxy overrides (these override env if set)"
for k in http.proxy https.proxy; do
  v="$(git config --global --get "$k" 2>/dev/null || true)"
  if [[ -n "$v" ]]; then
    bad "  git config --global $k = $v  (overrides env!)"
  else
    dim "  git config --global $k  (unset; good)"
  fi
done

hdr "QuickQ stable relay"
quickq_lsof="$(lsof -nP -a -c QuickQ -iTCP@127.0.0.1 -sTCP:LISTEN 2>/dev/null || true)"
quickq_http_port="$(printf '%s\n' "$quickq_lsof" | awk -F: '$NF ~ /^109[0-9][0-9] / {sub(/ .*/, "", $NF); print $NF}' | tail -1)"
quickq_socks_port="$(printf '%s\n' "$quickq_lsof" | awk -F: '$NF ~ /^100[0-9][0-9] / {sub(/ .*/, "", $NF); print $NF}' | tail -1)"
relay_http_pid="$(lsof -nP -tiTCP:"$RELAY_HTTP_PORT" -sTCP:LISTEN 2>/dev/null || true)"
relay_socks_pid="$(lsof -nP -tiTCP:"$RELAY_SOCKS_PORT" -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$relay_http_pid" && -n "$relay_socks_pid" ]]; then
  ok "  stable relay listening: HTTP 127.0.0.1:$RELAY_HTTP_PORT, SOCKS 127.0.0.1:$RELAY_SOCKS_PORT"
  if [[ -n "$quickq_http_port" || -n "$quickq_socks_port" ]]; then
    ok "  current QuickQ upstream: HTTP ${quickq_http_port:-off}, SOCKS ${quickq_socks_port:-off}"
  else
    dim "  QuickQ currently has no live upstream listeners (disconnected)"
  fi
else
  bad "  stable relay is not fully running; already-running agents cannot survive QuickQ rotation"
  dim "  run: bash ~/.codex/skills/mac-proxy-sync/scripts/install.sh --update"
fi

hdr "Quick connectivity probe (10s timeout)"
if [[ -n "${https_proxy:-}" ]]; then
  probe_url="${MAC_PROXY_PROBE_URL:-https://example.com/}"
  code="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$probe_url" 2>/dev/null || echo 000)"
  if [[ "$code" =~ ^[245] ]]; then
    ok "  ${probe_url} via proxy ${https_proxy}: HTTP ${code} (proxy OK; any HTTP response means the CONNECT tunnel worked)"
  else
    bad "  ${probe_url} via proxy ${https_proxy}: HTTP ${code} (proxy likely unreachable; is the local proxy app running?)"
  fi
else
  dim "  (no https_proxy set; skipping probe)"
fi

hdr "Agent-hook safety (Claude Code x Otty)"
SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$SETTINGS" ]] && grep -q 'agent-integration/claude/otty-hook.sh' "$SETTINGS"; then
  bad "  ~/.claude/settings.json registers Otty's stock hook (agent-integration/claude/otty-hook.sh)."
  bad "  It backgrounds otty-cli WITHOUT redirecting stdout: a wedged Otty IPC endpoint then"
  bad "  holds Claude's hook pipe open and EVERY hook event (UserPromptSubmit/PreToolUse/...)"
  bad "  stalls indefinitely -> claude renders, then freezes the moment you type. Fix:"
  echo '    cp ~/.claude/settings.json ~/.claude/settings.json.bak-otty-hook'
  echo '    sed -i '\'''\'' "s|/Applications/Otty.app/Contents/Resources/agent-integration/claude/otty-hook.sh|$HOME/.claude/hooks/otty-hook-safe.sh|g" ~/.claude/settings.json'
elif [[ -f "$SETTINGS" ]] && grep -q 'otty-hook-safe.sh' "$SETTINGS"; then
  if [[ -x "$HOME/.claude/hooks/otty-hook-safe.sh" ]]; then
    ok "  Otty hook routed through ~/.claude/hooks/otty-hook-safe.sh (detached stdio; cannot stall claude)"
  else
    bad "  settings.json points at ~/.claude/hooks/otty-hook-safe.sh but the wrapper is missing or not executable"
  fi
else
  dim "  no Otty agent hook registered in ~/.claude/settings.json"
fi

hdr "Running agents vs live proxy ports (stale-env detector)"
live_ports="$(lsof -nP -iTCP@127.0.0.1 -sTCP:LISTEN 2>/dev/null | awk '{n=split($9,a,":"); print a[n]}' | sort -u)"
found_agent=0
while read -r pid comm; do
  [[ -n "$pid" ]] || continue
  found_agent=1
  env_blob="$(ps eww -p "$pid" 2>/dev/null | tail -1)"
  port="$(printf '%s' "$env_blob" | sed -n 's/.*HTTPS_PROXY=http:\/\/127\.0\.0\.1:\([0-9]*\).*/\1/p')"
  if [[ -z "$port" ]]; then
    dim "  pid $pid ($(basename "$comm")): no loopback HTTPS_PROXY in its env"
  elif [[ "$port" == "$RELAY_HTTP_PORT" && -n "$relay_http_pid" ]]; then
    if [[ -n "$quickq_http_port" ]]; then
      ok "  pid $pid ($(basename "$comm")): stable relay -> current QuickQ HTTP $quickq_http_port"
    else
      warn "  pid $pid ($(basename "$comm")): stable relay is live; QuickQ is currently disconnected"
    fi
  elif printf '%s\n' "$live_ports" | grep -qx "$port"; then
    if (( port >= 10900 && port <= 10999 )); then
      warn "  pid $pid ($(basename "$comm")): direct QuickQ port $port works now but will stale on reconnect"
      warn "      -> restart this process once after installing the stable relay"
    else
      ok "  pid $pid ($(basename "$comm")): proxy 127.0.0.1:$port is live"
    fi
  else
    bad "  pid $pid ($(basename "$comm")): proxy 127.0.0.1:$port has NO listener (rotated away)"
    bad "      -> its API calls hang or refuse; the app looks frozen. Restart it from a fresh shell."
  fi
done < <(ps -axww -o pid=,comm= | awk '$2 ~ /(^|\/)(claude|codex)$/ {print $1, $2}')
(( found_agent )) || dim "  (no claude/codex processes running)"

hdr "Cloud-storage placeholder hazard (running claude cwds)"
cloud_hits=0
while read -r pid; do
  [[ -n "$pid" ]] || continue
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  case "$cwd" in
    "$HOME/Library/CloudStorage/"*|"$HOME/Library/Mobile Documents/"*)
      cloud_hits=1
      if [[ -d "$cwd/.claude" ]]; then
        flagged="$(find "$cwd/.claude" -type f -exec ls -lO {} + 2>/dev/null | grep dataless || true)"
      else
        flagged=''
      fi
      if [[ -n "$flagged" ]]; then
        bad "  pid $pid: cwd is cloud-synced AND .claude/ holds dataless placeholders:"
        printf '%s\n' "$flagged" | sed 's/^/      /'
        bad "      A synchronous read of a dataless file can block claude's main thread in-kernel"
        bad "      (observed live 2026-07-10). Restart the sync app (e.g. Google Drive), keep the"
        bad "      project's .claude 'Available offline', or move the project off the mount."
      else
        dim "  pid $pid: cwd on cloud-backed storage ($cwd); .claude files currently materialized"
      fi ;;
  esac
done < <(ps -axww -o pid=,comm= | awk '$2 ~ /(^|\/)claude$/ {print $1}')
(( cloud_hits )) || dim "  (no running claude in CloudStorage or iCloud Documents)"
