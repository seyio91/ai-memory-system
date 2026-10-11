#!/usr/bin/env bash
# skills/skill-audit/scripts/lint_skill.py: one fixture per rule, hermetic, stdlib python only.
. "$(dirname "$0")/_assert.sh"

LINT="$SCRIPTS_DIR/../skills/skill-audit/scripts/lint_skill.py"
command -v python3 >/dev/null 2>&1 || { printf 'SKIP: python3 unavailable\n'; finish; }

TMP="$(new_sandbox)"
trap 'rm -rf "$TMP"' EXIT

run() { out=$(python3 "$LINT" "$@" 2>"$TMP/err"); code=$?; err=$(cat "$TMP/err"); }

# summary <json> [skill] — "rule:status:file:line" per finding, sorted
summary() {
    printf '%s' "$1" | python3 -c '
import json, sys
want = sys.argv[1] if len(sys.argv) > 1 else None
for s in json.load(sys.stdin)["skills"]:
    if want and s["skill"] != want:
        continue
    for f in s["findings"]:
        print("%s:%s:%s:%s" % (f["rule"], f["status"], f["file"], f["line"]))
' "${2:-}" | LC_ALL=C sort
}

rules_of() { summary "$@" | cut -d: -f1 | sort -un | tr '\n' ' '; }

mk_good() {
    local d="$1"
    mkdir -p "$d/references" "$d/evals"
    cat > "$d/SKILL.md" <<'EOT'
---
name: sample
description: Checks sample files for drift. Use when reviewing sample output.
---

# Sample

Read [the reference](references/ref.md) for details.
EOT
    printf '# Ref\n\nShort reference.\n' > "$d/references/ref.md"
    printf '{"evals": [{"p": 1}, {"p": 2}, {"p": 3}]}\n' > "$d/evals/evals.json"
}

bad() {
    # bad <name> — fresh copy of the good skill under $TMP/bad/<name>
    mk_good "$TMP/bad/$1"
}

# === good skill: nothing to report ============================================
mk_good "$TMP/good"
run "$TMP/good"
assert_exit 0 "$code" "good skill exits 0"
assert_eq "" "$(summary "$out")" "good skill has zero fails and zero candidates"
assert_contains "$out" '"skill": "sample"' "output names the skill"

# === rule 1: body length ======================================================
bad r1len
for _ in $(seq 1 505); do echo "filler" >> "$TMP/bad/r1len/SKILL.md"; done
run "$TMP/bad/r1len"
assert_eq "1 " "$(rules_of "$out")" "rule 1: only rule 1 fires on a long body"
assert_contains "$out" "body is 509 lines" "rule 1: message carries the line count"

# === rule 1: missing link =====================================================
bad r1miss
printf '\nSee [gone](references/gone.md).\n' >> "$TMP/bad/r1miss/SKILL.md"
run "$TMP/bad/r1miss"
assert_eq "1 " "$(rules_of "$out")" "rule 1: only rule 1 fires on a missing linked file"
assert_contains "$(summary "$out")" "1:fail:SKILL.md:10" "rule 1: missing link reported with its line"
assert_contains "$out" "references/gone.md" "rule 1: missing link message names the target"

# === rule 1: chain and unreachable ============================================
bad r1chain
printf '\nSee [deep](deep.md).\n' >> "$TMP/bad/r1chain/references/ref.md"
printf '# Deep\n\nBody.\n' > "$TMP/bad/r1chain/references/deep.md"
run "$TMP/bad/r1chain"
assert_eq "1 " "$(rules_of "$out")" "rule 1: only rule 1 fires on a chained reference"
assert_contains "$out" "linked only from references/ref.md" "rule 1: chain names the intermediate file"

bad r1orphan
printf '# Orphan\n\nBody.\n' > "$TMP/bad/r1orphan/references/orphan.md"
run "$TMP/bad/r1orphan"
assert_eq "1 " "$(rules_of "$out")" "rule 1: only rule 1 fires on an orphan file"
assert_contains "$out" "references/orphan.md is unreachable" "rule 1: orphan reported as unreachable"

