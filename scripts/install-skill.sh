#!/usr/bin/env bash
# install-skill.sh — bring an existing skill into the store, two modes:
#
#  --remote <url>  REFERENCE a skill from a git source (the config-driven path).
#     Appends a [[skills]] entry to the TOML manifest (generic skills/skills.toml, or
#     skills-local/skills.toml with --local) AND resolves it into the gitignored cache
#     via resolve-skills.sh. No copy — the content is referenced, pinned, re-fetchable;
#     bump the ref + `resolve-skills.sh --update` to update. The manifest is the source
#     of truth and installing writes it back (--no-save to resolve without recording).
#     The skill declares its own tier in its SKILL.md, so --tier is not required here.
#
#  --from <dir|SKILL.md>  SEED a LOCAL skill from an existing dir (a fork you then own
#     and edit here). Copies under skills/<name>/ (or skills-local/<name>/ with --local),
#     normalizes metadata.tier = --tier, validates. This is authoring, not referencing:
#     it does not touch the manifest. Rule of thumb: modify it -> --from (local); just
#     use it -> --remote. --tier is required (classify it; do not guess).
#
# Neither mode injects the self-rating block (a first-party concern; add on request).
#
# Usage:
#   install-skill.sh --remote <url> --ref <ref> [--path <p>] [--name <n>] [--local] [--no-save] [--link] [--force]
#   install-skill.sh --from <dir|SKILL.md> --tier <tier> [--name <name>] [--local] [--link] [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

FROM="" REMOTE="" REF="" RPATH="" TIER="" NAME="" LINK=0 FORCE=0 LOCAL=0 SAVE=1
while [ $# -gt 0 ]; do
    case "$1" in
        --from)    FROM="${2:-}"; shift 2 ;;
        --remote)  REMOTE="${2:-}"; shift 2 ;;
        --ref)     REF="${2:-}"; shift 2 ;;
        --path)    RPATH="${2:-}"; shift 2 ;;
        --tier)    TIER="${2:-}"; shift 2 ;;
        --name)    NAME="${2:-}"; shift 2 ;;
        --local)   LOCAL=1; shift ;;
        --no-save) SAVE=0; shift ;;
        --link)    LINK=1; shift ;;
        --force)   FORCE=1; shift ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'install-skill: unknown arg: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# ── --remote: declare in the manifest + resolve into the cache ────────────────
