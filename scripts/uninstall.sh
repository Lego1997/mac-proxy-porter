#!/usr/bin/env bash
# Remove the mac-proxy-sync marker-bounded blocks from ~/.zshenv and ~/.zshrc.
# Run launchctl unsetenv for each proxy var.
# Print the shell commands the user must run to clean the CURRENT shell
# (a subshell can't unset the parent's env).
set -euo pipefail

BEGIN_MARK='# >>> mac-proxy-sync BEGIN >>>'
END_MARK='# <<< mac-proxy-sync END <<<'
RELAY_LABEL='com.pan.codex.quickq-stable-relay'
RELAY_PLIST="$HOME/Library/LaunchAgents/$RELAY_LABEL.plist"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }

remove_block() {
  local target=$1
  [[ -f "$target" ]] || { warn "  $target does not exist; skipping."; return 0; }

  if ! grep -qF "$BEGIN_MARK" "$target"; then
    warn "  no marker block in $target; skipping."
    return 0
  fi

  bold "Removing marker block from $target"
  local tmp
  tmp="$(mktemp)"
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, b) { skip = 1; next }
    skip && index($0, e) { skip = 0; next }
    !skip { print }
  ' "$target" > "$tmp"

  # Trim only trailing blank lines introduced by the splice; preserve the rest
  # of the user's dotfile formatting exactly.
  awk '
    /^[[:space:]]*$/ { blanks = blanks $0 ORS; next }
    { printf "%s", blanks; blanks = ""; print }
  ' "$tmp" > "$tmp.2" || cp "$tmp" "$tmp.2"
  mv "$tmp.2" "$target"
  rm -f "$tmp"
  ok "  + removed"
}

bold "== mac-proxy-sync uninstall =="
remove_block "$HOME/.zshenv"
remove_block "$HOME/.zshrc"

echo
bold "Stopping stable QuickQ relay"
launchctl bootout "gui/$(id -u)/$RELAY_LABEL" >/dev/null 2>&1 || true
rm -f "$RELAY_PLIST" \
      "$HOME/.codex/quickq-stable-relay.js" \
      "$HOME/.codex/quickq-stable-relay.out.log" \
      "$HOME/.codex/quickq-stable-relay.err.log"
ok "  + removed"

echo
bold "Running launchctl unsetenv for GUI-propagated vars"
for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
         grpc_proxy GRPC_PROXY no_proxy NO_PROXY \
         no_grpc_proxy NO_GRPC_PROXY ALL_PROXY all_proxy; do
  launchctl unsetenv "$v" 2>/dev/null || true
done
ok "  + cleared"

echo
bold "== Clean up the current shell =="
cat <<'EOF'
The marker blocks are removed from your dotfiles and launchctl env is cleared,
but the PARENT shell (the one that ran this uninstall) still has the proxy vars
exported. Paste this into your current shell to finish the cleanup:

  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY \
        grpc_proxy GRPC_PROXY no_proxy NO_PROXY \
        no_grpc_proxy NO_GRPC_PROXY ALL_PROXY all_proxy
  # either open a new Terminal tab, or replace the current zsh:
  exec zsh

All new Terminal tabs from this point forward will have no proxy env.
EOF
ok "done."
