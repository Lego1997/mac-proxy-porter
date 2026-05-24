#!/usr/bin/env bash
# Install (or update) the mac-proxy-sync marker-bounded blocks in ~/.zshenv and ~/.zshrc.
# Idempotent. Re-running when block already matches is a no-op.
# Run with --update to replace the marker region even if it differs from canonical.
set -euo pipefail

SKILL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCK_ENV="$SKILL_DIR/scripts/blocks/zshenv.zsh"
BLOCK_RC="$SKILL_DIR/scripts/blocks/zshrc.zsh"

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

echo
bold "== Post-install =="
echo "To activate in the CURRENT shell:"
echo "  source ~/.zshenv && source ~/.zshrc && syncproxy"
echo
echo "New Terminal tabs will pick this up automatically."
echo
echo "Run 'bash $SKILL_DIR/scripts/status.sh' anytime to diagnose."
ok "done."
