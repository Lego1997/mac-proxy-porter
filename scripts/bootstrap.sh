#!/usr/bin/env bash
# One-shot setup on a fresh Mac (or after pulling a new version):
#   1. place this skill at ~/.codex/skills/mac-proxy-sync (Codex reads it there)
#   2. symlink it into ~/.claude/skills so Claude Code sees /mac-proxy-sync
#   3. run scripts/install.sh (pass --update to refresh existing blocks)
# Usage: bash scripts/bootstrap.sh [--update]
set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$HOME/.codex/skills/mac-proxy-sync"
CLAUDE_LINK="$HOME/.claude/skills/mac-proxy-sync"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }

if [[ "$SRC" != "$DST" ]]; then
  bold "Syncing skill files -> $DST"
  mkdir -p "$DST"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude .git "$SRC/" "$DST/"
  else
    cp -R "$SRC/." "$DST/"
  fi
  ok "  + synced"
fi

mkdir -p "$HOME/.claude/skills"
if [[ -L "$CLAUDE_LINK" || ! -e "$CLAUDE_LINK" ]]; then
  ln -sfn "$DST" "$CLAUDE_LINK"
  ok "Claude Code link: $CLAUDE_LINK -> $DST"
else
  warn "$CLAUDE_LINK exists and is not a symlink; leaving it alone."
fi

bash "$DST/scripts/install.sh" "$@"
