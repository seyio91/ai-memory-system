#!/usr/bin/env bash
# install.sh — wire this memory tree into Claude Code on a fresh machine.
#
# What it does (idempotent, backs up anything it would overwrite):
#   1. Links the repo to $MEMORY_DIR (default ~/.claude-memory) so the hook
#      defaults resolve.
#   2. Symlinks the hook scripts into ~/.claude/hooks/.
#   3. Symlinks the slash commands into ~/.claude/commands/.
#   4. Links the bundled skills and agents into ~/.claude/ via the repo scripts.
#   5. Seeds identity.md / index.md from their templates if missing.
#   6. Prints the manual steps it will not do for you (settings.json merge,
#      CLAUDE.md placement).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
MEMORY_DIR="${MEMORY_DIR:-$HOME/.claude-memory}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
TS="$(date +%Y%m%d-%H%M%S)"

info() { printf '  %s\n' "$1"; }
step() { printf '\n==> %s\n' "$1"; }

# link <src> <dst> — symlink src->dst, skipping if already correct, backing up otherwise.
link() {
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        info "ok (already linked): $dst"; return 0
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mv "$dst" "$dst.bak-$TS"
        info "backed up existing -> $dst.bak-$TS"
    fi
    ln -s "$src" "$dst"
    info "linked: $dst -> $src"
}

step "Memory tree -> $MEMORY_DIR"
if [ "$REPO_ROOT" = "$MEMORY_DIR" ]; then
    info "repo is already at the default location"
elif [ -e "$MEMORY_DIR" ] && [ ! -L "$MEMORY_DIR" ]; then
    info "WARNING: $MEMORY_DIR exists and is not a symlink — leaving it alone."
    info "Set MEMORY_DIR to this repo's path in your shell env instead, or remove it and re-run."
else
    link "$REPO_ROOT" "$MEMORY_DIR"
fi

step "Hooks -> $CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/hooks"
for h in "$REPO_ROOT"/claude/hooks/*.sh; do
    chmod +x "$h"
    link "$h" "$CLAUDE_DIR/hooks/$(basename "$h")"
done

step "Slash commands -> $CLAUDE_DIR/commands"
mkdir -p "$CLAUDE_DIR/commands"
for c in "$REPO_ROOT"/claude/commands/*.md; do
    link "$c" "$CLAUDE_DIR/commands/$(basename "$c")"
done

step "Skills & agents"
if [ -d "$REPO_ROOT/skills" ]; then bash "$REPO_ROOT/scripts/link-skills.sh" || info "link-skills.sh skipped/failed"; fi
if [ -d "$REPO_ROOT/agents" ]; then bash "$REPO_ROOT/scripts/link-agents.sh" || info "link-agents.sh skipped/failed"; fi

step "Seed personal files from templates (only if missing)"
[ -f "$REPO_ROOT/identity.md" ] || { cp "$REPO_ROOT/identity.template.md" "$REPO_ROOT/identity.md"; info "created identity.md from template"; }
[ -f "$REPO_ROOT/index.md" ]    || { cp "$REPO_ROOT/index.template.md" "$REPO_ROOT/index.md";    info "created index.md from template"; }
mkdir -p "$REPO_ROOT/tasks" "$REPO_ROOT/archive/tasks"

cat <<EOF

==> Done. Two manual steps remain:

  1. Hooks must be registered in $CLAUDE_DIR/settings.json. Merge the three
     entries from claude/settings.hooks.json into your settings file.

  2. Workflow rules: review claude/CLAUDE.md, then either symlink or merge it:
       ln -s "$REPO_ROOT/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"   # if you have none
     (If you already have a ~/.claude/CLAUDE.md, merge by hand.)

  Then: edit identity.md, onboard a repo with '/pin <project>', and start a session.
EOF
