#!/usr/bin/env bash
# Pure diagnostic: dump everything a human or agent needs to understand the
# current state of proxy sync on this machine. Read-only.
set -u

BEGIN_MARK='# >>> mac-proxy-sync BEGIN >>>'

hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }
bad() { printf '\033[31m%s\033[0m\n' "$*"; }
dim() { printf '\033[2m%s\033[0m\n' "$*"; }

hdr "scutil --proxy"
/usr/sbin/scutil --proxy 2>/dev/null || bad "  (scutil failed)"

hdr "Current shell env"
# We print even if running in bash; the parent zsh's env is passed through.
for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
         no_proxy NO_PROXY ALL_PROXY all_proxy; do
  printf '  %-14s = %s\n' "$v" "${!v:-<unset>}"
done

hdr "launchctl getenv (GUI-inherited)"
for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
         no_proxy NO_PROXY ALL_PROXY all_proxy; do
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
