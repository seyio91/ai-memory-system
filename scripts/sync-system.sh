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
#     git checkout "$(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
#     for f in migrations/<semver>-<slug>.sh newer than .applied-version; do
#       MEMORY_DIR="$PWD" REPO_ROOT="$PWD" bash "$f"
#       echo "<semver>" > .applied-version
#     done
#     bash install.sh
#   dev channel:
#     git status --porcelain --untracked-files=no
#     git fetch --tags origin
#     if [ "$(git rev-parse --abbrev-ref HEAD)" = "HEAD" ]; then
#       branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
#       [ -n "$branch" ] || git remote set-head origin --auto
#       branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
#       git checkout "${branch:-main}"
#     fi
#     git merge --ff-only @{u}
#     for f in migrations/<semver>-<slug>.sh newer than .applied-version; do
#       MEMORY_DIR="$PWD" REPO_ROOT="$PWD" bash "$f"
#       echo "<semver>" > .applied-version
#     done
#     bash install.sh
#   one-shot ref:
#     git status --porcelain --untracked-files=no
#     git fetch --tags origin
#     git checkout <ref>
#     for f in migrations/<semver>-<slug>.sh newer than .applied-version; do
#       MEMORY_DIR="$PWD" REPO_ROOT="$PWD" bash "$f"
#       echo "<semver>" > .applied-version
#     done
#     bash install.sh
#     # --to cannot be combined with --no-pull
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

if [ "$DO_PULL" = 0 ] && [ -n "$SYNC_TO" ]; then
  echo "  ABORT: --to cannot be combined with --no-pull." >&2
  echo "  Use --to <ref> to checkout a ref, or --no-pull to re-link the current tree." >&2
  exit 2
fi

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

stable_release_tags() {
  git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true
}

latest_release_tag() {
  local tag candidate
  tag=""
  if sort_v_supported; then
    tag="$(stable_release_tags | sort -V | tail -1)"
  else
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if [ -z "$tag" ] || semver_gt "$candidate" "$tag"; then
        tag="$candidate"
      fi
    done < <(stable_release_tags)
  fi
  if [ -z "$tag" ]; then
    if [ -n "$(git tag -l 'v*')" ]; then
      echo "  ABORT: v* tags exist, but none are stable release tags matching v<num>.<num>.<num>." >&2
      exit 1
    fi
    echo "  ABORT: no release tag yet — cut one with release.sh, or set AI_MEMORY_CHANNEL=dev." >&2
    exit 1
  fi
  printf '%s\n' "$tag"
}

dev_default_branch() {
  local branch ref count
  branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch#origin/}"
  if [ -n "$branch" ]; then
    printf '%s\n' "$branch"
    return 0
  fi
  git remote set-head origin --auto >/dev/null 2>&1 || true
  branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch#origin/}"
  if [ -n "$branch" ]; then
    printf '%s\n' "$branch"
    return 0
  fi
  count=0
  branch=""
  while IFS= read -r ref; do
    case "$ref" in
      refs/remotes/origin/HEAD) continue ;;
    esac
    count=$((count + 1))
    branch="${ref#refs/remotes/origin/}"
  done < <(git for-each-ref --format='%(refname)' refs/remotes/origin)
  if [ "$count" -eq 1 ] && [ -n "$branch" ]; then
    printf '%s\n' "$branch"
    return 0
  fi
  branch="main"
  printf '%s\n' "$branch"
}

checkout_dev_tracking_branch() {
  local branch
  branch="$(dev_default_branch)"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout --quiet "$branch"
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git checkout --quiet -b "$branch" --track "origin/$branch"
  else
    echo "  ABORT: cannot recover detached HEAD; origin/$branch does not exist." >&2
    exit 1
  fi
  if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    git branch --set-upstream-to="origin/$branch" "$branch" >/dev/null 2>&1 || true
  fi
}

preview_dev_incoming() {
  local branch local_sha remote_sha
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$branch" = "HEAD" ]; then
    branch="$(dev_default_branch)"
    info "target: $branch (dev tracking branch; detached HEAD would be recovered on real sync)"
    return 0
  fi

  local_sha="$(git rev-parse @)"
  remote_sha="$(git rev-parse "@{u}" 2>/dev/null || echo "")"
  if [ -z "$remote_sha" ]; then
    info "no upstream configured for $branch — skipping pull"
  elif [ "$local_sha" = "$remote_sha" ]; then
    info "already up to date with origin/$branch ($local_sha)"
  else
    info "incoming changes on $branch:"
    git --no-pager log --oneline "${local_sha}..${remote_sha}" | sed 's/^/    /'
    echo
    git --no-pager diff --stat "${local_sha}..${remote_sha}" | sed 's/^/    /'
  fi
}

migrations_dir() {
  printf '%s\n' "${AI_MEMORY_MIGRATIONS_DIR:-$REPO_ROOT/migrations}"
}

applied_version_file() {
  printf '%s\n' "${AI_MEMORY_APPLIED_VERSION_FILE:-$REPO_ROOT/.applied-version}"
}

read_applied_version() {
  local file version
  file="$(applied_version_file)"
  if [ ! -f "$file" ]; then
    # Missing marker means an existing pre-1.0 instance runs the full idempotent
    # history; migrations are required to be safe when repeated.
    printf '0.0.0\n'
    return 0
  fi
  IFS= read -r version < "$file" || version=""
  if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "  ABORT: applied-version marker must contain a bare semver: $file" >&2
    exit 1
  fi
  printf '%s\n' "$version"
}

