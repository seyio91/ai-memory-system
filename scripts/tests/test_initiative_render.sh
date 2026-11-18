#!/usr/bin/env bash
# initiative-render.sh: Now / Environment matrix / Current rules fences.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"; ROOT="$(new_sandbox)"
trap 'rm -rf "$MEM" "$ROOT"' EXIT
export MEMORY_DIR="$MEM" AI_MEMORY_PROJECTS_ROOT="$ROOT"
SCRIPT="$SCRIPTS_DIR/initiative-render.sh"
mkdir -p "$MEM/initiatives"

cat > "$MEM/initiatives/full.md" <<'DOC'
---
kind: initiative
slug: full
status: active
created: 2026-08-14
envs: [staging, prod]
topics: [auth, storage]
---
# Full

Intro prose stays.

## Targets
### alpha/ready
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — write the thing | now · blocked_by: none
### alpha/after-edge
- execution_mode: interactive
- depends_on: alpha/ready, alpha/finished
- status: open · next: exec — follow up · blocked_by: none
### alpha/authored
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — go · blocked_by: waiting on legal
### alpha/stateblocked
- execution_mode: interactive
- depends_on: none
- status: blocked · next: exec — go · blocked_by: none
### alpha/finished
- execution_mode: interactive
- depends_on: none
- status: done
### alpha/dropped
- execution_mode: interactive
- depends_on: none
- status: closed
### alpha/thing@staging
- execution_mode: interactive
- depends_on: none
- status: done
### alpha/thing@prod
- execution_mode: interactive
- depends_on: alpha/thing@staging
- status: open · next: exec — roll to prod · blocked_by: none
### alpha/other@staging
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — stage it · blocked_by: none
### Closed
| Target | Closed | Jira | Outcome |
|---|---|---|---|
| alpha/old | 2026-01-01 | - | shipped |

## Notes

Between prose stays too.

## Decision stream
- D1 confirmed 2026-08-01 → D9 — Use tokens.
  topic: auth
- D2 confirmed 2026-08-02 — Bucket per env.
  topic: storage
- D3 proposed 2026-08-03 — Rotate keys.
  topic: auth
- D4 confirmed 2026-08-04 — Untagged rule.
- D5 confirmed 2026-08-05 — Odd topic.
  topic: weird
- D6 superseded 2026-08-06 — Old.
  topic: auth
- D9 confirmed 2026-08-09 — Token details.
  topic: auth
  AMENDS D1
DOC
cp "$MEM/initiatives/full.md" "$MEM/full.orig"

OUT="$("$SCRIPT" full 2>&1)"; rc=$?
assert_exit 0 "$rc" "default print exits 0"
assert_contains "$OUT" "<!-- BEGIN AUTOGEN initiative-render:now -->" "now fence printed"
assert_contains "$OUT" "| alpha/ready | exec — write the thing \\| now |" "ready row, pipe escaped"
case "$OUT" in
    *"| alpha/after-edge | alpha/ready (not done) |"*) _ok "blocked by unsatisfied edge only" ;;
    *) _bad "blocked by unsatisfied edge only"; printf '%s\n' "$OUT" ;;
esac
assert_contains "$OUT" "| alpha/authored | waiting on legal |" "blocked by authored blocked_by"
assert_contains "$OUT" "| alpha/stateblocked | blocked (no reason given) |" "state blocked"
assert_not_contains "$OUT" "| alpha/finished |" "done omitted"
assert_not_contains "$OUT" "| alpha/dropped |" "closed omitted"
assert_not_contains "$OUT" "| alpha/old |" "closed row omitted"
assert_contains "$OUT" "**Open proposals:** D3" "open proposals"
assert_contains "$OUT" "| Target | staging | prod |" "matrix columns"
assert_contains "$OUT" "| alpha/thing | done | open |" "matrix derived cells"
assert_contains "$OUT" "| alpha/other | open | not opened |" "matrix not opened"
assert_not_contains "$OUT" "| alpha/ready | staging" "non-@env not in matrix"
assert_contains "$OUT" "| auth | D1 (as amended by D9), D3 (proposed), D9 |" "rules: amended + proposed"
assert_contains "$OUT" "| storage | D2 |" "rules: storage row"
assert_contains "$OUT" "| (untagged) | D4 |" "rules: untagged"
assert_contains "$OUT" "| (unknown topic) | D5 |" "rules: unknown topic"
assert_not_contains "$OUT" "D6" "superseded not live"
D="$(date +%Y)"
assert_not_contains "$OUT" "$D-" "no date in fences"