if [ -n "$REMOTE" ]; then
    [ -z "$FROM" ] || { printf 'install-skill: --from and --remote are mutually exclusive\n' >&2; exit 2; }
    [ -n "$REF" ]  || { printf 'install-skill: --ref required with --remote (pin a branch/tag/sha)\n' >&2; exit 2; }
    case "$RPATH" in /*|*..*) printf 'install-skill: --path must be repo-relative, no ".."\n' >&2; exit 2 ;; esac

    # Name: --name, else the path basename, else the repo name (url minus .git).
    if [ -z "$NAME" ]; then
        if [ -n "$RPATH" ]; then NAME="$(basename "$RPATH")"
        else NAME="$(basename "$REMOTE")"; NAME="${NAME%.git}"; fi
    fi
    case "$NAME" in *[!A-Za-z0-9._-]*|""|.|..) printf 'install-skill: invalid skill name %s (set --name)\n' "$NAME" >&2; exit 2 ;; esac

    SCOPE=generic; [ "$LOCAL" = 1 ] && SCOPE=local
    MANIFEST="$(skill_manifest "$SCOPE")"

    if [ "$SAVE" = 1 ]; then
        mkdir -p "$(dirname "$MANIFEST")"
        REM_NAME="$NAME" REM_URL="$REMOTE" REM_REF="$REF" REM_PATH="$RPATH" REM_FORCE="$FORCE" \
        python3 - "$MANIFEST" <<'PY'
import os, sys
mf = sys.argv[1]
name, url, ref, path = (os.environ[k] for k in ("REM_NAME","REM_URL","REM_REF","REM_PATH"))
force = os.environ.get("REM_FORCE") == "1"
entries = []
if os.path.exists(mf):
    try:
        import tomllib
    except ModuleNotFoundError:
        sys.exit("install-skill: TOML manifests need python3.11+ (tomllib)")
    try:
        with open(mf, "rb") as f:
            entries = [e.get("name") for e in (tomllib.load(f).get("skills") or [])]
    except Exception as e:
        sys.exit("install-skill: cannot parse %s: %s" % (mf, e))
if name in entries and not force:
    sys.exit("install-skill: '%s' already in %s — edit it by hand, or --force to append anyway" % (name, mf))
def s(v): return v.replace("\\", "\\\\").replace('"', '\\"')
block = '\n[[skills]]\nname = "%s"\nurl  = "%s"\nref  = "%s"\n' % (s(name), s(url), s(ref))
if path:
    block += 'path = "%s"\n' % s(path)
with open(mf, "a") as f:
    f.write(block)
print("saved: %s (%s) -> %s" % (name, "local" if mf.endswith("skills-local/skills.toml") else "generic", mf))
PY
        rc=$?
        [ "$rc" = 0 ] || exit "$rc"
    fi

    # Materialize the manifest (resolves the new entry into the cache, pins it).
    if [ "$SAVE" = 1 ]; then
        bash "$SCRIPT_DIR/resolve-skills.sh" || { printf 'install-skill: resolve failed for %s\n' "$NAME" >&2; exit 1; }
    else
        printf 'install-skill: --no-save — declared nothing; nothing to resolve (remote installs go through the manifest)\n' >&2
        exit 0
    fi

    # Validate just this skill (its own SKILL.md tier etc.), then optionally link.
    vout="$(bash "$SCRIPT_DIR/validate-skills.sh" 2>&1 || true)"
    verr="$(printf '%s\n' "$vout" | awk -v n="$NAME" '$1=="ERROR:" && $2==n')"
    if [ -n "$verr" ]; then
        printf '%s\ninstall-skill: resolved remote %s has validation errors (review upstream)\n' "$verr" "$NAME" >&2
        exit 1
    fi
    echo "installed (remote): $NAME"
    if [ "$LINK" = 1 ]; then
        bash "$SCRIPT_DIR/link-skills.sh" >/dev/null && echo "linked: $NAME -> ~/.claude/skills"
    fi
    exit 0
fi

# ── --from: seed a local skill by copying (authoring, not referencing) ─────────
[ -n "$FROM" ] || { printf 'install-skill: --from or --remote required\n' >&2; exit 2; }
case "$TIER" in target-read-only|target-write) : ;; *) printf 'install-skill: --tier required (target-read-only | target-write) — classify the skill, do not guess\n' >&2; exit 2 ;; esac

# Resolve the source SKILL.md and the source dir to copy from.
if [ -d "$FROM" ]; then
    SRC_DIR="$FROM"; SRC_MD="$FROM/SKILL.md"
elif [ -f "$FROM" ]; then
    SRC_DIR="$(dirname "$FROM")"; SRC_MD="$FROM"
else
    printf 'install-skill: --from not found: %s\n' "$FROM" >&2; exit 2
fi
[ -f "$SRC_MD" ] || { printf 'install-skill: no SKILL.md at %s\n' "$SRC_MD" >&2; exit 2; }

# Name: --name, else frontmatter name, else source dir basename.
if [ -z "$NAME" ]; then
    NAME="$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^name:/{sub(/^name:[[:space:]]*/,"");sub(/[[:space:]]+$/,"");print;exit}' "$SRC_MD")"
    [ -n "$NAME" ] || NAME="$(basename "$SRC_DIR")"
fi
case "$NAME" in *[!A-Za-z0-9._-]*|.|..) printf 'install-skill: invalid skill name %s\n' "$NAME" >&2; exit 2 ;; esac

STORE="skills"; [ "$LOCAL" = 1 ] && STORE="skills-local"
TARGET="$MEMORY_DIR/$STORE/$NAME"

# Refuse an in-place re-import: --from resolving to TARGET would be deleted by
# the rm -rf below before the copy. Compare canonicalized paths.
SRC_ABS="$(cd "$SRC_DIR" 2>/dev/null && pwd || printf '%s' "$SRC_DIR")"
TGT_ABS="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd || printf '%s' "$(dirname "$TARGET")")/$(basename "$TARGET")"
if [ "$SRC_ABS" = "$TGT_ABS" ]; then
    printf 'install-skill: --from resolves to the install target (%s); copy it elsewhere first\n' "$TARGET" >&2; exit 2