# evals/ and scripts/ markdown is exempt from reachability
bad r1exempt
printf '# Case\n' > "$TMP/bad/r1exempt/evals/case.md"
mkdir -p "$TMP/bad/r1exempt/scripts"; printf '# Notes\n' > "$TMP/bad/r1exempt/scripts/notes.md"
run "$TMP/bad/r1exempt"
assert_eq "" "$(summary "$out")" "rule 1: evals/ and scripts/ markdown is not flagged unreachable"

# === rule 2: long reference without contents ==================================
bad r2
for _ in $(seq 1 110); do echo "row" >> "$TMP/bad/r2/references/ref.md"; done
run "$TMP/bad/r2"
assert_eq "2 " "$(rules_of "$out")" "rule 2: only rule 2 fires on a long reference with no contents"
assert_contains "$out" "113 lines" "rule 2: message carries the line count"

bad r2ok
{ printf '# Ref\n\n- [One](#one)\n- [Two](#two)\n\n'; for _ in $(seq 1 110); do echo "row"; done; } > "$TMP/bad/r2ok/references/ref.md"
run "$TMP/bad/r2ok"
assert_eq "" "$(summary "$out")" "rule 2: a link list after the H1 counts as contents"

bad r2head
{ printf '# Ref\n\n## Table of contents\n\n'; for _ in $(seq 1 110); do echo "row"; done; } > "$TMP/bad/r2head/references/ref.md"
run "$TMP/bad/r2head"
assert_eq "" "$(summary "$out")" "rule 2: a contents heading counts as contents"

# === rule 5: description person ===============================================
bad r5
sed -i.bak 's/^description:.*/description: I can check sample files. Use when you need it./' "$TMP/bad/r5/SKILL.md"; rm "$TMP/bad/r5/SKILL.md.bak"
run "$TMP/bad/r5"
assert_eq "5 " "$(rules_of "$out")" "rule 5: only rule 5 fires on a first-person description"
assert_contains "$out" "'I'" "rule 5: message quotes the phrase"

bad r5you
sed -i.bak 's/^description:.*/description: Checks files. Use when your team needs it./' "$TMP/bad/r5you/SKILL.md"; rm "$TMP/bad/r5you/SKILL.md.bak"
run "$TMP/bad/r5you"
assert_contains "$out" "'your'" "rule 5: second person is caught"

bad r5none
sed -i.bak '/^description:/d' "$TMP/bad/r5none/SKILL.md"; rm "$TMP/bad/r5none/SKILL.md.bak"
run "$TMP/bad/r5none"
assert_eq "5 " "$(rules_of "$out")" "rule 5: missing description fails"
assert_contains "$out" "missing" "rule 5: missing description message"

# === rule 9: paths ============================================================
bad r9win
printf '\nOpen docs\\guide.md first.\n' >> "$TMP/bad/r9win/SKILL.md"
run "$TMP/bad/r9win"
assert_eq "9 " "$(rules_of "$out")" "rule 9: only rule 9 fires on a backslash path"
assert_contains "$(summary "$out")" "9:fail:SKILL.md:10" "rule 9: backslash path reported with its line"

bad r9drive
printf '\nInstall to C:\\tools.\n' >> "$TMP/bad/r9drive/SKILL.md"
run "$TMP/bad/r9drive"
assert_eq "9 " "$(rules_of "$out")" "rule 9: drive-letter path fails"

bad r9abs
printf '\nConfig lives at /Users/alice/conf.\n' >> "$TMP/bad/r9abs/references/ref.md"
run "$TMP/bad/r9abs"
assert_eq "9 " "$(rules_of "$out")" "rule 9: only rule 9 fires on an absolute user path"
assert_contains "$(summary "$out")" "9:fail:references/ref.md:5" "rule 9: absolute path reported in the reference file"

bad r9home
printf '\nConfig lives at /home/bob/conf.\n' >> "$TMP/bad/r9home/SKILL.md"
run "$TMP/bad/r9home"
assert_contains "$out" "/home/bob/" "rule 9: /home/<name>/ is caught"

