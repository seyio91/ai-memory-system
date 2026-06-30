#!/usr/bin/env bash
#
# sync-system.sh — pull the latest memory-system from the remote and (re)install
# every feature it ships: hooks, slash commands, skills, agents, statusline.
#
# It is the "apply what was pulled" button. A plain `git pull` updates the files
# in the repo, but new commands/skills/agents only become visible to the harness
# once they are symlinked into ~/.claude/. This script does both: fast-forward
# the checkout, then re-run the idempotent install.sh which relinks everything.
#
# Usage:
#   sync-system.sh                 # fetch + ff-only pull, then re-install
#   sync-system.sh --no-pull       # skip the pull; just re-link from current tree
#   sync-system.sh --dry-run       # show what a pull would bring; do not install
#
# Safe by design:
#   - Pull is --ff-only: it refuses to merge/rebase over local divergence and
#     never rewrites history. Local commits or a dirty tree abort the pull with
#     a clear message instead of guessing.
#   - install.sh is idempotent and backs up anything it would overwrite.
#   - Never touches running infrastructure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DO_PULL=1
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --no-pull) DO_PULL=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) echo "unexpected argument: $arg" >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

step() { printf '\n==> %s\n' "$1"; }
info() { printf '  %s\n' "$1"; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [ "$DO_PULL" = 1 ]; then
  step "Fetching origin"
  git fetch --quiet origin

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

    if [ "$DRY_RUN" = 1 ]; then
      info "[dry-run] not pulling, not installing"
      exit 0
    fi

    step "Fast-forward pull"
    if ! git merge --ff-only "@{u}"; then
      echo "  ABORT: local branch has diverged from origin/$BRANCH (local commits or non-ff)." >&2
      echo "  Resolve by hand (git status / git rebase), then re-run." >&2
      exit 1
    fi
  fi
else
  info "--no-pull: re-linking from current tree (no fetch)"
fi

if [ "$DRY_RUN" = 1 ]; then
  step "[dry-run] would run install.sh to relink features — stopping here"
  exit 0
fi

step "Re-installing features (install.sh)"
bash "$REPO_ROOT/install.sh"

step "Sync complete"
info "Slash commands are loaded at session start — restart/reconnect to pick up new ones."