A="$("$SCRIPT" full)"; B="$("$SCRIPT" full)"
assert_eq "$A" "$B" "two renders identical"

"$SCRIPT" full --check >/dev/null 2>&1; assert_exit 1 $? "check fails before first write"
"$SCRIPT" full --write; assert_exit 0 $? "write exits 0"
"$SCRIPT" full --check; assert_exit 0 $? "check passes after write"
cp "$MEM/initiatives/full.md" "$MEM/full.w1"
"$SCRIPT" full --write; cmp -s "$MEM/full.w1" "$MEM/initiatives/full.md"; assert_exit 0 $? "write idempotent"

# Bytes outside fences untouched: removing each inserted heading + fence + blank
# line from the written file must reproduce the original byte for byte.
awk '
    /^## (Now|Environment matrix|Current rules)$/ { skip = 1; next }
    skip && /^<!-- END AUTOGEN initiative-render:/ { skip = 2; next }
    skip == 2 { skip = 0; next }
    !skip { print }
' "$MEM/initiatives/full.md" > "$MEM/stripped"
cmp -s "$MEM/full.orig" "$MEM/stripped"; assert_exit 0 $? "bytes outside fences identical to original"
case "$(grep -E '^## (Now|Environment matrix|Targets)$' "$MEM/initiatives/full.md" | tr '\n' ,)" in
    "## Now,## Environment matrix,## Targets,") _ok "Now and matrix inserted before Targets" ;;
    *) _bad "Now and matrix inserted before Targets" ;;
esac
RL="$(grep -n '^## Current rules$' "$MEM/initiatives/full.md" | cut -d: -f1)"
DS="$(grep -n '^## Decision stream$' "$MEM/initiatives/full.md" | cut -d: -f1)"
[ -n "$RL" ] && [ "$((DS - RL))" -gt 0 ] && _ok "rules inserted before Decision stream" || _bad "rules inserted before Decision stream"

# Hand edit inside a fence -> stale.
cp "$MEM/initiatives/full.md" "$MEM/full.good"
sed 's/| storage | D2 |/| storage | D2, D77 |/' "$MEM/full.good" > "$MEM/initiatives/full.md"
ERR="$("$SCRIPT" full --check 2>&1)"; rc=$?
assert_exit 1 "$rc" "check fails on hand edit"
assert_contains "$ERR" "stale fence: rules" "names stale fence"
"$SCRIPT" full --write; "$SCRIPT" full --check; assert_exit 0 $? "write repairs stale fence"
cmp -s "$MEM/full.good" "$MEM/initiatives/full.md"; assert_exit 0 $? "repair restores exact bytes"

# Deleted fence (marker lines + body + heading) -> missing, restored in place.
awk '
    /^## Environment matrix$/ { skip = 1 }
    /^## Targets$/ { skip = 0 }
    !skip { print }
' "$MEM/full.good" > "$MEM/initiatives/full.md"
ERR="$("$SCRIPT" full --check 2>&1)"; rc=$?
assert_exit 1 "$rc" "check fails on deleted section"
assert_contains "$ERR" "missing fence: matrix" "names missing fence"
"$SCRIPT" full --write
cmp -s "$MEM/full.good" "$MEM/initiatives/full.md"; assert_exit 0 $? "write restores deleted section in place"

# Heading kept, fence deleted -> fence reinserted under the heading.
awk '
    /^<!-- BEGIN AUTOGEN initiative-render:now -->$/ { skip = 1 }
    !skip { print }
    /^<!-- END AUTOGEN initiative-render:now -->$/ { skip = 0 }
' "$MEM/full.good" > "$MEM/initiatives/full.md"
"$SCRIPT" full --check >/dev/null 2>&1; assert_exit 1 $? "check fails on deleted fence under heading"
"$SCRIPT" full --write
cmp -s "$MEM/full.good" "$MEM/initiatives/full.md"; assert_exit 0 $? "write restores fence under existing heading"

