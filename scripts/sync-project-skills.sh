#!/usr/bin/env bash
#
# sync-project-skills.sh — fan project-scoped skills from the memory system into
# their target repo's per-harness skill directory. The counterpart to
# link-skills.sh (which links GLOBAL skills into a harness user dir): this links
# a skill that is scoped to ONE project into that project's repo, so it only
# loads when an agent runs inside that repo.
#
# Source of truth (per-project, path == scope):
#   <memory>/projects/<project>/skills/<skill>/SKILL.md
#
# Each project's repo is resolved from its memory.md `repo_path:` via the shared
# resolve_repo_path (in _lib.sh): repo_path is relative to AI_MEMORY_PROJECTS_ROOT,
# or the `$MEMORY_DIR` sentinel for the self-referential meta-project, with the
# git remote as a fallback. Skills are fanned per harness; both Claude Code and
# Codex consume the SAME SKILL.md, so no translation is needed:
#   Claude Code -> <repo>/.claude/skills/<skill>
#   Codex       -> <repo>/.agents/skills/<skill>
#
# Usage:
#   sync-project-skills.sh [--harness claude|codex|all] [--mode link|copy]
#                          [--force] [--dry-run] [--list] [<project>...]
#
#   --harness   which harness target(s) to write (default: all)
#   --mode      link  = symlink into the repo (personal; gitignore it)        [default]
#               copy  = copy into the repo (shareable; commit it; Codex repo
#                       skills are designed to be checked in)
#   --force     in copy mode, refresh an existing target (rm -r + re-copy)
#   --dry-run   show what would change, do nothing
#   --list      list project skills and their resolved targets, then exit
#   <project>   restrict to the named project(s); default = all projects
#
# link mode is idempotent: repairs stale links, leaves real files / foreign
# symlinks untouched. Skips skill dirs without a SKILL.md (so *-workspace dirs
# are ignored). Never edits a repo's .gitignore — it prints a reminder instead.

set -euo pipefail

# Tree resolution is delegated to _lib.sh, which resolves MEMORY_DIR exactly as
# every other script does (${MEMORY_DIR:-self-locate}) and then sources
# config.local.sh from it. This script used to reimplement that under its own
# name, MEMORY_ROOT, and assign MEMORY_DIR="$MEM" BEFORE sourcing _lib.sh -- so
# a user-set MEMORY_DIR was silently discarded and the self-located tree synced
# instead. Aimed at a sandbox tree, it wrote symlinks into the real repos.
#
# MEMORY_ROOT is deprecated. It is still honoured, and loudly, so that setting
# it never quietly selects a different tree than it used to -- that would be the
# same silent wrong-tree failure this fix removes. Drop the shim at the next
# major; docs/scripts.md marks the row deprecated.
if [ -n "${MEMORY_ROOT:-}" ]; then
    echo "WARN: MEMORY_ROOT is deprecated — use MEMORY_DIR (honouring MEMORY_ROOT for now)" >&2
    MEMORY_DIR="$MEMORY_ROOT"
fi

# Shared helpers: projects_root, resolve_repo_path, extract_fm_field.
. "$(dirname "$0")/_lib.sh"

MEM="$MEMORY_DIR"
PROJECTS_DIR="$MEM/projects"

HARNESS="all"
MODE="link"
DRY_RUN=0
DO_LIST=0
FORCE=0
FILTER=()

while [ $# -gt 0 ]; do
  case "$1" in
    --harness) HARNESS="${2:?--harness needs a value}"; shift 2 ;;
    --harness=*) HARNESS="${1#*=}"; shift ;;
    --mode) MODE="${2:?--mode needs a value}"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --list) DO_LIST=1; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) FILTER+=("$1"); shift ;;
  esac
done

case "$HARNESS" in claude|codex|all) ;; *) echo "bad --harness: $HARNESS (claude|codex|all)" >&2; exit 2 ;; esac
case "$MODE" in link|copy) ;; *) echo "bad --mode: $MODE (link|copy)" >&2; exit 2 ;; esac
[ -d "$PROJECTS_DIR" ] || { echo "no projects dir at $PROJECTS_DIR" >&2; exit 1; }