bad r9fence
printf '\n```\ndocs\\guide.md\n```\n' >> "$TMP/bad/r9fence/SKILL.md"
run "$TMP/bad/r9fence"
assert_eq "" "$(summary "$out")" "rule 9: backslashes inside fenced code are ignored"

# === rule 10: hook candidates =================================================
bad r10
printf '\nNever commit secrets.\nYou MUST run tests.\nAlways lint.\n' >> "$TMP/bad/r10/SKILL.md"
printf '\nThe runner must exit cleanly.\n' >> "$TMP/bad/r10/references/ref.md"
run "$TMP/bad/r10"
assert_eq "10 " "$(rules_of "$out")" "rule 10: only rule 10 fires"
assert_eq "10:candidate:SKILL.md:10
10:candidate:SKILL.md:11
10:candidate:SKILL.md:12
10:candidate:references/ref.md:5" "$(summary "$out")" "rule 10: one candidate per line, in SKILL.md and linked files"
assert_contains "$out" "hook candidate: Never commit secrets." "rule 10: message is the trimmed line"
assert_not_contains "$out" '"status": "fail"' "rule 10: candidates are never fails"

bad r10word
printf '\nThe mustard is neverland-colored.\n' >> "$TMP/bad/r10word/SKILL.md"
run "$TMP/bad/r10word"
assert_eq "" "$(summary "$out")" "rule 10: matches whole words only"

# === rule 11: evals ===========================================================
bad r11few
printf '{"evals": [{"p": 1}]}\n' > "$TMP/bad/r11few/evals/evals.json"
run "$TMP/bad/r11few"
assert_eq "11 " "$(rules_of "$out")" "rule 11: only rule 11 fires on too few evals"
assert_contains "$out" "evals/ has 1 entries" "rule 11: message carries the count"

bad r11list
printf '[{"p": 1}, {"p": 2}, {"p": 3}]\n' > "$TMP/bad/r11list/evals/evals.json"
run "$TMP/bad/r11list"
assert_eq "" "$(summary "$out")" "rule 11: top-level list of 3 passes"

bad r11files
rm "$TMP/bad/r11files/evals/evals.json"
touch "$TMP/bad/r11files/evals/a.txt" "$TMP/bad/r11files/evals/b.txt"
run "$TMP/bad/r11files"
assert_contains "$out" "evals/ has 2 entries" "rule 11: without evals.json it counts files"
touch "$TMP/bad/r11files/evals/c.txt"
run "$TMP/bad/r11files"
assert_eq "" "$(summary "$out")" "rule 11: three files pass"

bad r11none
rm -r "$TMP/bad/r11none/evals"
run "$TMP/bad/r11none"
assert_eq "11 " "$(rules_of "$out")" "rule 11: missing evals/ fails"
assert_contains "$out" "evals/ has 0 entries" "rule 11: missing dir reports zero"

# === rule 13: reasoning echo ==================================================
bad r13
printf '\nAsk the model to think step by step before answering.\n' >> "$TMP/bad/r13/SKILL.md"
run "$TMP/bad/r13"
assert_eq "13 " "$(rules_of "$out")" "rule 13: only rule 13 fires"
assert_contains "$(summary "$out")" "13:candidate:SKILL.md:10" "rule 13: candidate reported with its line"

# === rule 1: backtick references =============================================
bad tick
sed -i.bak 's#Read \[the reference\](references/ref.md) for details.#Read `references/ref.md` for details.#' "$TMP/bad/tick/SKILL.md"; rm "$TMP/bad/tick/SKILL.md.bak"
run "$TMP/bad/tick"
assert_eq "" "$(summary "$out")" "rule 1: a backticked path makes the file reachable"

bad tickmiss
printf '\nExample: `references/nope.md` shows the shape.\n' >> "$TMP/bad/tickmiss/SKILL.md"
run "$TMP/bad/tickmiss"
assert_eq "" "$(summary "$out")" "rule 1: a backticked path to a missing file is not a fail"

