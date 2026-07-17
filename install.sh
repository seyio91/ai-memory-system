#!/usr/bin/env bash
# install.sh — wire this memory tree into a coding harness, driven by that
# harness's declarative manifest (harnesses/<name>/manifest).
#
#   install.sh                     # auto-detect the harness (prefers ~/.claude)
#   install.sh --harness <name>    # wire a specific harness (claude, codex, …)
#   install.sh --list              # list registered harnesses and exit
#
# Generic engine: resolve harness -> read manifest -> run the archetype driver
# (hook | file) -> deliver commands + skills + agents per the manifest -> run an
# optional per-harness override -> stamp config + seed personal files. Idempotent;
# backs up anything it would overwrite. Never touches running infrastructure.
set -euo pipefail

# Physical path (resolves symlinks) so MEMORY_DIR is the real tree, not the
# ~/.claude-memory symlink — deterministic whether run from the clone or via that
# symlink by sync-system.sh.
REPO_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
MEMORY_DIR="${MEMORY_DIR:-$HOME/.claude-memory}"
TS="$(date +%Y%m%d-%H%M%S)"

. "$REPO_ROOT/scripts/manifest.sh"
. "$REPO_ROOT/scripts/_lib.sh"

info() { printf '  %s\n' "$1"; }
step() { printf '\n==> %s\n' "$1"; }

# link <src> <dst> — symlink src->dst, skip if already correct, back up otherwise.
link() {
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        info "ok (already linked): $dst"; return 0
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mv "$dst" "$dst.bak-$TS"; info "backed up existing -> $dst.bak-$TS"
    fi
    ln -s "$src" "$dst"; info "linked: $dst -> $src"
}