validate_migration_files() {
  local dir f base version i
  local versions=()
  local bases=()
  dir="$(migrations_dir)"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
      README.md|.gitkeep) continue ;;
    esac
    if ! printf '%s\n' "$base" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[A-Za-z0-9._-]+\.sh$'; then
      echo "  ABORT: malformed migration filename: $base" >&2
      echo "  Expected migrations/<semver>-<slug>.sh, e.g. migrations/1.1.0-agents-marker.sh" >&2
      exit 1
    fi
    version="${base%%-*}"
    if [ "${#versions[@]}" -gt 0 ]; then
      i=0
      while [ "$i" -lt "${#versions[@]}" ]; do
        if [ "${versions[$i]}" = "$version" ]; then
          echo "  ABORT: duplicate migration version: $version" >&2
          echo "  One migration version may map to only one file." >&2
          echo "  Colliding files: ${bases[$i]} and $base" >&2
          exit 1
        fi
        i=$((i + 1))
      done
    fi
    versions[${#versions[@]}]="$version"
    bases[${#bases[@]}]="$base"
  done
}

list_migration_versions() {
  local dir f base
  dir="$(migrations_dir)"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
      README.md|.gitkeep) continue ;;
    esac
    printf '%s\n' "${base%%-*}"
  done
}

pending_migrations() {
  local dir marker versions version f base
  dir="$(migrations_dir)"
  marker="$1"
  [ -d "$dir" ] || return 0
  versions="$(list_migration_versions | semver_sort_asc | uniq)" || return 1
  [ -n "$versions" ] || return 0
  while IFS= read -r version; do
    [ -n "$version" ] || continue
    semver_gt "$version" "$marker" || continue
    for f in "$dir/$version"-*.sh; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      printf '%s\t%s\t%s\n' "$version" "$base" "$f"
    done
  done <<EOF
$versions
EOF
}

dry_run_migrations() {
  local marker pending_list count version base file
  validate_migration_files
  marker="$(read_applied_version)"
  pending_list="$(pending_migrations "$marker")" || { echo "  ABORT: could not compute pending migrations." >&2; exit 1; }
  step "[dry-run] pending migrations"
  info "applied marker: $marker"
  count=0
  if [ -n "$pending_list" ]; then
    while IFS="$(printf '\t')" read -r version base file; do
      [ -n "$version" ] || continue
      count=$((count + 1))
      info "$version  $base"
    done <<EOF
$pending_list
EOF
  fi
  if [ "$count" -eq 0 ]; then
    info "none"
  fi
}

write_applied_version() {
  local marker_file="$1" version="$2" marker_dir tmp rc
  marker_dir="$(dirname "$marker_file")"
  mkdir -p "$marker_dir"
  tmp="$marker_file.tmp.$$"
  printf '%s\n' "$version" > "$tmp" || {
    rc=$?
    rm -f "$tmp"
    exit "$rc"
  }
  mv "$tmp" "$marker_file" || {
    rc=$?
    rm -f "$tmp"
    exit "$rc"
  }
}

run_migrations() {
  local marker marker_file pending_list version base file count rc
  validate_migration_files
  marker="$(read_applied_version)"
  marker_file="$(applied_version_file)"
  pending_list="$(pending_migrations "$marker")" || { echo "  ABORT: could not compute pending migrations." >&2; exit 1; }
  count=0
  if [ -n "$pending_list" ]; then
    while IFS="$(printf '\t')" read -r version base file; do
      [ -n "$version" ] || continue
      count=$((count + 1))
      step "Running migration $base"
      info "version: $version"
      if MEMORY_DIR="$MEMORY_DIR" REPO_ROOT="$REPO_ROOT" bash "$file"; then
        write_applied_version "$marker_file" "$version"
        marker="$version"
        info "recorded $(basename "$marker_file"): $version"
      else
        rc=$?
        echo "  ABORT: migration failed: $file" >&2
        echo "  The applied-version marker was left at $marker." >&2
        exit "$rc"
      fi
    done <<EOF
$pending_list
EOF
  fi
  if [ "$count" -eq 0 ]; then
    info "No pending migrations (applied marker: $marker)"
  fi
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
    FETCH_STATUS="fetched origin"
    if ! git fetch --quiet --tags origin; then
      info "could not fetch origin; refs may be stale (offline or no origin)"
      FETCH_STATUS="using local refs"
    fi
    step "[dry-run] sync target"
    info "channel: $CHANNEL"
    if [ "$MODE" = "ref" ]; then
      info "target: $TARGET (--to override)"
    elif [ "$MODE" = "release" ]; then
      TARGET="$(latest_release_tag)"
      info "target: $TARGET (latest release tag)"
    else
      info "target: @{u} (dev ff-only merge)"
      preview_dev_incoming
    fi
    dry_run_migrations
    info "[dry-run] $FETCH_STATUS, not checking out, not installing"
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
    if [ "$BRANCH" = "HEAD" ]; then
      step "Recovering dev tracking branch"
      checkout_dev_tracking_branch
      BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    fi
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
    dry_run_migrations
    exit 0
  fi
  info "--no-pull: re-linking from current tree (no fetch)"
fi

run_migrations

if [ "$UPDATE_REMOTES" = 1 ]; then
  step "Re-resolving remote skills (--update: re-fetch pinned refs)"
  bash "$REPO_ROOT/scripts/resolve-skills.sh" --update \
    || { echo "  ABORT: a remote skill failed to re-resolve (see above)." >&2; exit 1; }
fi

step "Re-installing features (install.sh)"
bash "$REPO_ROOT/install.sh"

step "Sync complete"
info "Slash commands are loaded at session start — restart/reconnect to pick up new ones."