bad tickscan
sed -i.bak 's#\[the reference\](references/ref.md)#`references/ref.md`#' "$TMP/bad/tickscan/SKILL.md"; rm "$TMP/bad/tickscan/SKILL.md.bak"
printf '\nYou must run it.\nThink step by step.\n' >> "$TMP/bad/tickscan/references/ref.md"
run "$TMP/bad/tickscan"
assert_eq "10 13 " "$(rules_of "$out")" "rules 10/13: a backtick-reached file is scanned"

bad tickroot
printf '\nSee `references/ref.md` and `references/ref.md`.\n' >> "$TMP/bad/tickroot/references/ref.md"
printf '# Other\n' > "$TMP/bad/tickroot/references/other.md"
printf '\nAlso `references/other.md` here.\n' >> "$TMP/bad/tickroot/references/ref.md"
run "$TMP/bad/tickroot"
assert_contains "$out" "other.md is linked only from references/ref.md" "rule 1: root-relative backtick path in a nested file resolves"

bad exempt
printf '# Readme\n' > "$TMP/bad/exempt/README.md"
printf '# Lic\n' > "$TMP/bad/exempt/LICENSE.md"
printf '# Agents\n' > "$TMP/bad/exempt/AGENTS.md"
printf '# Claude\n' > "$TMP/bad/exempt/CLAUDE.md"
printf '# Ratings\n' > "$TMP/bad/exempt/self-rating.md"
run "$TMP/bad/exempt"
assert_eq "" "$(summary "$out")" "rule 1: root README/LICENSE/AGENTS/CLAUDE markdown is exempt from reachability"

# === rule 10: depth, fences ===================================================
bad deep
printf '\nSee [deep](deep.md).\n' >> "$TMP/bad/deep/references/ref.md"
printf '# Deep\n\nYou must stop.\n' > "$TMP/bad/deep/references/deep.md"
run "$TMP/bad/deep"
assert_contains "$(summary "$out")" "10:candidate:references/deep.md:3" "rule 10: a candidate two links deep is found"

bad fence10
printf '\n```\nNever do this. Think step by step.\n```\n' >> "$TMP/bad/fence10/SKILL.md"
run "$TMP/bad/fence10"
assert_eq "" "$(summary "$out")" "rules 10/13: fenced code is skipped"

# === rule 5: person, false positives ==========================================
desc() {
    # desc <name> <text> — good skill with the given description
    bad "$1"
    python3 - "$TMP/bad/$1/SKILL.md" "$2" <<'PY'
import sys
p, d = sys.argv[1:3]
lines = open(p).read().split("\n")
lines[2] = "description: " + d
open(p, "w").write("\n".join(lines))
PY
}
desc p1 "Audits files. Use when you need to audit."
assert_contains "$(run "$TMP/bad/p1"; echo "$out")" "'you'" "rule 5: plain 'you' is caught"
desc p2 "Audits files. Use when you have a spec."
run "$TMP/bad/p2"; assert_eq "5 " "$(rules_of "$out")" "rule 5: 'you have' is caught"
desc p3 "Audits files. We review our output for us."
run "$TMP/bad/p3"; assert_eq "5 " "$(rules_of "$out")" "rule 5: we/our/us are caught"
desc p4 "Audits files. You're done when it's clean."
run "$TMP/bad/p4"; assert_eq "5 " "$(rules_of "$out")" "rule 5: you're is caught"
desc n1 "Audits CI pipelines and I/O in phase I of my-config.yaml."
run "$TMP/bad/n1"; assert_eq "" "$(summary "$out")" "rule 5: I/O, phase I and my-config.yaml are not first person"
desc n2 "Audits files when a user says \"I want a dashboard\" or 'you decide' or \`my plan\`."
run "$TMP/bad/n2"; assert_eq "" "$(summary "$out")" "rule 5: quoted segments are ignored"
desc n3 "Audits tier I and part I and step I outputs."
run "$TMP/bad/n3"; assert_eq "" "$(summary "$out")" "rule 5: Roman numerals after phase/part/step/tier are ignored"
desc p5 "Audits files. My notes help."
run "$TMP/bad/p5"; assert_eq "5 " "$(rules_of "$out")" "rule 5: 'My ' is first person"

