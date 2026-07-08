#!/usr/bin/env bash
#
# sync-system.sh — sync the memory-system checkout to its configured channel and
# (re)install every feature it ships: hooks, slash commands, skills, agents,
# statusline.
#
# It is the "apply what was synced" button. Git updates the files in the repo,
# but new commands/skills/agents only become visible to the harness once they are
# symlinked into ~/.claude/. This script does both: syncs the checkout, then
# re-runs the idempotent install.sh which relinks everything.
#
# Manual equivalent:
#   release channel:
#     git status --porcelain --untracked-files=no
#     git fetch --tags origin
#     git checkout "$(git tag -l 'v*' | sort -V | tail -1)"
#     bash install.sh
#   dev channel:
#     git status --porcelain --untracked-files=no
#     git fetch --tags origin
#     git merge --ff-only @{u}
#     bash install.sh
#   one-shot ref:
#     git status --porcelain --untracked-files=no
#     git fetch --tags origin
#     git checkout <ref>
#     bash install.sh
#
# Usage:
#   sync-system.sh                 # channel default: release -> latest v* tag
#                                  #                  dev -> ff-only upstream merge
#   sync-system.sh --to <ref>      # one-shot checkout of tag, branch, or sha
#   sync-system.sh --no-pull       # skip the pull; just re-link from current tree
#   sync-system.sh --dry-run       # show target channel/ref; do not sync/install
#   sync-system.sh --update        # also re-resolve remote skills (re-fetch pinned refs)
#
# Safe by design:
#   - Dirty tracked files abort before checkout/merge. Untracked files are
#     ignored because the tree commonly holds gitignored personal data.
#   - dev-channel merge is --ff-only: it refuses to merge/rebase over local
#     divergence and never rewrites history.
#   - release-channel checkout leaves consumers detached at a tested tag.
#   - install.sh is idempotent and backs up anything it would overwrite.
#   - Never touches running infrastructure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/_lib.sh"

DO_PULL=1
DRY_RUN=0
UPDATE_REMOTES=0
SYNC_TO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --no-pull) DO_PULL=0 ;;
    --dry-run) DRY_RUN=1 ;;
    --update)  UPDATE_REMOTES=1 ;;
    --to)
      shift
      [ $# -gt 0 ] || { echo "missing ref after --to" >&2; exit 2; }
      SYNC_TO="$1"
      ;;
    --to=*) SYNC_TO="${1#--to=}" ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) echo "unexpected argument: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "$REPO_ROOT"

step() { printf '\n==> %s\n' "$1"; }
info() { printf '  %s\n' "$1"; }

dirty_tracked_guard() {
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "  ABORT: tracked files have local modifications or staged changes." >&2
    echo "  Commit/stash/revert tracked changes, then re-run sync-system.sh." >&2
    echo "  Untracked files do not block sync." >&2
    git status --short --untracked-files=no >&2
    exit 1
  fi
}

latest_release_tag() {
  local tag
  tag="$(git tag -l 'v*' | sort -V | tail -1)"
  if [ -z "$tag" ]; then
    echo "  ABORT: no release tag yet — cut one with release.sh, or set AI_MEMORY_CHANNEL=dev." >&2
    exit 1
  fi
  printf '%s\n' "$tag"
}

run_migrations_placeholder() {
  # Phase 2: run pending migrations here before install.sh.
  :
}

resolve_channel() {
  local channel="${AI_MEMORY_CHANNEL:-release}"
  [ -n "$channel" ] || channel="release"
  case "$channel" in
    release|dev) printf '%s\n' "$channel" ;;
    *)
      echo "  ABORT: invalid AI_MEMORY_CHANNEL='$channel' (valid: release, dev)." >&2
      exit 2
      ;;
  esac
}

if [ "$DO_PULL" = 1 ]; then
  CHANNEL="$(resolve_channel)"
  MODE="$CHANNEL"
  TARGET=""
  if [ -n "$SYNC_TO" ]; then
    MODE="ref"
    TARGET="$SYNC_TO"
  fi

  if [ "$DRY_RUN" = 1 ]; then
    step "[dry-run] sync target"
    info "channel: $CHANNEL"
    if [ "$MODE" = "ref" ]; then
      info "target: $TARGET (--to override)"
    elif [ "$MODE" = "release" ]; then
      TARGET="$(latest_release_tag)"
      info "target: $TARGET (latest release tag)"
    else
      info "target: @{u} (dev ff-only merge)"
    fi
    info "[dry-run] not fetching, not checking out, not installing"
    exit 0
  fi

  dirty_tracked_guard

  step "Fetching origin"
  git fetch --quiet --tags origin

  if [ "$MODE" = "release" ]; then
    TARGET="$(latest_release_tag)"
    step "Checking out release $TARGET"
    git checkout --quiet "$TARGET"
  elif [ "$MODE" = "ref" ]; then
    step "Checking out $TARGET (--to)"
    git checkout --quiet "$TARGET"
  else
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    local_sha="$(git rev-parse @)"
    remote_sha="$(git rev-parse "@{u}" 2>/dev/null || echo "")"

    if [ -z "$remote_sha" ]; then
      info "no upstream configured for $BRANCH — skipping pull"
    elif [ "$local_sha" = "$remote_sha" ]; then
      info "already up to date with origin/$BRANCH ($local_sha)"
    else
      info "incoming changes on $BRANCH:"
      git --no-pager log --oneline "${local_sha}..${remote_sha}" | sed 's/^/    /'
      echo
      git --no-pager diff --stat "${local_sha}..${remote_sha}" | sed 's/^/    /'

      step "Fast-forward pull"
      if ! git merge --ff-only "@{u}"; then
        echo "  ABORT: local branch has diverged from origin/$BRANCH (local commits or non-ff)." >&2
        echo "  Resolve by hand (git status / git rebase), then re-run." >&2
        exit 1
      fi
    fi
  fi
else
  if [ "$DRY_RUN" = 1 ]; then
    step "[dry-run] sync target"
    info "--no-pull: current tree (no fetch, no checkout, no install)"
    exit 0
  fi
  info "--no-pull: re-linking from current tree (no fetch)"
fi

run_migrations_placeholder

if [ "$UPDATE_REMOTES" = 1 ]; then
  step "Re-resolving remote skills (--update: re-fetch pinned refs)"
  bash "$REPO_ROOT/scripts/resolve-skills.sh" --update \
    || { echo "  ABORT: a remote skill failed to re-resolve (see above)." >&2; exit 1; }
fi

step "Re-installing features (install.sh)"
bash "$REPO_ROOT/install.sh"

step "Sync complete"
info "Slash commands are loaded at session start — restart/reconnect to pick up new ones."