# Symlink refused.
cp "$MEM/full.orig" "$MEM/real.md"
mkdir -p "$MEM/linkmem/initiatives"
sed 's/slug: full/slug: lnk/' "$MEM/full.orig" > "$MEM/real.md"
ln -s "$MEM/real.md" "$MEM/initiatives/lnk.md"
cp "$MEM/real.md" "$MEM/real.before"
ERR="$("$SCRIPT" lnk --write 2>&1)"; rc=$?
assert_exit 1 "$rc" "write refuses symlink"
assert_contains "$ERR" "refusing symlink" "symlink message"
cmp -s "$MEM/real.md" "$MEM/real.before"; assert_exit 0 $? "symlink target untouched"

# envs: removed after a matrix fence was written -> orphan, then removed cleanly.
sed '/^envs:/d' "$MEM/full.good" > "$MEM/initiatives/full.md"
ERR="$("$SCRIPT" full --check 2>&1)"; rc=$?
assert_exit 1 "$rc" "check fails on orphan matrix fence"
assert_contains "$ERR" "orphan fence: matrix" "names orphan fence"
awk '
    /^## Environment matrix$/ { skip = 1; next }
    skip && /^<!-- END AUTOGEN initiative-render:matrix -->$/ { skip = 2; next }
    skip == 2 { skip = 0; if ($0 == "") next }
    !skip { print }
' "$MEM/initiatives/full.md" > "$MEM/orphan.expected"
"$SCRIPT" full --write; assert_exit 0 $? "write removes orphan matrix"
cmp -s "$MEM/orphan.expected" "$MEM/initiatives/full.md"; assert_exit 0 $? "orphan removal leaves every other byte intact"
"$SCRIPT" full --check; assert_exit 0 $? "check passes after orphan removal"
cp "$MEM/full.good" "$MEM/initiatives/full.md"

# No envs: -> no matrix section.
sed -e '/^envs:/d' "$MEM/full.orig" | sed 's/slug: full/slug: noenv/' > "$MEM/initiatives/noenv.md"
OUT="$("$SCRIPT" noenv)"
assert_not_contains "$OUT" "initiative-render:matrix" "no matrix fence without envs"
"$SCRIPT" noenv --write; "$SCRIPT" noenv --check; assert_exit 0 $? "no-envs write then check"
case "$(cat "$MEM/initiatives/noenv.md")" in
    *"## Environment matrix"*) _bad "no matrix heading without envs" ;;
    *) _ok "no matrix heading without envs" ;;
esac

# CRLF file: markers and headings recognised, endings preserved, idempotent.
sed -e 's/slug: full/slug: crlf/' -e 's/$/\r/' "$MEM/full.orig" > "$MEM/initiatives/crlf.md"
cp "$MEM/initiatives/crlf.md" "$MEM/crlf.orig"
"$SCRIPT" crlf --write; assert_exit 0 $? "CRLF: write exits 0"
"$SCRIPT" crlf --check; assert_exit 0 $? "CRLF: check passes after write"
cp "$MEM/initiatives/crlf.md" "$MEM/crlf.w1"
"$SCRIPT" crlf --write; cmp -s "$MEM/crlf.w1" "$MEM/initiatives/crlf.md"; assert_exit 0 $? "CRLF: second write is a no-op"
assert_eq "1" "$(grep -c 'BEGIN AUTOGEN initiative-render:now' "$MEM/initiatives/crlf.md" | tr -d '[:space:]')" "CRLF: no duplicate markers"
assert_eq "0" "$(grep -vc "$(printf '\r')\$" "$MEM/initiatives/crlf.md" | tr -d '[:space:]')" "CRLF: every line still ends in CR"
awk '
    /^## (Now|Environment matrix|Current rules)\r?$/ { skip = 1; next }
    skip && /^<!-- END AUTOGEN initiative-render:/ { skip = 2; next }
    skip == 2 { skip = 0; next }
    !skip { print }
' "$MEM/initiatives/crlf.md" > "$MEM/crlf.stripped"
cmp -s "$MEM/crlf.orig" "$MEM/crlf.stripped"; assert_exit 0 $? "CRLF: untouched lines byte-identical"