# === frontmatter: BOM, unclosed ===============================================
bad bom
printf '\xef\xbb\xbf' | cat - "$TMP/bad/bom/SKILL.md" > "$TMP/bom.md"; mv "$TMP/bom.md" "$TMP/bad/bom/SKILL.md"
run "$TMP/bad/bom"
assert_eq "" "$(summary "$out")" "frontmatter: a UTF-8 BOM is stripped"

bad unclosed
sed -i.bak '4d' "$TMP/bad/unclosed/SKILL.md"; rm "$TMP/bad/unclosed/SKILL.md.bak"
run "$TMP/bad/unclosed"
assert_contains "$out" "frontmatter has no closing ---" "frontmatter: unclosed fence is named"
assert_not_contains "$out" "missing or empty" "frontmatter: unclosed fence is not reported as a missing description"

# === rule 9: outside the skill ================================================
bad outlink
printf '\nSee [up](../elsewhere.md).\n' >> "$TMP/bad/outlink/SKILL.md"
run "$TMP/bad/outlink"
assert_eq "9 " "$(rules_of "$out")" "rule 9: a link escaping the skill folder fails (and is not rule 1)"
assert_contains "$out" "references a file outside the skill folder: ../elsewhere.md" "rule 9: escape message names the path"

bad outtick
printf '\nSee `../elsewhere.md`.\n' >> "$TMP/bad/outtick/SKILL.md"
run "$TMP/bad/outtick"
assert_eq "9 " "$(rules_of "$out")" "rule 9: a backtick path escaping the skill folder fails"

# === rule 11: malformed evals =================================================
bad badjson
printf '{not json' > "$TMP/bad/badjson/evals/evals.json"
run "$TMP/bad/badjson"
assert_eq "11 " "$(rules_of "$out")" "rule 11: malformed evals.json fails"
assert_contains "$out" "evals/evals.json is not valid JSON:" "rule 11: invalid JSON message"

bad badshape
printf '{"cases": [1, 2, 3]}' > "$TMP/bad/badshape/evals/evals.json"
run "$TMP/bad/badshape"
assert_contains "$out" 'must be a list or {\"evals\": [...]}; found object with keys [cases]' "rule 11: wrong shape names the keys found"
printf '"text"' > "$TMP/bad/badshape/evals/evals.json"
run "$TMP/bad/badshape"
assert_contains "$out" "found str" "rule 11: wrong shape names the type found"

bad hidden
rm "$TMP/bad/hidden/evals/evals.json"
touch "$TMP/bad/hidden/evals/a.txt" "$TMP/bad/hidden/evals/b.txt" "$TMP/bad/hidden/evals/.DS_Store" "$TMP/bad/hidden/evals/.gitkeep"
run "$TMP/bad/hidden"
assert_contains "$out" "evals/ has 2 entries" "rule 11: dotfiles are not counted"

# === rule 0: unreadable files =================================================
bad dangling
ln -s "$TMP/nowhere.md" "$TMP/bad/dangling/references/broken.md"
run "$TMP/bad/dangling"
assert_exit 0 "$code" "rule 0: dangling reference symlink does not crash"
assert_contains "$(summary "$out")" "0:error:references/broken.md:None" "rule 0: error finding names the file"
assert_contains "$out" "could not read references/broken.md" "rule 0: message carries the OS error"

bad dangskill
rm "$TMP/bad/dangskill/SKILL.md"; ln -s "$TMP/nowhere.md" "$TMP/bad/dangskill/SKILL.md"
run "$TMP/bad/dangskill"
assert_exit 0 "$code" "rule 0: dangling SKILL.md does not crash"
assert_eq "0:error:SKILL.md:None" "$(summary "$out")" "rule 0: dangling SKILL.md yields only the error"

mkdir -p "$TMP/mixed"
cp -R "$TMP/good" "$TMP/mixed/ok"; cp -R "$TMP/bad/dangskill" "$TMP/mixed/broken"
run "$TMP/mixed"
assert_exit 0 "$code" "rule 0: folder mode keeps going past a broken skill"
assert_eq "" "$(summary "$out" sample)" "rule 0: the healthy sibling is still linted"

