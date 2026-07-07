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

# detect_harness — pick a harness whose manifest exists AND whose runtime dir is
# present. Claude first, preserving the historical no-arg behavior.
detect_harness() {
    local h
    for h in claude codex antigravity gemini cursor; do
        [ -f "$REPO_ROOT/harnesses/$h/manifest" ] || continue
        case "$h" in
            claude)      [ -d "$HOME/.claude" ] && { printf claude; return 0; } ;;
            codex)       [ -d "$HOME/.codex" ]  && { printf codex; return 0; } ;;
            antigravity) { command -v agy >/dev/null 2>&1 || [ -d "$HOME/.gemini/antigravity-cli" ]; } \
                             && { printf antigravity; return 0; } ;;
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
driver_install

# ---- skills + agents fan-out (any harness that declares a target) ---------
# Phase 4 lifts the Phase-3 archetype gate: skills fan out into whatever
# skills_dir the manifest names (Claude ~/.claude/skills, Codex ~/.agents/skills).
SKILLS_DIR="$(manifest_get "$MANIFEST" skills_dir)"
AGENTS_DIR="$(manifest_get "$MANIFEST" agents_dir)"
# Resolve declared remote skills into the gitignored cache BEFORE linking, so any
# remote skill fans out with the authored ones. A plain resolve is a cache hit for
# anything already pinned (offline-safe); only new/changed remotes fetch. Non-fatal:
# an unreachable remote must not brick a full reinstall — it is reported, and the
# rest (authored + cached) still link. Re-fetch stale refs with resolve-skills.sh --update.
if [ -f "$REPO_ROOT/skills/skills.toml" ] || [ -f "$REPO_ROOT/skills-local/skills.toml" ]; then
    step "Resolve remote skills (manifest -> .skill-cache/)"
    bash "$REPO_ROOT/scripts/resolve-skills.sh" || info "resolve-skills.sh reported failures (see above) — linking cached + authored only"
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
# Canonical command bodies are authored under the Claude harness dir and shared
# across harnesses: symlinked natively (Claude), wrapped AS skills into skills_dir
# (Codex — its command mechanism IS skills), or rendered as a reference doc
# (fallback for a harness with neither surface).
COMMANDS_STORE="$REPO_ROOT/harnesses/claude/commands"
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
[ -f "$REPO_ROOT/index.md" ]    || { cp "$REPO_ROOT/index.template.md" "$REPO_ROOT/index.md";    info "created index.md from template"; }
mkdir -p "$REPO_ROOT/tasks" "$REPO_ROOT/archive/tasks"

# ---- manual steps (harness-specific) --------------------------------------
printf '\n==> Done (%s). Manual steps that remain:\n\n' "$HARNESS"
driver_notes
cat <<EOF

  Then: edit identity.md, onboard a repo with '/pin <project>', and start a session.
EOF