# File mode preserved.
cp "$MEM/full.orig" "$MEM/initiatives/mode.md"; sed -i.bak 's/slug: full/slug: mode/' "$MEM/initiatives/mode.md"; rm -f "$MEM/initiatives/mode.md.bak"
chmod 600 "$MEM/initiatives/mode.md"
"$SCRIPT" mode --write
M="$(stat -c %a "$MEM/initiatives/mode.md" 2>/dev/null || stat -f %Lp "$MEM/initiatives/mode.md")"
assert_eq "600" "$M" "write preserves file mode"

# Headings with trailing whitespace are anchors and headings alike.
sed -e 's/slug: full/slug: ws/' -e 's/^## Targets$/## Targets  /' -e "s/^## Decision stream\$/## Decision stream $(printf '\t')/" "$MEM/full.orig" > "$MEM/initiatives/ws.md"
"$SCRIPT" ws --write; assert_exit 0 $? "trailing-blank headings: write exits 0"
"$SCRIPT" ws --check; assert_exit 0 $? "trailing-blank headings: check passes (all three inserted)"
assert_eq "3" "$(grep -c 'BEGIN AUTOGEN' "$MEM/initiatives/ws.md" | tr -d '[:space:]')" "trailing-blank headings: three fences inserted"

# An @env whose env is not in envs: gets a trailing column.
sed -e 's/slug: full/slug: extra/' -e 's/^### alpha\/other@staging$/### alpha\/other@qa/' "$MEM/full.orig" > "$MEM/initiatives/extra.md"
OUT="$("$SCRIPT" extra)"
assert_contains "$OUT" "| Target | staging | prod | qa |" "undeclared env gets an extra trailing column"
assert_contains "$OUT" "| alpha/other | not opened | not opened | open |" "undeclared env cell carries the stage"

# Orphan with a blank line between heading and fence: heading goes too.
"$SCRIPT" full --write
sed '/^envs:/d' "$MEM/initiatives/full.md" | awk '{ print } /^## Environment matrix$/ { print "" }' > "$MEM/orph2.md"
cp "$MEM/orph2.md" "$MEM/initiatives/full.md"
"$SCRIPT" full --write
assert_eq "0" "$(grep -c 'Environment matrix' "$MEM/initiatives/full.md" | tr -d '[:space:]')" "orphan removal drops the heading even with a blank line before the fence"
"$SCRIPT" full --check; assert_exit 0 $? "check passes after that orphan removal"

# Anchors are only required when an insertion needs them.
"$SCRIPT" full --write
grep -v '^## Decision stream$' "$MEM/initiatives/full.md" > "$MEM/initiatives/full2.md"
sed -i.bak 's/slug: full/slug: full2/' "$MEM/initiatives/full2.md"; rm -f "$MEM/initiatives/full2.md.bak"
"$SCRIPT" full2 --write; assert_exit 0 $? "write without Decision stream heading is fine when no insertion is needed"
sed -e 's/slug: full/slug: nod/' "$MEM/full.orig" | grep -v '^## Decision stream$' > "$MEM/initiatives/nod.md"
"$SCRIPT" nod --write >/dev/null 2>&1; assert_exit 1 $? "write refuses when an insertion needs the missing Decision stream anchor"

# A bare "### " heading under Targets no longer breaks the renderer.
sed -e 's/slug: full/slug: bare/' -e 's/^### alpha\/dropped$/### /' "$MEM/full.orig" > "$MEM/initiatives/bare.md"
"$SCRIPT" bare >/dev/null 2>&1; assert_exit 0 $? "bare '### ' heading: render exits 0"