bad evalsperm
ln -sf "$TMP/nowhere.json" "$TMP/bad/evalsperm/evals/evals.json"
run "$TMP/bad/evalsperm"
assert_exit 0 "$code" "rule 0: dangling evals.json does not crash"
assert_eq "0:error:evals/evals.json:None" "$(summary "$out")" "rule 0: dangling evals.json is reported by name and not counted"
assert_contains "$out" "could not read evals/evals.json" "rule 0: dangling evals.json message names the file"

bad danglefile
rm "$TMP/bad/danglefile/evals/evals.json"
touch "$TMP/bad/danglefile/evals/a.txt" "$TMP/bad/danglefile/evals/b.txt"
ln -s "$TMP/nowhere" "$TMP/bad/danglefile/evals/d.txt"
run "$TMP/bad/danglefile"
assert_contains "$out" "evals/ has 2 entries" "rule 11: dangling symlinks are not counted as eval files"

# unreadable directories
if [ "$(id -u)" != 0 ]; then
    bad unreadevals
    chmod 000 "$TMP/bad/unreadevals/evals"
    run "$TMP/bad/unreadevals"
    chmod 755 "$TMP/bad/unreadevals/evals"
    assert_eq "0:error:evals:None" "$(summary "$out")" "rule 0: unreadable evals/ reports one error, not 'has 0 entries'"
    bad unreadref
    chmod 000 "$TMP/bad/unreadref/references"
    run "$TMP/bad/unreadref"
    chmod 755 "$TMP/bad/unreadref/references"
    assert_contains "$(summary "$out")" "0:error:references:None" "rule 0: unreadable references/ is reported by name"
fi

# === description quoting =====================================================
descraw() {
    bad "$1"
    python3 - "$TMP/bad/$1/SKILL.md" "$2" <<'PY'
import sys
p, d = sys.argv[1:3]
lines = open(p).read().split("\n")
lines[2] = "description: " + d
open(p, "w").write("\n".join(lines))
PY
}
descraw q1 'Grants access. Use when the user says "add access", "you decide"'
run "$TMP/bad/q1"; assert_eq "" "$(summary "$out")" "rule 5: trailing quoted phrase is not unwrapped wrongly and stays hidden"
descraw q2 '"I want access" - use for access requests.'
run "$TMP/bad/q2"; assert_eq "" "$(summary "$out")" "rule 5: leading quoted phrase stays hidden"
descraw q3 '"I check files and you review them."'
run "$TMP/bad/q3"; assert_eq "5 " "$(rules_of "$out")" "rule 5: a fully quoted YAML value is unwrapped and still flagged"
descraw q4 'Audits US regions and ME data.'
run "$TMP/bad/q4"; assert_eq "" "$(summary "$out")" "rule 5: ALL-CAPS US/ME are not pronouns"
descraw q5 'Audits files. Let me check them.'
run "$TMP/bad/q5"; assert_eq "5 " "$(rules_of "$out")" "rule 5: 'me' is first person"
descraw q6 'Audits section I, grade I and level I items.'
run "$TMP/bad/q6"; assert_eq "" "$(summary "$out")" "rule 5: Roman numeral after section/grade/level is ignored"

# === link parsing =============================================================
bad refdef
printf '\n[more]: references/more.md\n' >> "$TMP/bad/refdef/SKILL.md"
printf '# More\n' > "$TMP/bad/refdef/references/more.md"
run "$TMP/bad/refdef"
assert_eq "" "$(summary "$out")" "rule 1: a reference-style definition makes the file reachable"
bad refdefmiss
printf '\n[more]: references/gone.md\n' >> "$TMP/bad/refdefmiss/SKILL.md"
run "$TMP/bad/refdefmiss"
assert_contains "$out" "linked file 'references/gone.md' does not exist" "rule 1: a reference-style definition to a missing file fails"

