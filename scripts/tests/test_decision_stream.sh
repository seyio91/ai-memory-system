#!/usr/bin/env bash
# Tests for scripts/lib/decision-stream.awk: head classification (legacy shapes
# unchanged, forward pointer), continuation parsing (topic:, SUPERSEDES, AMENDS)
# and the collector helpers (live set, amended-by, pointer completeness, prose
# amendment candidates). AWK=<binary> selects the awk under test.
. "$(dirname "$0")/_assert.sh"
set -uo pipefail

LIB="$SCRIPTS_DIR/lib/decision-stream.awk"
AWK="${AWK:-awk}"
T="$(mktemp -d "${TMPDIR:-/tmp}/dstest.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# run <mode> <file> [arg] — mode: heads | dump | live | amby <id> | missing | cand
run() {
    "$AWK" -v mode="$1" -v arg="${3:-}" "$(cat "$LIB")
BEGIN { ds_reset() }
{ sub(/\r\$/, \"\"); if (ds_track(\$0)) {
    if (mode == \"heads\") { c = ds_head(\$0); if (c != \"\") print c \"|\" DS_ID \"|\" DS_STATUS \"|\" DS_DATE \"|\" DS_PTR }
    else ds_feed(\$0) } }
END {
    if (mode == \"dump\") for (i = 1; i <= ds_count(); i++)
        print i \"|\" ds_id(i) \"|\" ds_status(i) \"|\" ds_topic(i) \"|S:\" ds_supersedes(i) \"|A:\" ds_amends(i) \"|P:\" ds_ptr(i)
    else if (mode == \"live\") print ds_live_ids()
    else if (mode == \"amby\") print ds_amended_by(arg)
    else if (mode == \"missing\") { m = ds_missing_pointers(); if (m != \"\") print m }
    else if (mode == \"unknown\") { m = ds_unknown_targets(); if (m != \"\") print m }
    else if (mode == \"badkw\") { m = ds_bad_keywords(); if (m != \"\") print m }
    else if (mode == \"dangling\") { m = ds_dangling_pointers(); if (m != \"\") print m }
    else if (mode == \"statusok\") print ds_status_ok(arg)
    else if (mode == \"cand\") { m = ds_candidates(); if (m != \"\") print m }
}" "$2"
}

cat > "$T/legacy.md" <<'EOF'
# X

## Decision stream

- D1 confirmed 2026-10-01 — plain
- D2b proposed 2026-10-02 — letter id
- D3 superseded — no date token
- D4-proposed — old shape
- D5: colon shape
- D6 (paren) old
- D7 confirmed 2026-02-30 — impossible day
- Dx not an id
- D8 confirmed
- not an entry

## Next
EOF
got="$(run heads "$T/legacy.md")"
assert_eq "ok|D1|confirmed|2026-10-01|
ok|D2b|proposed|2026-10-02|
ok|D3|superseded||
unmig|D4|||
unmig|D5|||
unmig|D6|||
bad|D7|confirmed|2026-02-30|
bad||||
bad|D8|||" "$got" "legacy heads classify as before (no pointer)"

cat > "$T/ptr.md" <<'EOF'
## Decision stream

- D45 confirmed 2026-10-01 → D75 — text
- D46 superseded → D80, D81 — no date
- D47 confirmed 2026-10-01 — arrow after dash → D9 stays text
- D50 → D5 2026-10-01 — pointer before date
EOF
got="$(run heads "$T/ptr.md")"
assert_eq "ok|D45|confirmed|2026-10-01|D75
ok|D46|superseded||D80 D81
ok|D47|confirmed|2026-10-01|
bad|D50|→|D5|" "$got" "forward pointer parsed after the date; misplaced or malformed stays bad"

cat > "$T/stream.md" <<'EOF'
---
kind: initiative
---
## Decision stream

- D1 confirmed 2026-10-01 → D3 — base rule
  topic: auth
  evidence: PR 1
- D2 superseded 2026-10-02 → D4 — old rule
  topic: net
- D3 confirmed 2026-10-03 — amendment of D1
  topic: auth
  AMENDS D1
  evidence: PR 2
- D4 proposed 2026-10-04 — replaces D2
  SUPERSEDES D2
  unconfirmed: nothing yet
- D5 rejected 2026-10-05 — nope
- D6 retired 2026-10-06 — gone
- D7 confirmed 2026-10-07 — multi
  AMENDS D1, D2
  SUPERSEDES D5 D6 (reason)
- D2 confirmed 2026-10-08 — repeated id, live copy

```
- D99 confirmed 2026-10-09 — fenced, ignored
  AMENDS D1
```

## Targets

- D100 confirmed 2026-10-10 — outside the stream
EOF
got="$(run dump "$T/stream.md")"
assert_eq "1|D1|confirmed|auth|S:|A:|P:D3
2|D2|superseded|net|S:|A:|P:D4
3|D3|confirmed|auth|S:|A:D1|P:
4|D4|proposed||S:D2|A:|P:
5|D5|rejected||S:|A:|P:
6|D6|retired||S:|A:|P:
7|D7|confirmed||S:D5 D6|A:D1 D2|P:
8|D2|confirmed||S:|A:|P:" "$got" "topic, SUPERSEDES, AMENDS and pointers collected per entry; fences and later sections skipped"

assert_eq "D1 D3 D4 D7 D2" "$(run live "$T/stream.md")" "live set = confirmed + proposed, superseded/rejected/retired drop out"
assert_eq "D3 D7" "$(run amby "$T/stream.md" D1)" "amended-by map: D1 amended by D3 and D7"
assert_eq "D7" "$(run amby "$T/stream.md" D2)" "amended-by map: D2 amended by D7"
assert_eq "" "$(run amby "$T/stream.md" D3)" "amended-by map: unamended entry is empty"

got="$(run missing "$T/stream.md")"
assert_eq "D1 D7 AMENDS
D2 D7 AMENDS
D5 D7 SUPERSEDES
D6 D7 SUPERSEDES" "$(printf '%s\n' "$got" | sort -k1,1 -k2,2)" "missing pointers: D1 names D3 only, D2 names D4 only (so D4 SUPERSEDES D2 is complete); D5/D6 have none"
case "$got" in *"D1 D3"*) _bad "complete pointer D1->D3 not reported" ;; *) _ok "complete pointer D1->D3 not reported" ;; esac
case "$got" in *"D2 D4"*) _bad "complete pointer D2->D4 not reported" ;; *) _ok "complete pointer D2->D4 not reported" ;; esac

cat > "$T/complete.md" <<'EOF'
## Decision stream

- D1 confirmed 2026-10-01 → D3, D4 — base
- D2 superseded 2026-10-01 → D4 — old
- D3 confirmed 2026-10-02 — amends
  AMENDS D1
- D4 confirmed 2026-10-03 — both
  AMENDS D1
  SUPERSEDES D2
EOF
assert_eq "" "$(run missing "$T/complete.md")" "pointer completeness: fully pointed stream reports nothing"

cat > "$T/cand.md" <<'EOF'
## Decision stream

- D10 confirmed 2026-10-01 — base rule. Amended by D12.
- D11 confirmed 2026-10-02 — Amends D10 (prose only).
- D12 confirmed 2026-10-03 — real amendment
  AMENDS D10
- D13 confirmed 2026-10-04 — text says amends d10a and Amends D10a again
- D14 confirmed 2026-10-05 — unamends D10 and misamended by D10 are not matches
- D15 confirmed 2026-10-06 — keyword form
  AMENDS D13
- D16 confirmed 2026-10-07 — amended by D15.
EOF
assert_eq "D11 D10
D13 D10a
D15 D16" "$(run cand "$T/cand.md")" "prose candidates: only pairs lacking an AMENDS keyword; keyword and word-boundary cases excluded"
printf '## Decision stream\n\n- D1 confirmed 2026-10-01 \342\200\224 x\r\n  topic: crlf\r\n  AMENDS D0\r\n' > "$T/crlf.md"
assert_eq "1|D1|confirmed|crlf|S:|A:D0|P:" "$(run dump "$T/crlf.md")" "CRLF input parses"


# --- locale: separator compares are byte-exact -------------------------------
cat > "$T/loc.md" <<'EOF'
## Decision stream

- D1 confirmed 2026-10-01 → D3. — x
- D2 confirmed 2026-10-01 → see D3 — x
- D3 confirmed 2026-10-01 – en dash
- D4 confirmed – en dash no date
- D5 confirmed 2026-10-01 · dot
- D6 confirmed 2026-10-01 → D7 — good
EOF
for loc in en_US.UTF-8 C; do
    got="$(LC_ALL=$loc run heads "$T/loc.md")"
    assert_eq "bad|D1|confirmed|2026-10-01|
bad|D2|confirmed|2026-10-01|
bad|D3|confirmed|2026-10-01|
bad|D4|confirmed|–|
bad|D5|confirmed|2026-10-01|
ok|D6|confirmed|2026-10-01|D7" "$got" "malformed pointer / en-dash / dot heads are bad under LC_ALL=$loc"
    assert_eq "ok|D1|confirmed|2026-10-01|
ok|D2b|proposed|2026-10-02|
ok|D3|superseded||
unmig|D4|||
unmig|D5|||
unmig|D6|||
bad|D7|confirmed|2026-02-30|
bad||||
bad|D8|||" "$(LC_ALL=$loc run heads "$T/legacy.md")" "legacy head classes unchanged under LC_ALL=$loc"
done

# --- candidates: lists, bad heads --------------------------------------------
cat > "$T/cand2.md" <<'EOF'
## Decision stream

- D20 confirmed 2026-10-01 — base
- D21 confirmed 2026-10-02 — amends D9/D14 and more
- D22 confirmed 2026-10-02 — Amends D51 and D54, plus x
- D23 confirmed 2026-10-02 — amends D51, D54.
- D24 confirmed 2026-10-02 — amends D50's rule
- D51 confirmed 2026-11-05 (proposed 2026-11-04) — amends D50's scope, and D52.
  more text amended by D60
- D25 confirmed 2026-10-03 — reject
  AMENDS D4.
  AMENDS D6 and D7
EOF
assert_eq "D21 D9
D21 D14
D22 D51
D22 D54
D23 D51
D23 D54
D24 D50
D51 D50
D60 D51" "$(run cand "$T/cand2.md")" "candidates: full id lists, each id its own line, bad heads scanned"
assert_eq "D25 D4 AMENDS
D25 D6 AMENDS
D25 D7 AMENDS" "$(run unknown "$T/cand2.md" | grep '^D25')" "keyword ids: trailing dot stripped, 'and' separates"
if run live "$T/cand2.md" | tr ' ' '\n' | grep -qx D51; then _bad "bad-head entry D51 is not in the live set"; else _ok "bad-head entry D51 is not in the live set"; fi
if run live "$T/cand2.md" | tr ' ' '\n' | grep -qx D20; then _ok "control: ok-head D20 is in the live set"; else _bad "control: ok-head D20 is in the live set"; fi
assert_eq "6" "$(run dump "$T/cand2.md" | wc -l | tr -d ' ')" "bad heads are not counted as entries"

# --- entry boundaries (blank line / fence), unknown targets, live amenders ---
printf '## Decision stream\n\n- D1 confirmed 2026-10-01 \342\200\224 a\n  topic: t1\n\n  topic: late\n- D2 confirmed 2026-10-01 \342\200\224 b\n  topic:\n  topic: t2\n```\n  AMENDS D1\n```\n- D3 confirmed 2026-10-01 \342\200\224 c\n  ```\n  topic: in-indented-fence\n  ```\n  topic: kept\n' > "$T/bound.md"
assert_eq "1|D1|confirmed|t1|S:|A:|P:
2|D2|confirmed|t2|S:|A:|P:
3|D3|confirmed|kept|S:|A:|P:" "$(run dump "$T/bound.md")" "blank line and column-0 fence end the entry; blank topic is not first; indented fence does not"

cat > "$T/live.md" <<'EOF'
## Decision stream

- D1 confirmed 2026-10-01 — base
- D2 rejected 2026-10-02 — dead amender
  AMENDS D1
- D3 superseded 2026-10-02 — dead superseder
  SUPERSEDES D1
- D4 confirmed 2026-10-03 — live
  AMENDS D1, D99
EOF
assert_eq "D4" "$(run amby "$T/live.md" D1)" "amended-by counts only live amenders"
assert_eq "D1 D4 AMENDS" "$(run missing "$T/live.md")" "missing pointers: only live amenders, only existing targets (D99 excluded)"
assert_eq "D4 D99 AMENDS" "$(run unknown "$T/live.md" | head -1)" "unknown targets name ids absent from the stream"
assert_eq "" "$(run amby "$T/live.md" "")" "ds_amended_by(\"\") is empty"

# --- id shapes after the keyword (markdown / punctuation / curly quote) -----
printf '## Decision stream\n\n- D30 confirmed 2026-10-01 \342\200\224 x\n- D31 confirmed 2026-10-01 \342\200\224 amends **D55** and D56, D57\342\200\231s tail\n- D32 confirmed 2026-10-01 \342\200\224 amends D1'"'"'s. Then D2 is unrelated\n- D33 confirmed 2026-10-01 \342\200\224 Amends: D3, D4)\n- D34 confirmed 2026-10-01 \342\200\224 amended  by\tD5/D6\n- D35 confirmed 2026-10-01 \342\200\224 amends D7abc nothing\n- D36 confirmed 2026-10-01 \342\200\224 amends\tD8\n- D37 confirmed 2026-10-01 \342\200\224 (amends D58)\n' > "$T/shapes.md"
assert_eq "D31 D55
D31 D56
D31 D57
D32 D1
D33 D3
D33 D4
D5 D34
D6 D34
D36 D8
D37 D58" "$(run cand "$T/shapes.md")" "prose id shapes: **D55**, D56, D57 curly 's, D1's., Amends:, tab, double space, D7abc rejected, (amends D58)"

# --- keyword continuation shapes, bad keywords, dangling pointers -----------
cat > "$T/kw.md" <<'EOF'
## Decision stream

- D40 confirmed 2026-10-01 → D41 — base
- D41 confirmed 2026-10-02 — amender
  AMENDS: D40
  AMENDS **D42**, D43)
  AMENDS see below
  SUPERSEDES
  AMENDS D40.
- D42 confirmed 2026-10-03 → D77 — pointer to nowhere
- D43 rejected 2026-10-03 — dead
  AMENDS D40
  SUPERSEDES nothing
EOF
assert_eq "1|D40|confirmed||S:|A:|P:D41
2|D41|confirmed||S:|A:D40 D42 D43 D40|P:
3|D42|confirmed||S:|A:|P:D77
4|D43|rejected||S:|A:D40|P:" "$(run dump "$T/kw.md")" "keyword ids parsed (colon, markdown, paren, dot); no empty slot in amends list"
assert_eq "D41 AMENDS see below
D41 SUPERSEDES
D43 SUPERSEDES nothing" "$(run badkw "$T/kw.md")" "unparseable AMENDS/SUPERSEDES lines are reported, not dropped"
assert_eq "D42 D77" "$(run dangling "$T/kw.md")" "dangling pointer reported"
assert_eq "" "$(run dangling "$T/complete.md")" "no dangling pointers in a complete stream"

# --- candidates skip non-live entries ---------------------------------------
cat > "$T/deadcand.md" <<'EOF'
## Decision stream

- D50 superseded 2026-10-01 — amends D1
- D51 rejected 2026-10-01 — amends D2
- D52 retired 2026-10-01 — amends D3
- D53 confirmed 2026-10-01 — amends D4
- D54 superseded 2026-11-05 (proposed 2026-11-04) — amends D5
- D55 confirmed 2026-11-05 (proposed 2026-11-04) — amends D6
EOF
assert_eq "D53 D4
D55 D6" "$(run cand "$T/deadcand.md")" "candidates skip superseded/rejected/retired entries (ok and bad heads)"

# --- ds_live is byte-exact under both locales --------------------------------
printf '## Decision stream\n\n- D1 confirmed\342\200\224 2026-10-01 \342\200\224 x\n- D2 confirmed 2026-10-01 \342\200\224 y\n- D3 confirmed\302\267 2026-10-01 \342\200\224 z\n' > "$T/livloc.md"
for loc in en_US.UTF-8 C; do
    assert_eq "D2" "$(LC_ALL=$loc run live "$T/livloc.md")" "ds_live matches the status byte-exactly under LC_ALL=$loc"
done

# --- blank line terminates the entry: later indented lines attach to nothing --
printf '## Decision stream\n\n- D1 confirmed 2026-10-01 \342\200\224 head\n  AMENDS D2\n\n  AMENDS D9\n  amends D8\n- D2 confirmed 2026-10-01 \342\200\224 next\n' > "$T/blank.md"
assert_eq "D2" "$(run dump "$T/blank.md" | sed -n 1p | sed 's/.*|A://; s/|P:.*//')" "blank line: AMENDS after it is not attached to the entry above"
assert_eq "" "$(run cand "$T/blank.md")" "blank line: prose 'amends D8' after it is not scanned as the entry's text"

# --- ds_status_ok is byte-exact ------------------------------------------------
for loc in en_US.UTF-8 C; do
    assert_eq "1 0 0" "$(for st in confirmed 'confirmed—' 'confirmed·'; do LC_ALL=$loc run statusok "$T/legacy.md" "$st"; done | tr '\n' ' ' | sed 's/ $//')" "ds_status_ok accepts confirmed, rejects confirmed— and confirmed· under LC_ALL=$loc"
done

finish