# Headings and markers inside fenced code blocks are ignored (``` and ~~~).
for fch in '```' '~~~'; do
    {
        sed -n '1,/^Intro prose stays\.$/p' "$MEM/full.orig" | sed 's/slug: full/slug: code/'
        printf '\n%s\n## Now\n## Decision stream\n<!-- BEGIN AUTOGEN initiative-render:now -->\nstale\n%s\n' "$fch" "$fch"
        sed -n '/^Intro prose stays\.$/,$p' "$MEM/full.orig" | sed 1d
    } > "$MEM/initiatives/code.md"
    cp "$MEM/initiatives/code.md" "$MEM/code.orig"
    "$SCRIPT" code --write; assert_exit 0 $? "$fch block: write exits 0"
    "$SCRIPT" code --check; assert_exit 0 $? "$fch block: check passes"
    assert_eq "2" "$(grep -c '^<!-- BEGIN AUTOGEN initiative-render:now -->' "$MEM/initiatives/code.md" | tr -d '[:space:]')" "$fch block: one real now fence plus the one inside the block"
    awk -v f="$fch" '
        $0 == f { infence = !infence }
        !infence && /^## Now$/ { seen = 1 }
        END { exit !seen }' "$MEM/initiatives/code.md"
    assert_exit 0 $? "$fch block: sections inserted outside the block"
    grep -q '^stale$' "$MEM/initiatives/code.md"; assert_exit 0 $? "$fch block: block content untouched"
done

# Frontmatter lists: quoted inline items and YAML block lists, same result.
sed -e 's/slug: full/slug: q/' -e "s/^envs: .*/envs: [staging, \"prod\"]/" -e "s/^topics: .*/topics: ['auth', \"storage\"]/" "$MEM/full.orig" > "$MEM/initiatives/q.md"
sed -e 's/slug: full/slug: blk/' -e '/^envs: /c\
envs:\
  - staging\
  - "prod"' -e '/^topics: /c\
topics:\
  - auth\
  - '"'"'storage'"'"'' "$MEM/full.orig" > "$MEM/initiatives/blk.md"
sed 's/slug: full/slug: base/' "$MEM/full.orig" > "$MEM/initiatives/base.md"
BASE="$("$SCRIPT" base)"
assert_eq "$BASE" "$("$SCRIPT" q)" "quoted inline lists render like plain ones"
assert_eq "$BASE" "$("$SCRIPT" blk)" "YAML block lists render like inline ones"

# A Target whose stage is unknown is Blocked, never Ready.
mkdir -p "$MEM/projects/ghost"
printf -- '---\ntopic: ghost\nscope: project\nsummary: g\nrepo_path: absent-checkout\n---\n' > "$MEM/projects/ghost/memory.md"
cat > "$MEM/initiatives/unk.md" <<'DOC'
---
kind: initiative
slug: unk
status: active
created: 2026-08-14
topics: [a]
---
# Unk
## Targets
### ghost/x
- execution_mode: software_adw
- task: t-1
- stages: plan -> implement
- depends_on: none
## Decision stream
DOC
OUT="$("$SCRIPT" unk)"
assert_contains "$OUT" "| ghost/x | stage unknown |" "unknown stage is Blocked with reason"
assert_contains "$OUT" "**Sessions to start:** none" "unknown stage is not in Sessions to start"
assert_contains "$OUT" "**Waiting on you:** none" "unknown stage is not in Waiting on you"