bad span
printf '\nSyntax is `[text](references/gone.md)` in markdown.\n' >> "$TMP/bad/span/SKILL.md"
run "$TMP/bad/span"
assert_eq "" "$(summary "$out")" "rule 1: a link inside an inline code span is ignored"

bad spaces
sed -i.bak 's#(references/ref.md)#(references/my%20ref.md)#' "$TMP/bad/spaces/SKILL.md"; rm "$TMP/bad/spaces/SKILL.md.bak"
mv "$TMP/bad/spaces/references/ref.md" "$TMP/bad/spaces/references/my ref.md"
run "$TMP/bad/spaces"
assert_eq "" "$(summary "$out")" "rule 1: %20 in a link target is decoded"
bad angle
sed -i.bak 's#(references/ref.md)#(<references/my ref.md>)#' "$TMP/bad/angle/SKILL.md"; rm "$TMP/bad/angle/SKILL.md.bak"
mv "$TMP/bad/angle/references/ref.md" "$TMP/bad/angle/references/my ref.md"
run "$TMP/bad/angle"
assert_eq "" "$(summary "$out")" "rule 1: an angle-bracket target with spaces is supported"

# === rule 9: markdown escapes =================================================
bad escape
printf '\nUse snake\\_case.py and a\\*b.md here.\n' >> "$TMP/bad/escape/SKILL.md"
run "$TMP/bad/escape"
assert_eq "" "$(summary "$out")" "rule 9: markdown escapes are not backslash paths"

# === walks: hidden, vendored, symlinked dirs ==================================
bad vendored
mkdir -p "$TMP/bad/vendored/node_modules/x" "$TMP/bad/vendored/.git" "$TMP/bad/vendored/venv"
printf '# V\n' > "$TMP/bad/vendored/node_modules/x/readme.md"
printf '# G\n' > "$TMP/bad/vendored/.git/notes.md"
printf '# P\n' > "$TMP/bad/vendored/venv/notes.md"
run "$TMP/bad/vendored"
assert_eq "" "$(summary "$out")" "walks: hidden and vendored directories are skipped"

bad symdir
mv "$TMP/bad/symdir/references" "$TMP/bad/symdir/shared-refs"
ln -s shared-refs "$TMP/bad/symdir/references"
printf '# Orphan\n' > "$TMP/bad/symdir/shared-refs/orphan.md"
run "$TMP/bad/symdir"
assert_contains "$out" "references/orphan.md is unreachable" "walks: a symlinked references/ directory is followed"
bad symloop
ln -s .. "$TMP/bad/symloop/references/loop"
run "$TMP/bad/symloop"
assert_exit 0 "$code" "walks: a symlink loop terminates"
assert_eq "" "$(summary "$out")" "walks: a symlink loop adds no findings"

# === round 3 ================================================================
bad footnote
printf '\n[^1]: Taken from the upstream docs.\n' >> "$TMP/bad/footnote/references/ref.md"
run "$TMP/bad/footnote"
assert_eq "" "$(summary "$out")" "rule 1: a footnote definition is not a link definition"

bad symup
ln -s ../.. "$TMP/bad/symup/references/up"
run "$TMP/bad/symup"
assert_eq "9:fail:references/up:None" "$(summary "$out")" "rule 9: a symlinked dir escaping upward gives exactly one finding"
assert_contains "$out" "symlinked directory points outside the skill folder: references/up -> ../.." "rule 9: escape message names the link and target"
bad symroot
ln -s / "$TMP/bad/symroot/references/sys"
run "$TMP/bad/symroot"
assert_eq "9:fail:references/sys:None" "$(summary "$out")" "rule 9: a symlink to / is not descended and gives one finding"

bad symskill
mkdir -p "$TMP/real-skill-root"; cp -R "$TMP/good/." "$TMP/real-skill-root/"
ln -s "$TMP/real-skill-root" "$TMP/linked-skill"
run "$TMP/linked-skill"
assert_eq "" "$(summary "$out")" "rule 9: a skill root that is itself a symlink works"
bad syminside
mkdir -p "$TMP/bad/syminside/shared"; printf '# Shared\n' > "$TMP/bad/syminside/shared/s.md"
ln -s ../shared "$TMP/bad/syminside/references/s"
run "$TMP/bad/syminside"
assert_not_contains "$out" "outside the skill folder" "rule 9: a symlinked dir that stays inside the skill is allowed"