list_harnesses() {
    local mf name arch
    for mf in "$REPO_ROOT"/harnesses/*/manifest; do
        [ -f "$mf" ] || continue
        name="$(basename "$(dirname "$mf")")"
        arch="$(manifest_get "$mf" archetype)"
        printf '  %-10s (%s)\n' "$name" "$arch"
    done
}

codex_hooks_version() {
    command -v codex >/dev/null 2>&1 || return 1
    codex --version 2>/dev/null | awk '{print $NF; exit}'
}

# detect_harness — pick a harness whose manifest exists AND whose runtime dir is
# present. Claude first, preserving the historical no-arg behavior.
detect_harness() {
    local h
    for h in claude codex antigravity copilot gemini cursor; do
        [ -f "$REPO_ROOT/harnesses/$h/manifest" ] || continue
        case "$h" in
            claude)      [ -d "$HOME/.claude" ] && { printf claude; return 0; } ;;
            codex)       [ -d "$HOME/.codex" ]  && { printf codex; return 0; } ;;
            antigravity) { command -v agy >/dev/null 2>&1 || [ -d "$HOME/.gemini/antigravity-cli" ]; } \
                             && { printf antigravity; return 0; } ;;
            copilot)     command -v copilot >/dev/null 2>&1 && { printf copilot; return 0; } ;;
            gemini)      [ -d "$HOME/.gemini" ] && { printf gemini; return 0; } ;;
            cursor)      [ -d "$HOME/.cursor" ] && { printf cursor; return 0; } ;;
        esac
    done
    return 1
}

# ---- resolve the harness --------------------------------------------------
HARNESS=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --harness) HARNESS="${2:-}"; shift 2 ;;
        --harness=*) HARNESS="${1#*=}"; shift ;;
        --list) list_harnesses; exit 0 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$HARNESS" ]; then
    HARNESS="$(detect_harness)" || {
        echo "install: could not auto-detect a harness (no known runtime dir found)." >&2
        echo "  Pick one explicitly: install.sh --harness <name>" >&2
        echo "  Registered harnesses:" >&2; list_harnesses >&2
        exit 1
    }
fi

HARNESS_DIR="$REPO_ROOT/harnesses/$HARNESS"
MANIFEST="$HARNESS_DIR/manifest"
if [ ! -f "$MANIFEST" ]; then
    echo "install: no manifest for harness '$HARNESS' ($MANIFEST)" >&2
    echo "  Registered harnesses:" >&2; list_harnesses >&2
    exit 1
fi

# Fail fast on a malformed manifest.
if ! bash "$REPO_ROOT/scripts/validate-manifest.sh" "$MANIFEST" >/tmp/vm.$$ 2>&1; then
    echo "install: manifest for '$HARNESS' failed validation:" >&2
    sed 's/^/  /' /tmp/vm.$$ >&2; rm -f /tmp/vm.$$
    exit 1
fi
rm -f /tmp/vm.$$

ARCHETYPE="$(manifest_get "$MANIFEST" archetype)"
printf '== installing memory system for harness: %s (archetype: %s) ==\n' "$HARNESS" "$ARCHETYPE"
PROBE="$(manifest_get "$MANIFEST" probe)"
SKIP_DRIVER=0
if [ -n "$PROBE" ] && ! command -v "$PROBE" >/dev/null 2>&1; then
    info "$PROBE not found on PATH — skipping $HARNESS hook registration"
    SKIP_DRIVER=1
fi

# ---- shared: stable memory-tree path --------------------------------------
step "Memory tree -> $MEMORY_DIR"
if [ "$REPO_ROOT" = "$MEMORY_DIR" ]; then
    info "repo is already at the default location"
elif [ -e "$MEMORY_DIR" ] && [ ! -L "$MEMORY_DIR" ]; then
    info "WARNING: $MEMORY_DIR exists and is not a symlink — leaving it alone."
    info "Set MEMORY_DIR to this repo's path in your shell env instead, or remove it and re-run."
else
    link "$REPO_ROOT" "$MEMORY_DIR"
fi

# ---- archetype driver (hooks/statusline for hook; context prep for file) --
. "$REPO_ROOT/scripts/drivers/$ARCHETYPE.sh"
if [ "$SKIP_DRIVER" -eq 0 ]; then
    driver_install
fi

# Codex hybrid: its manifest remains file-archetype (static AGENTS.md base) but
# declares native hooks_json for dynamic per-turn memory and the executor guard.
# Codex shares the Claude native hook schema, so this calls the native JSON writer
# even though Codex remains file-archetype for its AGENTS.md base.
HOOKS_JSON="$(manifest_get "$MANIFEST" hooks_json)"
if [ "$ARCHETYPE" = file ] && [ -n "$HOOKS_JSON" ]; then
    HOOKS_MIN_VERSION="$(manifest_get "$MANIFEST" hooks_min_version)"
    CODEX_HOOKS_VERSION="$(codex_hooks_version || true)"
    if [ -n "$HOOKS_MIN_VERSION" ] && [ -z "$CODEX_HOOKS_VERSION" ]; then
        info "codex not found — skipping native hook registration; $HARNESS stays file-archetype-only (AGENTS.md)"
    elif [ -n "$HOOKS_MIN_VERSION" ] && semver_gt "$HOOKS_MIN_VERSION" "$CODEX_HOOKS_VERSION"; then
        info "codex $CODEX_HOOKS_VERSION is below hooks_min_version $HOOKS_MIN_VERSION — skipping native hook registration; $HARNESS stays file-archetype-only (AGENTS.md)"
    else
        (
            . "$REPO_ROOT/scripts/drivers/hook.sh"
            _hook_register_codex_json "$HOOKS_JSON"
        )
    fi
fi

# ---- skills + agents fan-out (any harness that declares a target) ---------
# Phase 4 lifts the Phase-3 archetype gate: skills fan out into whatever
# skills_dir the manifest names (Claude ~/.claude/skills, Codex ~/.agents/skills).
SKILLS_DIR="$(manifest_get "$MANIFEST" skills_dir)"
AGENTS_DIR="$(manifest_get "$MANIFEST" agents_dir)"
if [ ! -f "$REPO_ROOT/skills.toml" ] && [ -f "$REPO_ROOT/skills.toml.example" ]; then
    step "Seed remote-skill manifest"
    cp "$REPO_ROOT/skills.toml.example" "$REPO_ROOT/skills.toml"
    info "seeded skills.toml from template — prune what you don't want, then run scripts/resolve-skills.sh"
fi
if [ -n "$SKILLS_DIR" ] && [ -d "$REPO_ROOT/skills" ]; then
    step "Skills -> $SKILLS_DIR"
    bash "$REPO_ROOT/scripts/link-skills.sh" "$SKILLS_DIR" || info "link-skills.sh skipped/failed"
else
    info "no skills_dir in manifest (or no skills/ store) — skills fan-out skipped"
fi
if [ -n "$AGENTS_DIR" ] && [ -d "$REPO_ROOT/agents" ]; then
    step "Agents -> $AGENTS_DIR"
    bash "$REPO_ROOT/scripts/link-agents.sh" "$AGENTS_DIR" || info "link-agents.sh skipped/failed"
fi

# ---- commands surface ------------------------------------------------------
# Canonical command bodies live in the repo-level commands/ store (harness-neutral,
# like skills/ and agents/) and are shared across harnesses: symlinked natively
# (Claude), wrapped AS skills into skills_dir
# (Codex — its command mechanism IS skills), or rendered as a reference doc
# (fallback for a harness with neither surface).
COMMANDS_STORE="$REPO_ROOT/commands"
CMDS="$(manifest_get "$MANIFEST" commands)"
CMDS_DIR="$(manifest_get "$MANIFEST" commands_dir)"
case "$CMDS" in
    native)
        step "Commands (native) -> $CMDS_DIR"
        bash "$REPO_ROOT/scripts/link-commands.sh" "$CMDS_DIR" || info "link-commands.sh skipped/failed"
        ;;
    skill)
        if [ -n "$SKILLS_DIR" ]; then
            step "Commands (as skills) -> $SKILLS_DIR"
            bash "$REPO_ROOT/scripts/link-command-skills.sh" "$COMMANDS_STORE" "$SKILLS_DIR" \
                || info "link-command-skills.sh skipped/failed"
        else
            info "commands=skill but no skills_dir — commands surface skipped (reported)"
        fi
        ;;
    doc)
        CMDS_DOC="$(manifest_get "$MANIFEST" commands_doc)"
        if [ -z "$CMDS_DOC" ]; then
            CTX="$(manifest_get "$MANIFEST" context_target)"
            [ -n "$CTX" ] && CMDS_DOC="$(dirname "$CTX")/MEMORY-COMMANDS.md"
        fi
        if [ -n "$CMDS_DOC" ]; then
            step "Commands (reference doc) -> $CMDS_DOC"
            bash "$REPO_ROOT/scripts/gen-commands-doc.sh" "$COMMANDS_STORE" "$CMDS_DOC" \
                || info "gen-commands-doc.sh skipped/failed"
        else
            info "commands=doc but no commands_doc/context_target to place it — skipped (reported)"
        fi
        ;;
    ""|none) : ;;
    *) info "unknown commands surface '$CMDS' — skipped (reported)" ;;
esac

# ---- optional per-harness override ----------------------------------------
OVERRIDE="$HARNESS_DIR/$HARNESS.sh"
if [ -f "$OVERRIDE" ]; then
    step "Per-harness override -> $OVERRIDE"
    bash "$OVERRIDE" --install || info "override $HARNESS.sh --install returned nonzero (continuing)"
fi

# ---- shared: record install location --------------------------------------
step "Recording install location -> config.local.sh"
CONFIG_LOCAL="$REPO_ROOT/config.local.sh"
if [ ! -f "$CONFIG_LOCAL" ]; then
    printf '#!/usr/bin/env bash\n# Per-environment overrides (gitignored). See config.local.sh.example.\n' > "$CONFIG_LOCAL"
    info "created config.local.sh"
fi
TMP_CL="$(mktemp)"
grep -v '^export MEMORY_DIR=' "$CONFIG_LOCAL" > "$TMP_CL" && grep_st=0 || grep_st=$?
if [ "$grep_st" -gt 1 ]; then
    rm -f "$TMP_CL"
    echo "install: cannot read $CONFIG_LOCAL (grep exit $grep_st) — not stamping" >&2
    exit 1
fi
printf 'export MEMORY_DIR=%q\n' "$REPO_ROOT" >> "$TMP_CL"
mv "$TMP_CL" "$CONFIG_LOCAL"
info "set MEMORY_DIR=$REPO_ROOT"

# ---- shared: seed personal files from templates ---------------------------
step "Seed personal files from templates (only if missing)"
[ -f "$REPO_ROOT/identity.md" ] || { cp "$REPO_ROOT/identity.template.md" "$REPO_ROOT/identity.md"; info "created identity.md from template"; }
[ -f "$REPO_ROOT/orchestrator.md" ] || { cp "$REPO_ROOT/orchestrator.template.md" "$REPO_ROOT/orchestrator.md"; info "created orchestrator.md from template"; }
[ -f "$REPO_ROOT/index.md" ]    || { cp "$REPO_ROOT/index.template.md" "$REPO_ROOT/index.md";    info "created index.md from template"; }
mkdir -p "$REPO_ROOT/tasks" "$REPO_ROOT/archive/tasks"

# ---- manual steps (harness-specific) --------------------------------------
printf '\n==> Done (%s). Manual steps that remain:\n\n' "$HARNESS"
if [ "$SKIP_DRIVER" -eq 0 ]; then
    driver_notes
else
    cat <<EOF
  1. Install for '$HARNESS' skipped hook registration because '$PROBE' is not on PATH.
     Install the runtime, then re-run: install.sh --harness $HARNESS
EOF
fi
cat <<EOF

  Then: edit identity.md and orchestrator.md (per-instance, git-ignored),
  onboard a repo with '/pin <project>', and start a session.
EOF