# Now: Decisions needed / Waiting on you / Sessions to start / Blocked.
mkdir -p "$MEM/projects/alpha/plans" "$ROOT/alpha-co/.agents"
printf 'alpha\n' > "$ROOT/alpha-co/.agents/memory-project"
printf -- '---\ntopic: alpha\nscope: project\nsummary: a\nrepo_path: alpha-co\n---\n' > "$MEM/projects/alpha/memory.md"
printf '%s\n' '---' 'plan: draft' 'status: draft' 'task_ref: t-draft-001' '---' > "$MEM/projects/alpha/plans/draft.md"
cat > "$MEM/initiatives/nv.md" <<'DOC'
---
kind: initiative
slug: nv
status: active
created: 2026-08-14
---
# Nv
## Targets
### alpha/user1
- execution_mode: interactive
- depends_on: none
- status: open · next: user — confirm scope · blocked_by: none
### alpha/user2
- execution_mode: interactive
- depends_on: none
- status: open · next: user — review; then exec session — implement · blocked_by: none
### alpha/sess
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — go · blocked_by: none
### alpha/swa
- execution_mode: software_adw
- task: t-draft-001
- stages: discover -> plan -> implement -> validate
- depends_on: none
### alpha/lost
- execution_mode: interactive
- depends_on: alpha/nowhere
- status: open · next: exec — x · blocked_by: none
### alpha/needs
- execution_mode: interactive
- depends_on: alpha/swa (stage: implement)
- status: open · next: exec — x · blocked_by: none
### alpha/gate2
- execution_mode: interactive
- depends_on: none
- status: blocked · next: exec — wait · blocked_by: pilot choice D79
### alpha/mid
- execution_mode: interactive
- depends_on: alpha/gate1
- status: open · next: exec — plan ahead · blocked_by: none
### alpha/gate1
- execution_mode: interactive
- depends_on: none
- status: blocked · next: exec — wait · blocked_by: waiting on D84 and D2
### alpha/leaf
- execution_mode: interactive
- depends_on: alpha/mid
- status: open · next: exec — x · blocked_by: none
### alpha/finished
- execution_mode: interactive
- depends_on: none
- status: done
## Decision stream
- D2 confirmed 2026-08-02 — Settled.
- D7 proposed 2026-08-03 — Unrelated.
- D79 proposed 2026-08-04 — Pilot apps.
- D84 proposed 2026-08-05 — Gate.
DOC
OUT="$("$SCRIPT" nv)"
NOW="$(printf '%s\n' "$OUT" | sed -n '/initiative-render:now -->$/,/END AUTOGEN initiative-render:now/p')"
assert_eq "**Decisions needed**|**Waiting on you**|**Sessions to start**|**Blocked**|**Open proposals:** D79 (blocking), D84 (blocking), D7|" "$(printf '%s\n' "$NOW" | grep '^\*\*' | tr '\n' '|')" "now: section order"
assert_contains "$NOW" "| alpha/user1 | user — confirm scope |" "user row in Waiting on you"
assert_contains "$NOW" "| alpha/user2 | user — review; then exec session — implement |" "chained user row in Waiting on you"
WAIT="$(printf '%s\n' "$NOW" | sed -n '/^\*\*Waiting on you\*\*/,/^\*\*Sessions/p')"
assert_not_contains "$WAIT" "alpha/sess" "session row not in Waiting on you"
SESS="$(printf '%s\n' "$NOW" | sed -n '/^\*\*Sessions to start\*\*/,/^\*\*Blocked/p')"
assert_contains "$SESS" "| alpha/sess | exec — go |" "exec row in Sessions to start"
assert_contains "$SESS" "| alpha/swa | (stage: plan) |" "no-next Target in Sessions to start"
assert_not_contains "$SESS" "alpha/user" "user rows not in Sessions to start"
DEC="$(printf '%s\n' "$NOW" | sed -n '/^\*\*Decisions needed\*\*/,/^\*\*Waiting/p')"
assert_contains "$DEC" "| Decision | Blocks |" "decisions table header"
assert_contains "$DEC" "| D84 | alpha/mid, alpha/gate1, alpha/leaf |" "decision blocks citing + transitive Targets"
assert_contains "$DEC" "| D79 | alpha/gate2 |" "D79 is not matched by D7"
assert_not_contains "$DEC" "| D7 |" "uncited proposed id not listed"
assert_not_contains "$DEC" "| D2 |" "confirmed cited id not listed"
BLK="$(printf '%s\n' "$NOW" | sed -n '/^\*\*Blocked\*\*/,/^\*\*Open/p' | grep '^| alpha/' | cut -d' ' -f2 | tr '\n' ,)"
assert_eq "alpha/gate1,alpha/mid,alpha/lost,alpha/needs,alpha/gate2,alpha/leaf," "$BLK" "blocked sorted by hold-up count, ties in file order"
assert_contains "$NOW" "| alpha/mid | alpha/gate1 (blocked) |" "wording: at blocked -> blocked"
assert_contains "$NOW" "| alpha/leaf | alpha/mid (not done) |" "wording: at X -> not done"
assert_contains "$NOW" "| alpha/needs | alpha/swa (stage: implement) (needs implement) |" "wording: at X, needs Y -> needs Y"
assert_contains "$NOW" "| alpha/lost | alpha/nowhere (not found) |" "wording: not found kept"
assert_not_contains "$OUT" "(at " "no (at ) wording in render output"
TSV="$(bash "$SCRIPTS_DIR/initiative-status.sh" --tsv nv 2>/dev/null)"
assert_contains "$TSV" "alpha/gate1 (at blocked)" "status --tsv unsatisfied wording still uses (at ) that the renderer maps"
assert_contains "$TSV" "(at plan, needs implement)" "status --tsv still reports (at X, needs Y)"

