#!/usr/bin/env bash
# Install (or update) the mac-proxy-sync marker-bounded blocks in ~/.zshenv and ~/.zshrc.
# Idempotent. Re-running when block already matches is a no-op.
# Run with --update to replace the marker region even if it differs from canonical.
set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCK_ENV="$SKILL_DIR/scripts/blocks/zshenv.zsh"
BLOCK_RC="$SKILL_DIR/scripts/blocks/zshrc.zsh"
RELAY_SRC="$SKILL_DIR/scripts/quickq-stable-relay.js"
RELAY_DST="$HOME/.codex/quickq-stable-relay.js"
RELAY_LABEL="com.pan.codex.quickq-stable-relay"
RELAY_PLIST="$HOME/Library/LaunchAgents/$RELAY_LABEL.plist"
RELAY_HTTP_PORT=17890
RELAY_SOCKS_PORT=17891

BEGIN_MARK='# >>> mac-proxy-sync BEGIN >>>'
END_MARK='# <<< mac-proxy-sync END <<<'

UPDATE=0
if [[ "${1:-}" == "--update" ]]; then UPDATE=1; fi

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

# Extract the marker-bounded region from a file (empty string if none).
extract_region() {
  local file=$1
  [[ -f "$file" ]] || { printf ''; return 0; }
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, b) { p = 1 }
    p            { print }
    index($0, e) { p = 0 }
  ' "$file"
}

# Replace the marker-bounded region in $1 with the contents of $2.
# If no region present, append. If present, splice.
install_block() {
  local target=$1 source=$2
  local current canonical
  current="$(extract_region "$target")"
  canonical="$(cat "$source")"

  if [[ -z "$current" ]]; then
    bold "Appending block to $target"
    # Ensure file ends with a newline before appending.
    if [[ -f "$target" && -n "$(tail -c1 "$target" 2>/dev/null)" ]]; then
      printf '\n' >> "$target"
    fi
    printf '\n' >> "$target"
    cat "$source" >> "$target"
    ok "  + installed"
    return 0
  fi

  if [[ "$current" == "$canonical" ]]; then
    ok "Block in $target already matches canonical; no-op."
    return 0
  fi

  if (( UPDATE )); then
    bold "Updating block in $target"
  else
    warn "Block in $target exists but differs from canonical."
    warn "Re-run with --update to replace, or run uninstall.sh first."
    diff -u <(printf '%s\n' "$current") <(printf '%s\n' "$canonical") || true
    return 2
  fi

  # Splice: delete old region, insert new.
  local tmp
  tmp="$(mktemp)"
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v src="$source" '
    BEGIN { skip = 0 }
    index($0, b) && !skip {
      skip = 1
      while ((getline line < src) > 0) print line
      next
    }
    skip && index($0, e) { skip = 0; next }
    !skip { print }
  ' "$target" > "$tmp"
  mv "$tmp" "$target"
  ok "  + updated"
}

install_relay() {
  local node_bin=''
  local quickq_node='/Applications/QuickQ For Mac.app/Contents/Resources/node_universal'
  if [[ -x "$quickq_node" ]]; then
    node_bin="$quickq_node"
  else
    node_bin="$(command -v node 2>/dev/null || true)"
  fi
  if [[ -z "$node_bin" ]]; then
    warn "No Node.js runtime found; skipping the stable QuickQ relay."
    warn "Shells will still sync dynamically, but running agents must restart after a port rotation."
    return 0
  fi

  bold "Installing stable QuickQ relay"
  mkdir -p "$HOME/.codex" "$HOME/Library/LaunchAgents"
  install -m 0755 "$RELAY_SRC" "$RELAY_DST"

  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$RELAY_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$node_bin</string>
    <string>$RELAY_DST</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$HOME/.codex/quickq-stable-relay.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/.codex/quickq-stable-relay.err.log</string>
</dict>
</plist>
EOF
  /usr/bin/plutil -lint "$tmp" >/dev/null
  mv "$tmp" "$RELAY_PLIST"
  chmod 0644 "$RELAY_PLIST"

  local domain="gui/$(id -u)" port holder
  /bin/launchctl bootout "$domain/$RELAY_LABEL" >/dev/null 2>&1 || true
  /bin/sleep 0.2
  for port in "$RELAY_HTTP_PORT" "$RELAY_SOCKS_PORT"; do
    holder="$(/usr/sbin/lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "$holder" ]]; then
      err "Port $port is already used by pid $holder; cannot start the stable relay."
      return 2
    fi
  done

  /bin/launchctl bootstrap "$domain" "$RELAY_PLIST"
  /bin/launchctl kickstart -k "$domain/$RELAY_LABEL"
  for _ in {1..30}; do
    if /usr/sbin/lsof -nP -iTCP:"$RELAY_HTTP_PORT" -sTCP:LISTEN >/dev/null 2>&1 \
       && /usr/sbin/lsof -nP -iTCP:"$RELAY_SOCKS_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      ok "  + relay live on 127.0.0.1:$RELAY_HTTP_PORT (HTTP) and :$RELAY_SOCKS_PORT (SOCKS)"
      return 0
    fi
    /bin/sleep 0.1
  done
  err "Stable relay did not start; inspect $HOME/.codex/quickq-stable-relay.err.log"
  return 2
}

bold "== mac-proxy-sync install =="
echo "skill dir: $SKILL_DIR"
echo "block sources:"
echo "  zshenv -> $BLOCK_ENV"
echo "  zshrc  -> $BLOCK_RC"
echo

# Create .zshenv if it doesn't exist.
if [[ ! -f "$HOME/.zshenv" ]]; then
  bold "Creating $HOME/.zshenv"
  : > "$HOME/.zshenv"
fi

install_block "$HOME/.zshenv" "$BLOCK_ENV"
install_block "$HOME/.zshrc"  "$BLOCK_RC"
install_relay

echo
bold "== Post-install =="
echo "To activate in the CURRENT shell:"
echo "  source ~/.zshenv && source ~/.zshrc && syncproxy"
echo
echo "New Terminal tabs will pick this up automatically."
echo
echo "Run 'bash $SKILL_DIR/scripts/status.sh' anytime to diagnose."
ok "done."