fi

if [ -e "$TARGET" ] && [ "$FORCE" != 1 ]; then
    printf 'install-skill: %s already exists (use --force to overwrite)\n' "$TARGET" >&2; exit 1
fi
rm -rf "$TARGET"; mkdir -p "$TARGET"

# Copy the whole skill dir if --from was a dir (preserve references/ etc.),
# else just the single SKILL.md.
if [ -d "$FROM" ]; then
    cp -R "$SRC_DIR"/. "$TARGET"/
else
    cp "$SRC_MD" "$TARGET/SKILL.md"
fi

# Normalize: ensure metadata.tier = $TIER. Line-oriented (preserves formatting/
# comments). Only touches DIRECT children of the metadata: block — never a
# nested mapping key or a block-scalar body line that happens to read "tier:".
# Uses the block's own child indent, so non-2-space external frontmatter stays
# valid YAML. python3 is an accepted dev dependency. On failure, drop the
# half-installed TARGET rather than leave a broken skill behind.
if ! TIER="$TIER" python3 - "$TARGET/SKILL.md" <<'PY'
import os, sys
path = sys.argv[1]; tier = os.environ["TIER"]
lines = open(path).read().split("\n")
if not lines or lines[0].strip() != "---":
    sys.exit("source has no frontmatter")
end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
if end is None:
    sys.exit("unterminated frontmatter")
fm = lines[1:end]
indent = lambda s: len(s) - len(s.lstrip(" "))
mi = next((i for i, l in enumerate(fm) if l.rstrip() == "metadata:"), None)
if mi is None:
    fm += ["metadata:", "  tier: " + tier]
else:
    # Isolate the metadata block body (until the next column-0 line).
    bs = mi + 1
    be = bs
    while be < len(fm) and not (fm[be].strip() != "" and indent(fm[be]) == 0):
        be += 1
    body = fm[bs:be]
    # Normalize to our 2-space convention: if the block's direct children are
    # indented deeper than 2, shift the whole block left so tier (and siblings)
    # land at 2 spaces — preserving relative nesting (and never matching a
    # nested key or a block-scalar body line as "the" tier).
    child = next((indent(l) for l in body if l.strip() != "" and indent(l) > 0), 2)
    delta = child - 2
    if delta > 0:
        body = [l[delta:] if (l.strip() != "" and indent(l) >= delta) else l for l in body]
    set_it = False
    for k, l in enumerate(body):
        if l.strip() == "":
            continue
        if indent(l) == 2 and (l.strip() == "tier:" or l.strip().startswith("tier:")):
            body[k] = "  tier: " + tier; set_it = True; break
    if not set_it:
        body.insert(0, "  tier: " + tier)
    fm = fm[:bs] + body + fm[be:]
open(path, "w").write("\n".join(["---"] + fm + ["---"] + lines[end + 1:]))
PY
then
    rm -rf "$TARGET"
    printf 'install-skill: could not normalize frontmatter for %s (see error above)\n' "$NAME" >&2
    exit 1
fi

echo "installed: $TARGET (tier=$TIER)"

# Isolate THIS skill's validation errors by exact field match (a name may
# contain '.', a regex metachar — so compare fields, don't grep a pattern).
vout="$(bash "$SCRIPT_DIR/validate-skills.sh" 2>&1 || true)"
verr="$(printf '%s\n' "$vout" | awk -v n="$NAME" '$1=="ERROR:" && $2==n')"
if [ -n "$verr" ]; then
    printf '%s\n' "$verr" >&2
    printf 'install-skill: validation failed for %s — review %s\n' "$NAME" "$TARGET/SKILL.md" >&2
    exit 1
fi
echo "validated: $NAME OK"

if [ "$LINK" = 1 ]; then
    bash "$SCRIPT_DIR/link-skills.sh" >/dev/null && echo "linked: $NAME -> ~/.claude/skills"
fi