cat > "$MEM/initiatives/emp.md" <<'DOC'
---
kind: initiative
slug: emp
status: active
created: 2026-08-14
---
# Emp
## Targets
### alpha/solo
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — go · blocked_by: none
## Decision stream
DOC
OUT="$("$SCRIPT" emp)"
assert_contains "$OUT" "**Decisions needed:** none" "empty Decisions needed"
assert_contains "$OUT" "**Waiting on you:** none" "empty Waiting on you"
assert_contains "$OUT" "| alpha/solo | exec — go |" "solo row in Sessions to start"
assert_contains "$OUT" "**Blocked:** none" "empty Blocked"
assert_contains "$OUT" "**Open proposals:** none" "empty Open proposals"

# Pipes already escaped in the source are not escaped twice.
cat > "$MEM/initiatives/pipe.md" <<'DOC'
---
kind: initiative
slug: pipe
status: active
created: 2026-08-14
---
# Pipe
## Targets
### alpha/p
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — a \| b | c · blocked_by: none
### alpha/q
- execution_mode: interactive
- depends_on: none
- status: open · next: exec — go · blocked_by: x \| y | z
## Decision stream
DOC
OUT="$("$SCRIPT" pipe)"
assert_contains "$OUT" '| alpha/p | exec — a \| b \| c |' "next: keeps \\| and escapes bare |"
assert_contains "$OUT" '| alpha/q | x \| y \| z |' "blocked_by: keeps \\| and escapes bare |"

# CRLF: the rendered content (not just the markers) matches the LF render.
assert_eq "$("$SCRIPT" base)" "$("$SCRIPT" crlf)" "CRLF: printed fences equal the LF render byte for byte"
tr -d '\r' < "$MEM/initiatives/crlf.md" | sed 's/slug: crlf/slug: base/' > "$MEM/crlf.lf"
"$SCRIPT" base --write
cmp -s "$MEM/crlf.lf" "$MEM/initiatives/base.md"; assert_exit 0 $? "CRLF: written fences equal the LF write once CRs are removed"

# No final newline: --write adds exactly one, is then stable, never corrupts the last line.
printf '%s' "$(cat "$MEM/full.orig")" | sed 's/slug: full/slug: nonl/' > "$MEM/initiatives/nonl.md"
"$SCRIPT" nonl --write; assert_exit 0 $? "no final newline: write exits 0"
assert_eq "  AMENDS D1" "$(tail -n1 "$MEM/initiatives/nonl.md")" "no final newline: last line intact"
case "$(tail -c2 "$MEM/initiatives/nonl.md" | od -An -tx1 | tr -d ' \n')" in
    *0a0a) _bad "no final newline: exactly one trailing newline" ;;
    *0a) _ok "no final newline: exactly one trailing newline" ;;
    *) _bad "no final newline: exactly one trailing newline" ;;
esac
"$SCRIPT" nonl --check; assert_exit 0 $? "no final newline: check passes after write"
cp "$MEM/initiatives/nonl.md" "$MEM/nonl.w1"
"$SCRIPT" nonl --write; cmp -s "$MEM/nonl.w1" "$MEM/initiatives/nonl.md"; assert_exit 0 $? "no final newline: second write is a no-op"

# An interrupted --write leaves no temp file behind.
cp "$MEM/full.orig" "$MEM/initiatives/intr.md"; sed -i.bak 's/slug: full/slug: intr/' "$MEM/initiatives/intr.md"; rm -f "$MEM/initiatives/intr.md.bak"
( "$SCRIPT" intr --write & p=$!; kill -TERM "$p" 2>/dev/null; wait "$p" 2>/dev/null ) >/dev/null 2>&1
assert_eq "0" "$(find "$MEM/initiatives" -name '*.tmp.*' | wc -l | tr -d '[:space:]')" "no leftover temp file after TERM"

# Usage / errors.
"$SCRIPT" >/dev/null 2>&1; assert_exit 2 $? "no slug is usage error"
"$SCRIPT" nope >/dev/null 2>&1; assert_exit 1 $? "missing initiative exits 1"

finish