harness_subdirs() {
  case "$HARNESS" in
    claude) printf '%s\n' ".claude/skills" ;;
    codex)  printf '%s\n' ".agents/skills" ;;
    all)    printf '%s\n' ".claude/skills" ".agents/skills" ;;
  esac
}

in_filter() {
  [ ${#FILTER[@]} -eq 0 ] && return 0
  local p="$1" f
  for f in "${FILTER[@]}"; do [ "$f" = "$p" ] && return 0; done
  return 1
}

linked=0 copied=0 repaired=0 refreshed=0 skipped=0 warned=0
gitignore_reminder=0

for skilldir in "$PROJECTS_DIR"/*/skills/*/; do
  [ -d "$skilldir" ] || continue
  rel="${skilldir#"$PROJECTS_DIR"/}"      # <project>/skills/<skill>/
  project="${rel%%/*}"
  skill="$(basename "$skilldir")"
  src="${skilldir%/}"

  in_filter "$project" || continue
  [ -f "$src/SKILL.md" ] || { echo "skip (no SKILL.md): $project/$skill"; continue; }

  # Shared resolver: returns the absolute checkout dir (repo_path relative to
  # projects_root, the $MEMORY_DIR sentinel, or an absolute path; git-remote
  # fallback) only when it exists on disk, else empty.
  rp="$(resolve_repo_path "$project" 2>/dev/null || true)"
  if [ -z "$rp" ]; then echo "WARN: $project — cannot resolve repo checkout (repo_path/repo missing or dir absent) — skipping $skill" >&2; warned=$((warned+1)); continue; fi

  while IFS= read -r sub; do
    target="$rp/$sub"
    dst="$target/$skill"

    if [ "$DO_LIST" = 1 ]; then
      echo "$project/$skill -> $dst"
      continue
    fi

    [ "$DRY_RUN" = 1 ] || mkdir -p "$target"

    if [ "$MODE" = "link" ]; then
      if [ -L "$dst" ]; then
        cur="$(readlink "$dst")"
        if [ "$cur" = "$src" ]; then skipped=$((skipped+1)); continue; fi
        echo "repair: $project/$skill ($sub)"
        [ "$DRY_RUN" = 1 ] || { rm "$dst"; ln -s "$src" "$dst"; }
        repaired=$((repaired+1))
      elif [ -e "$dst" ]; then
        echo "WARN: $dst exists and is not our symlink — leaving untouched" >&2
        warned=$((warned+1))
      else
        echo "link: $project/$skill -> $sub"
        [ "$DRY_RUN" = 1 ] || ln -s "$src" "$dst"
        linked=$((linked+1)); gitignore_reminder=1
      fi
    else  # copy
      if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ "$FORCE" = 1 ]; then
          echo "refresh: $project/$skill ($sub)"
          [ "$DRY_RUN" = 1 ] || { rm -r "$dst"; cp -R "$src" "$dst"; }
          refreshed=$((refreshed+1))
        else
          echo "exists (use --force to refresh): $project/$skill ($sub)"
          skipped=$((skipped+1))
        fi
      else
        echo "copy: $project/$skill -> $sub"
        [ "$DRY_RUN" = 1 ] || cp -R "$src" "$dst"
        copied=$((copied+1))
      fi
    fi
  done < <(harness_subdirs)
done

[ "$DO_LIST" = 1 ] && exit 0

tag=""; [ "$DRY_RUN" = 1 ] && tag=" [dry-run]"
echo "done: ${linked} linked, ${copied} copied, ${repaired} repaired, ${refreshed} refreshed, ${skipped} already-current/skipped, ${warned} warnings (harness: $HARNESS, mode: $MODE)${tag}"
if [ "$gitignore_reminder" = 1 ] && [ "$MODE" = "link" ]; then
  echo "reminder: linked skills point at the absolute store path (machine-local) — add the linked .claude/skills/<skill> and/or .agents/skills/<skill> entries to each repo's .gitignore, or use --mode copy for skills meant to be committed/shared."
fi