bad r9span
printf '\nMatch lines with `^version:\\s*(.*)$` here.\nRun `printf "a\\nb.txt"` now.\n' >> "$TMP/bad/r9span/SKILL.md"
run "$TMP/bad/r9span"
assert_eq "" "$(summary "$out")" "rule 9: backslashes inside inline code spans are ignored"

bad rootreadme
{ printf '# Readme\n\n'; for _ in $(seq 1 120); do echo "row"; done; } > "$TMP/bad/rootreadme/README.md"
run "$TMP/bad/rootreadme"
assert_eq "" "$(summary "$out")" "rule 2: a long root README is not a reference file"

desc w1 "Audits files named we.json and act I output."
run "$TMP/bad/w1"; assert_eq "" "$(summary "$out")" "rule 5: 'we.json' and 'act I' are not first person"

bad symfile
printf '# Outside\n\nYou must obey.\n' > "$TMP/outside-file.md"
ln -s "$TMP/outside-file.md" "$TMP/bad/symfile/references/out.md"
printf '\nSee [out](references/out.md).\n' >> "$TMP/bad/symfile/SKILL.md"
run "$TMP/bad/symfile"
assert_eq "9:fail:references/out.md:None" "$(summary "$out")" "rule 9: a symlinked file escaping the skill gives one finding and is not read"
assert_contains "$out" "symlinked file points outside the skill folder: references/out.md -> $TMP/outside-file.md" "rule 9: file escape message names link and target"
bad symevals
printf '[1]' > "$TMP/outside-evals.json"
rm "$TMP/bad/symevals/evals/evals.json"; ln -s "$TMP/outside-evals.json" "$TMP/bad/symevals/evals/evals.json"
run "$TMP/bad/symevals"
assert_eq "9:fail:evals/evals.json:None" "$(summary "$out")" "rule 9: an evals.json symlinked outside the skill is not read"
bad syminfile
printf '# In\n' > "$TMP/bad/syminfile/shared.md"
ln -s ../shared.md "$TMP/bad/syminfile/references/in.md"
printf '\nSee [in](references/in.md).\n' >> "$TMP/bad/syminfile/SKILL.md"
run "$TMP/bad/syminfile"
assert_not_contains "$out" "outside the skill folder" "rule 9: a symlinked file that stays inside the skill is allowed"

# === folder-of-skills mode ====================================================
mkdir -p "$TMP/multi"
cp -R "$TMP/good" "$TMP/multi/alpha"
cp -R "$TMP/bad/r11none" "$TMP/multi/beta"
mkdir -p "$TMP/multi/not-a-skill"
sed -i.bak 's/^name: sample/name: alpha/' "$TMP/multi/alpha/SKILL.md"; rm "$TMP/multi/alpha/SKILL.md.bak"
sed -i.bak 's/^name: sample/name: beta/' "$TMP/multi/beta/SKILL.md"; rm "$TMP/multi/beta/SKILL.md.bak"
run "$TMP/multi"
assert_exit 0 "$code" "folder mode exits 0"
count=$(printf '%s' "$out" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["skills"]))')
assert_eq "2" "$count" "folder mode reports only directories holding SKILL.md"
assert_eq "" "$(summary "$out" alpha)" "folder mode: alpha is clean"
assert_eq "11:fail:evals:None" "$(summary "$out" beta)" "folder mode: beta carries its own finding"

# === usage errors =============================================================
run "$TMP/does-not-exist"
assert_exit 2 "$code" "bad path exits 2"
assert_contains "$err" "usage" "bad path explains on stderr"
mkdir -p "$TMP/empty"
run "$TMP/empty"
assert_exit 2 "$code" "folder with no skills exits 2"
assert_contains "$err" "no skills found" "no-skills error on stderr"
run
assert_exit 2 "$code" "no argument exits 2"

finish
