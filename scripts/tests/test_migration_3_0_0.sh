#!/usr/bin/env bash
# Sandbox test for migrations/3.0.0-initiative-format.sh. Fixtures are
# synthetic; they keep the shapes the migration handles (long prose,
# Progress:/Was: segments, sentence labels, next_actor actions, #123 refs).
# MIGRATION_3_0_0 points the test at a mutated copy for mutation proofs.
. "$(dirname "$0")/_assert.sh"
set -euo pipefail

REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
MIG="${MIGRATION_3_0_0:-$REPO_ROOT/migrations/3.0.0-initiative-format.sh}"
ROOT="$(new_sandbox)"
trap 'rm -rf "$ROOT"' EXIT
TODAY=2026-11-17

M="$ROOT/mem"
I="$M/initiatives"
mkdir -p "$I/archive" "$I/.state" "$I/logs"

assert_same() { if cmp -s "$1" "$2"; then _ok "$3"; else _bad "$3"; fi; }
run_mig() { MEMORY_DIR="$M" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY="$TODAY" bash "$MIG"; }

# --- the main fixture -------------------------------------------------------
cat > "$I/old.md" <<'IN'
---
kind: initiative
slug: old
status: active
created: 2026-10-07
---

# Old initiative

## Objective

Prove the thing. A fenced example stays as written:

```text
### x/y
- status: open — x
- next_actor: human
```

## Decision stream

- D1 confirmed 2026-10-01 — Base rule — evidence: user 2026-10-01.
- D2 confirmed 2026-10-02 — Second rule — evidence: user 2026-10-02.
- D3 superseded 2026-10-03 — Old consumption via referent auth — evidence: user.
- D4 confirmed 2026-10-04 — New consumption reuses the namespace identity (user 2026-10-04; follows D3, amends D1/D2).
  evidence: user 2026-10-04
  SUPERSEDES D3
- D5 confirmed 2026-10-05 — Port rule (amends D2).
  evidence: user 2026-10-05

## Targets

Jira: epic ABC-1; every ticket maps to a Target jira: line.

```text
### x/y
- status: open — x
```

### alpha/proof
- jira: ABC-10, ABC-11 (container ABC-1)
- execution_mode: interactive
- task: prove-alpha-in-the-sandbox
- depends_on: none
- next_actor: orchestrator (project session)
- status: done 2026-10-19 — sandbox proof completed (plan archived); remediation done. Was: prove alpha on the sandbox

### alpha/naming
- jira: ABC-12
- execution_mode: interactive
- depends_on: alpha/proof
- next_actor: orchestrator (project session)
- status: done — convention decided (D1); consumer module shipped

### beta/addon
- jira: ABC-20
- execution_mode: interactive
- task: port-beta-addon
- depends_on: alpha/proof, alpha/naming
- next_actor: orchestrator (project session)
- status: open — staging DONE 2026-11-17 (P1–P7 verified; ABC-20 closeable); non-prod ports next (ABC-21/22, notify per D2). Progress: P1 certificates merged; P2 chart values merged. Was: port the addon to staging only. Progress: P3 validated with run-xyz 15/0/0

### beta/workspaces
- jira: ABC-30
- execution_mode: interactive
- task: beta-workspaces
- depends_on: alpha/proof
- next_actor: builder (project session) — P4 dev/test/live per the runbook, after each env's store is seeded
- status: open — login app per environment with role gating (no CLI callback, D1)

### beta/config
- execution_mode: interactive
- depends_on: beta/addon
- next_actor: none
- task: beta-config-root
- status: blocked (staging) — waiting on beta/addon; owner to confirm

### gamma/old-build
- execution_mode: software_adw
- task: gamma-old-build
- depends_on: none
- next_actor: orchestrator (project session)
- status: done — built and shipped

### gamma/pipeline
- execution_mode: software_adw
- task: gamma-pipeline
- depends_on: gamma/old-build
- next_actor: orchestrator (project session)

## Closure

Open.
IN
cp "$I/old.md" "$ROOT/old.orig"
# Staleness snapshot naming the software_adw Target that gets collapsed.
printf '%s\n' '# initiative-status snapshot' 'gamma/old-build done' 'gamma/pipeline unknown' 'stream-entries 5' > "$I/.state/old.snapshot"
cp "$I/.state/old.snapshot" "$ROOT/old.snapshot.orig"

# --- a file with a line the migration cannot match ------------------------------
cat > "$I/odd.md" <<'IN'
---
kind: initiative
slug: odd
status: active
created: 2026-10-07
---

# Odd

## Targets

### delta/fine
- execution_mode: interactive
- task: delta-fine
- depends_on: none
- next_actor: human
- status: open — fine prose

### delta/weird
- execution_mode: interactive
- depends_on: none
- next_actor: orchestrator (project session)
- status: in flight — something odd

### delta/legacy
- execution_mode: interactive
- depends_on: none
- status: done (no dash)

## Closure

Open.

## Decision stream

- D1 confirmed 2026-10-01 (weird) — malformed head.
- D2 confirmed 2026-10-02 — replaces D1.
  SUPERSEDES D1
IN

# --- a closed initiative with an existing log -----------------------------------
cat > "$I/shut.md" <<'IN'
---
kind: initiative
slug: shut
status: closed
created: 2026-09-01
topics: [infra]
---

# Shut

## Targets

### eps/one
- jira: EPS-1
- execution_mode: interactive
- depends_on: none
- next_actor: none
- status: done 2026-09-30 — shipped after the spike

### Closed

| Target | Closed | Jira | Outcome |
|---|---|---|---|
| eps/zero | 2026-09-02 | EPS-0 | shipped |

## Closure

Closed 2026-09-30.
IN
printf '# Progress log — shut\n\n## 2026-09-15 — eps/one\n\nhand entry\n' > "$I/logs/shut.md"
cp "$I/logs/shut.md" "$ROOT/shutlog.orig"

# --- two next_actor lines; labels that end a Progress segment -----------------
cat > "$I/multi.md" <<'IN'
---
kind: initiative
slug: multi
status: active
created: 2026-10-07
---

# Multi

## Targets

### zeta/two
- execution_mode: interactive
- task: zeta-two
- depends_on: none
- next_actor: builder (project session) — P4 per the runbook
- next_actor: orchestrator (project session)
- status: open — login app per environment (D1). Progress: staging P1 done 2026-11-16 (toolbox#123 merged). Next, in repo: write the root beside that `backend.tf`. Admin sets temporary `API_TOKEN`. P2 done 2026-11-16: variable set moved. Remaining: P4 dev/test/live under each env's deploy ticket

### zeta/addon
- execution_mode: interactive
- task: zeta-addon
- depends_on: none
- next_actor: orchestrator (project session)
- status: open — staging port. Progress: P1 merged; P2 merged. Staging port complete; next: dev/test/live. Seed: tooling investigation `widget-port-notes`.

## Closure

Open.

## Decision stream

- D1 confirmed 2026-10-01 — Login app per environment.
  evidence: user 2026-10-01
IN
cp "$I/multi.md" "$ROOT/multi.orig"
chmod 640 "$I/multi.md"

# --- an abandoned (closed) Target with a dependent; a done Target beside it -----
cat > "$I/aband.md" <<'IN'
---
kind: initiative
slug: aband
status: active
created: 2026-10-07
---

# Aband

## Targets

### eta/spike
- jira: ETA-1
- execution_mode: interactive
- depends_on: none
- next_actor: builder (project session) — write up the spike
- status: closed 2026-10-20 — abandoned; the approach did not scale. Progress: P1 prototype merged (toolbox#123). Remaining: nothing

### eta/build
- execution_mode: interactive
- depends_on: eta/spike
- next_actor: orchestrator (project session)
- status: open — build on the spike result

### eta/docs
- jira: ETA-3
- execution_mode: interactive
- depends_on: none
- next_actor: none
- status: done 2026-10-21 — written

### eta/retired
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: closed

### eta/after
- execution_mode: interactive
- depends_on: eta/docs, eta/retired
- status: open · next: human — check · blocked_by: none

## Closure

Open.

## Decision stream

- D1 confirmed 2026-10-01 — Spike first.
  evidence: user 2026-10-01
IN

# --- things that must not be touched -------------------------------------------
cp "$ROOT/old.orig" "$I/_template.md"
cp "$ROOT/old.orig" "$I/archive/arch.md"
cp "$ROOT/old.orig" "$ROOT/outside.md"
ln -s "$ROOT/outside.md" "$I/link.md"
sed 's/kind: initiative/kind: note/' "$ROOT/old.orig" > "$I/notinit.md"
cp "$I/notinit.md" "$ROOT/notinit.orig"

rc=0; out="$(run_mig)" || rc=$?
assert_exit 0 "$rc" "migration exits 0 (unmatched content is reported, not fatal)"
got="$I/old.md"
log="$I/logs/old.md"
body="$(cat "$got")"
logbody="$(cat "$log")"

# Backup
assert_same "$ROOT/old.orig" "$I/.state/old.pre-3.0.0.md" "backup is byte-identical to the input"
assert_contains "$out" "backup: $I/.state/old.pre-3.0.0.md" "backup is reported"

# Open Targets: scope + one-line status, next_actor removed
assert_contains "$body" $'- task: port-beta-addon\n- depends_on: alpha/proof, alpha/naming\n- scope: staging DONE 2026-11-17 (P1–P7 verified; ABC-20 closeable); non-prod ports next (ABC-21/22, notify per D2).\n- status: open · next: orchestrator (project session) · blocked_by: none\n' "open status: prose to scope minus Progress/Was, next from next_actor"
assert_contains "$body" $'- scope: login app per environment with role gating (no CLI callback, D1)\n- status: open · next: builder (project session) — P4 dev/test/live per the runbook, after each env\'s store is seeded · blocked_by: none\n' "next_actor with an action carries into next:"
assert_contains "$body" $'- task: beta-config-root\n- scope: (staging) waiting on beta/addon; owner to confirm\n- status: blocked · next: none · blocked_by: none\n' "next_actor none -> next: none; (…) middle leads the scope, no dash"
assert_not_contains "$(sed '/^```/,/^```/d' "$got")" "next_actor" "no next_actor line left outside fences"
assert_contains "$body" $'### gamma/pipeline\n- execution_mode: software_adw\n- task: gamma-pipeline\n- depends_on: gamma/old-build\n\n' "software_adw Target with no status stays without status"
assert_contains "$logbody" $'## 2026-11-17 — gamma/pipeline (migrated by 3.0.0)\n\n- next_actor: orchestrator (project session)' "statusless Target's next_actor goes to the log"

# Progress/Was segments to the log
assert_contains "$logbody" $'## 2026-11-17 — beta/addon (migrated by 3.0.0)\n\nProgress: P1 certificates merged; P2 chart values merged.\n\nWas: port the addon to staging only.\n\nProgress: P3 validated with run-xyz 15/0/0\n' "Progress/Was segments are log entries tagged with the Target id"

# Fenced blocks untouched
assert_eq "2" "$(grep -c -x -- '- status: open — x' "$got")" "fenced '- status: open — x' lines untouched"
assert_eq "2" "$(grep -c -x -- '### x/y' "$got")" "fenced '### x/y' lines untouched"
assert_contains "$body" $'```text\n### x/y\n- status: open — x\n- next_actor: human\n```' "fenced block in Objective byte-identical"

# Closed rows; collapsed blocks verbatim in the log
assert_contains "$body" $'### Closed\n\n| id | closed | jira | outcome |\n|---|---|---|---|\n| alpha/proof | 2026-10-19 | ABC-10, ABC-11 (container ABC-1) | see log |\n| alpha/naming | - | ABC-12 | see log |\n| gamma/old-build | - | - | see log |\n\n## Closure' "Closed table at the end of Targets with date, jira and see log"
assert_not_contains "$body" "### alpha/proof" "collapsed Target heading removed"
blk="$(sed -n '/^### alpha\/proof$/,/^- status:/p' "$ROOT/old.orig")"
assert_contains "$logbody" $'## 2026-11-17 — alpha/proof (migrated by 3.0.0)\n\n'"$blk"$'\n' "collapsed Target block goes to the log verbatim"
blk="$(sed -n '/^### alpha\/naming$/,/^- status:/p' "$ROOT/old.orig")"
assert_contains "$logbody" "$blk" "undated done Target block in the log"
assert_eq "5" "$(grep -c '(migrated by 3.0.0)$' "$log")" "log entries: 3 collapsed blocks + 1 Progress/Was set + 1 statusless next_actor"
assert_contains "$out" "old.md: 4 Target(s) converted, 3 collapsed into Closed rows, 5 log entr(ies), 1 forward pointer(s) added" "per-file counts reported"
assert_contains "$logbody" "# Progress log — old" "log created with a header"

# Decision stream: pointer added, nothing else edited
assert_contains "$body" $'\n- D3 superseded 2026-10-03 → D4 — Old consumption via referent auth — evidence: user.\n' "SUPERSEDES adds → D4 to D3's head"
for id in D1 D2 D4 D5; do
    assert_eq "$(grep -- "^- $id " "$ROOT/old.orig")" "$(grep -- "^- $id " "$got")" "decision $id head untouched"
done
assert_contains "$out" "candidate: D4 amends D1 — add an AMENDS line by hand" "prose 'amends D1/D2' reported (D1)"
assert_contains "$out" "candidate: D4 amends D2 — add an AMENDS line by hand" "prose 'amends D1/D2' reported (D2)"
assert_contains "$out" "candidate: D5 amends D2 — add an AMENDS line by hand" "prose '(amends D2)' reported"
assert_not_contains "$body" "AMENDS" "no AMENDS line written"

# Frontmatter
assert_eq "kind: initiative|slug: old|status: active|created: 2026-10-07|topics: []|---" \
    "$(sed -n '2,7p' "$got" | tr '\n' '|' | sed 's/|$//')" "topics: [] added before the closing frontmatter fence"
assert_not_contains "$(sed -n '1,8p' "$got")" "envs:" "envs: not added"

# No word lost: every word of every old status / next_actor value is in the file or log
lost=""
while IFS= read -r line; do
    for w in $line; do
        printf '%s\n%s\n' "$body" "$logbody" | grep -qF -- "$w" || lost="$lost $w"
    done
done < <(sed -n 's/^- status: //p; s/^- next_actor: //p' "$ROOT/old.orig")
assert_eq "" "$lost" "no word of old status prose or next_actor is lost"

# The migrated file is valid
rc=0; MEMORY_DIR="$M" bash "$REPO_ROOT/scripts/initiative-status.sh" --tsv old >/dev/null 2>&1 || rc=$?
assert_exit 0 "$rc" "initiative-status.sh accepts the migrated file"
assert_contains "$body" "<!-- BEGIN AUTOGEN initiative-render:now -->" "Now fence inserted"
assert_contains "$body" "<!-- BEGIN AUTOGEN initiative-render:rules -->" "Current rules fence inserted"
rc=0; MEMORY_DIR="$M" bash "$REPO_ROOT/scripts/initiative-render.sh" old --check >/dev/null 2>&1 || rc=$?
assert_exit 0 "$rc" "initiative-render.sh --check exits 0 after migration"
assert_contains "$out" "old.md: fences written" "fence insertion reported"
lint="$(MEMORY_DIR="$M" bash "$REPO_ROOT/scripts/lint-memory.sh" 2>&1 || true)"
assert_contains "$lint" "initiatives/old.md Target 'beta/addon' next: has no ' — ' action part" "lint ran on the migrated file (thin next: WARNs as expected)"
assert_not_contains "$(printf '%s\n' "$lint" | grep 'initiatives/old.md' || true)" "ERROR" "migrated file has no lint ERROR"
assert_not_contains "$lint" "unresolved Target id 'alpha/proof'" "depends_on to a collapsed Target still resolves"
assert_not_contains "$lint" "unresolved Target id 'gamma/old-build'" "depends_on to a collapsed software_adw Target resolves"

# Collapsing a software_adw Target raises no stale alert; the snapshot is untouched
assert_same "$ROOT/old.snapshot.orig" "$I/.state/old.snapshot" "migration leaves the staleness snapshot untouched"
st="$(MEMORY_DIR="$M" bash "$REPO_ROOT/scripts/initiative-status.sh" old 2>&1 || true)"
assert_not_contains "$st" "Stale targets" "collapsed software_adw Target raises no stale alert"

# Unmatchable line: reported with its line number, left byte-identical
odd="$I/odd.md"
assert_contains "$out" "unmatched line left unchanged (fix by hand): $odd:24: - status: in flight — something odd" "unmatchable status reported with line number"
assert_eq "- status: in flight — something odd" "$(sed -n 24p "$odd")" "reported line number points at the line in the rewritten file"
assert_contains "$out" "$odd:23: - next_actor: orchestrator (project session)" "its next_actor line is reported too"
assert_contains "$(cat "$odd")" $'- next_actor: orchestrator (project session)\n- status: in flight — something odd\n' "unmatched Target left byte-identical"
assert_contains "$(cat "$odd")" $'- scope: fine prose\n- status: open · next: human · blocked_by: none\n' "the matchable Target in the same file is converted"
assert_contains "$out" "odd.md: fences skipped" "a file still refused by initiative-status.sh skips fences and says so"
assert_not_contains "$(cat "$odd")" "AUTOGEN" "no fences written to a refused file"

# Closed initiative migrated; row appended to the existing Closed table; existing log appended
shut="$(cat "$I/shut.md")"
assert_contains "$shut" $'| eps/zero | 2026-09-02 | EPS-0 | shipped |\n| eps/one | 2026-09-30 | EPS-1 | see log |\n' "closed initiative: row appended to the existing Closed table"
assert_not_contains "$shut" "### eps/one" "closed initiative: Target collapsed"
assert_eq "1" "$(grep -c '^### Closed' "$I/shut.md")" "no second Closed section"
assert_eq "1" "$(grep -c '^topics:' "$I/shut.md")" "existing topics: kept, not duplicated"
assert_eq "$(cat "$ROOT/shutlog.orig")" "$(head -n "$(wc -l < "$ROOT/shutlog.orig")" "$I/logs/shut.md")" "existing log bytes kept as prefix (append-only)"
assert_contains "$(cat "$I/logs/shut.md")" "## 2026-11-17 — eps/one (migrated by 3.0.0)" "existing log gets the new entry"

# Abandoned (closed) Target: keeps its heading with a standalone closed status,
# is not a Closed row, and does not satisfy its dependent; done still collapses
ab="$(cat "$I/aband.md")"; al="$(cat "$I/logs/aband.md")"
assert_contains "$ab" $'### eta/spike\n- jira: ETA-1\n- execution_mode: interactive\n- depends_on: none\n- scope: 2026-10-20 abandoned; the approach did not scale. Remaining: nothing\n- status: closed\n' "abandoned Target keeps its heading; scope gets the prose; status: closed stands alone"
assert_not_contains "$ab" "| eta/spike |" "abandoned Target is not a Closed row"
assert_contains "$ab" $'### Closed\n\n| id | closed | jira | outcome |\n|---|---|---|---|\n| eta/docs | 2026-10-21 | ETA-3 | see log |\n' "done Target still collapses into the Closed table"
assert_not_contains "$ab" "### eta/docs" "done Target heading removed"
assert_contains "$ab" $'### eta/retired\n- execution_mode: interactive\n- depends_on: none\n- status: closed\n' "new-format closed Target with a stray next_actor keeps its heading"
assert_not_contains "$ab" "| eta/retired |" "new-format closed Target is not a Closed row"
assert_not_contains "$(sed '/^```/,/^```/d' "$I/aband.md")" "next_actor" "abandoned fixture: no next_actor line left"
assert_contains "$al" $'## 2026-11-17 — eta/spike (migrated by 3.0.0)\n\n- next_actor: builder (project session) — write up the spike\n\nProgress: P1 prototype merged (toolbox#123).\n' "abandoned Target: its single next_actor line and Progress segment go to the log"
assert_contains "$al" $'## 2026-11-17 — eta/retired (migrated by 3.0.0)\n\n- next_actor: human' "new-format closed Target: next_actor goes to the log"
assert_contains "$out" "aband.md: 3 Target(s) converted, 1 collapsed into Closed rows, 3 log entr(ies)" "abandoned fixture counts reported"
tsv="$(MEMORY_DIR="$M" bash "$REPO_ROOT/scripts/initiative-status.sh" --tsv aband 2>/dev/null)"; rc=$?
assert_exit 0 "$rc" "initiative-status.sh accepts the migrated abandoned fixture"
assert_eq "closed" "$(printf '%s\n' "$tsv" | awk -F'\t' '$1 == "eta/spike" { print $7 }')" "--tsv: abandoned Target state is closed"
assert_eq "no" "$(printf '%s\n' "$tsv" | awk -F'\t' '$1 == "eta/build" { print $3 }')" "--tsv: dependent of the abandoned Target is unsatisfied"
assert_eq "eta/spike (at closed)" "$(printf '%s\n' "$tsv" | awk -F'\t' '$1 == "eta/build" { print $6 }')" "--tsv: the unsatisfied edge names the abandoned Target"
assert_eq "no" "$(printf '%s\n' "$tsv" | awk -F'\t' '$1 == "eta/after" { print $3 }')" "--tsv: a dependent of a new-format closed Target stays unsatisfied"
assert_eq "eta/retired (at closed)" "$(printf '%s\n' "$tsv" | awk -F'\t' '$1 == "eta/after" { print $6 }')" "--tsv: the done edge is satisfied, the closed one is not"
rnd="$(MEMORY_DIR="$M" bash "$REPO_ROOT/scripts/initiative-render.sh" aband 2>/dev/null)"
assert_contains "$(printf '%s\n' "$rnd" | sed -n '/^\*\*Blocked\*\*/,$p')" "| eta/build |" "initiative-render.sh lists the dependent of the abandoned Target under Blocked"
assert_not_contains "$(printf '%s\n' "$rnd" | sed -n '/^\*\*Ready\*\*/,/^\*\*Blocked/p')" "eta/build" "the dependent is not Ready"
assert_contains "$out" "aband.md: fences written" "abandoned fixture gets its fences"

# Skipped files
assert_same "$ROOT/old.orig" "$I/_template.md" "_template.md untouched"
assert_same "$ROOT/old.orig" "$I/archive/arch.md" "archive/ untouched"
assert_same "$ROOT/old.orig" "$ROOT/outside.md" "symlink target untouched"
assert_contains "$out" "skipped symlink" "symlink skip reported"
assert_same "$ROOT/notinit.orig" "$I/notinit.md" "non-initiative file untouched"
assert_not_file "$I/.state/_template.pre-3.0.0.md" "no backup for _template.md"
assert_not_file "$I/logs/link.md" "no log for the symlink"

# Grammar-only bad status in a migrated file is reported with its line number
assert_contains "$out" "$odd:29: - status: done (no dash) (status does not match the new grammar (fix by hand))" "grammar-only bad status in a migrated file is reported as unmatched"
assert_contains "$(cat "$odd")" $'- depends_on: none\n- status: done (no dash)\n' "grammar-only bad status left byte-identical"
# SUPERSEDES naming a malformed head
assert_contains "$out" "D2 SUPERSEDES D1, which names a malformed head (left unedited): no pointer added" "SUPERSEDES to a malformed head is named as such"
assert_contains "$(cat "$odd")" $'\n- D1 confirmed 2026-10-01 (weird) — malformed head.\n' "malformed head left unedited"

# Two next_actor lines: first becomes next:, all go to the log, one run converges
mb="$(cat "$I/multi.md")"; ml="$(cat "$I/logs/multi.md")"
assert_not_contains "$mb" "next_actor" "every next_actor line removed"
assert_contains "$mb" "- status: open · next: builder (project session) — P4 per the runbook · blocked_by: none" "first next_actor value becomes next:"
assert_contains "$ml" $'## 2026-11-17 — zeta/two (migrated by 3.0.0)\n\n- next_actor: builder (project session) — P4 per the runbook\n- next_actor: orchestrator (project session)\n\nProgress: staging P1 done 2026-11-16 (toolbox#123 merged).\n' "all next_actor lines and the Progress segment go to the log"
# Labels end a Progress segment; the rest stays in scope
assert_contains "$mb" "- scope: login app per environment (D1). Next, in repo: write the root beside that \`backend.tf\`. Admin sets temporary \`API_TOKEN\`. P2 done 2026-11-16: variable set moved. Remaining: P4 dev/test/live under each env's deploy ticket" "'Next, in repo:' label ends the Progress segment; trailing prose and 'Remaining:' stay in scope"
assert_contains "$mb" "- scope: staging port. Seed: tooling investigation \`widget-port-notes\`." "'Seed:' label ends the Progress segment"
assert_contains "$ml" $'Progress: P1 merged; P2 merged. Staging port complete; next: dev/test/live.' "a lower-case 'next:' inside a sentence does not end the segment"
lost=""
while IFS= read -r line; do
    for w in $line; do
        printf '%s\n%s\n' "$mb" "$ml" | grep -qF -- "$w" || lost="$lost $w"
    done
done < <(sed -n 's/^- status: //p; s/^- next_actor: //p' "$ROOT/multi.orig")
assert_eq "" "$lost" "multi: no word lost"
fmode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
assert_eq "640" "$(fmode "$I/.state/multi.pre-3.0.0.md")" "new backup takes the main file's mode"
assert_eq "640" "$(fmode "$I/logs/multi.md")" "new log takes the main file's mode"
assert_contains "$out" "multi.md: fences written" "multi fixture gets its fences"
assert_eq "644" "$(fmode "$I/logs/shut.md")" "existing log keeps its mode"

# --- idempotency: second run is a byte-for-byte no-op ----------------------------
snap() { for p in "$@"; do cksum < "$p"; done; }
before="$(snap "$got" "$log" "$I/.state/old.pre-3.0.0.md" "$I/shut.md" "$I/logs/shut.md" "$I/.state/shut.pre-3.0.0.md" "$odd" "$I/multi.md" "$I/logs/multi.md")"
lsbefore="$(ls -a "$I" "$I/logs" "$I/.state")"
out2="$(run_mig)"
assert_eq "$before" "$(snap "$got" "$log" "$I/.state/old.pre-3.0.0.md" "$I/shut.md" "$I/logs/shut.md" "$I/.state/shut.pre-3.0.0.md" "$odd" "$I/multi.md" "$I/logs/multi.md")" "second run: main files (incl. two next_actor lines), logs and backups byte-identical"
assert_eq "$lsbefore" "$(ls -a "$I" "$I/logs" "$I/.state")" "second run creates no files"
assert_not_contains "$out2" "old.md" "second run does not report the migrated file"
assert_not_contains "$out2" "backup:" "second run writes no backup"

# An existing backup is never overwritten
printf 'sentinel\n' > "$I/.state/old2.pre-3.0.0.md"
cp "$ROOT/old.orig" "$I/old2.md"
run_mig >/dev/null
assert_eq "sentinel" "$(cat "$I/.state/old2.pre-3.0.0.md")" "existing backup kept"

# A failed main-file write: the log is written first; a rerun converges with no duplicates
F="$ROOT/fail"; mkdir -p "$F/initiatives" "$ROOT/shim"
cp "$ROOT/old.orig" "$F/initiatives/old.md"
cat > "$ROOT/shim/mv" <<SHIM
#!/bin/sh
for a in "\$@"; do last="\$a"; done
[ "\$last" = "$F/initiatives/old.md" ] && { echo "shim: refusing mv to \$last" >&2; exit 1; }
exec /bin/mv "\$@"
SHIM
chmod +x "$ROOT/shim/mv"
rc=0; PATH="$ROOT/shim:$PATH" MEMORY_DIR="$F" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY="$TODAY" bash "$MIG" >/dev/null 2>"$ROOT/fail.err" || rc=$?
assert_eq "1" "$rc" "a failed main-file write exits 1"
assert_contains "$(cat "$ROOT/fail.err")" "cannot write $F/initiatives/old.md" "the failed write is named"
assert_same "$ROOT/old.orig" "$F/initiatives/old.md" "main file unchanged after the failed write"
assert_eq "5" "$(grep -c '(migrated by 3.0.0)$' "$F/initiatives/logs/old.md")" "log written before the main file"
assert_eq "" "$(find "$F/initiatives" -name '.mig-*' -print)" "no temp file left behind"
rc=0; out3="$(MEMORY_DIR="$F" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY=2026-11-18 bash "$MIG")" || rc=$?
assert_exit 0 "$rc" "rerun after the failure exits 0"
assert_eq "5" "$(grep -c '(migrated by 3.0.0)$' "$F/initiatives/logs/old.md")" "rerun (even on a later day) adds no duplicate log entries"
assert_contains "$out3" "0 entr(ies) appended, 5 already present" "rerun reports the entries as already present"
assert_same "$I/logs/old.md" "$F/initiatives/logs/old.md" "log after failure + rerun equals a clean run's log"
assert_same "$I/old.md" "$F/initiatives/old.md" "main file after failure + rerun equals a clean run's result"

# Guards: two status lines, and a non-date/non-(...) middle, are left alone and reported
G="$ROOT/guards"; mkdir -p "$G/initiatives"
cat > "$G/initiatives/guards.md" <<'IN'
---
kind: initiative
slug: guards
status: active
created: 2026-10-07
---

# Guards

## Targets

### g/two
- next_actor: human
- status: open — first
- status: blocked — second

### g/soon
- next_actor: human
- status: open soon — prose

### g/dated
- next_actor: human
- status: open 2026-11-16 — prose

### g/paren
- next_actor: human
- status: open (asserted) — prose
IN
rc=0; gout="$(MEMORY_DIR="$G" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY="$TODAY" bash "$MIG")" || rc=$?
assert_exit 0 "$rc" "guards: migration exits 0"
gf="$G/initiatives/guards.md"
gb="$(cat "$gf")"
assert_contains "$gb" $'### g/two\n- next_actor: human\n- status: open — first\n- status: blocked — second\n' "two status lines: Target left byte-identical"
assert_contains "$gout" "$gf:15: - status: open" "two status lines: first status reported unmatched"
assert_contains "$gout" "$gf:16: - status: blocked" "two status lines: second status reported unmatched"
assert_contains "$gout" "$gf:14: - next_actor: human" "two status lines: next_actor reported unmatched"
assert_contains "$gout" "more than one status line" "two status lines: reason given"
assert_contains "$gb" $'### g/soon\n- next_actor: human\n- status: open soon — prose\n' "non-date middle: Target left byte-identical"
assert_contains "$gout" "$gf:20: - status: open soon" "non-date middle: status reported unmatched"
assert_contains "$gout" "$gf:19: - next_actor: human" "non-date middle: next_actor reported unmatched"
assert_contains "$gout" "is not a date or" "non-date middle: reason given"
assert_not_contains "$gb" "- status: open 2026-11-16" "dated middle: old status line converted"
assert_contains "$gb" $'### g/dated\n- scope: 2026-11-16 prose\n- status: open · next: human · blocked_by: none\n' "dated middle: date leads the scope with no ' — ' separator"
assert_not_contains "$gb" "- status: open (asserted) " "(...) middle: old status line converted"
assert_contains "$gb" "- scope: (asserted) prose" "(...) middle: leads the scope with no ' — ' separator"

# Statuses with no ` — ` in an old Target (it has a next_actor: line): the
# state is the first token, remaining words go to scope verbatim; done collapses
# (date only when the next token is YYYY-MM-DD); closed keeps its heading.
B="$ROOT/bare"; mkdir -p "$B/initiatives"
cat > "$B/initiatives/bare.md" <<'IN'
---
kind: initiative
slug: bare
status: active
created: 2026-10-07
---

# Bare

## Targets

### b/open
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: open

### b/blocked
- execution_mode: interactive
- depends_on: none
- next_actor: none
- status: blocked

### b/vendor
- execution_mode: interactive
- depends_on: none
- next_actor: builder (project session) — chase the vendor
- status: blocked waiting on vendor

### b/dated
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: open 2026-11-16 pending review (see #123)

### b/shipped
- jira: BB-1
- execution_mode: interactive
- depends_on: none
- next_actor: none
- status: done

### b/early
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: done shipped early

### b/when
- jira: BB-3
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: done 2026-11-01 shipped on time

### b/glued
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: done 2026-11-01x

### b/retired
- execution_mode: interactive
- depends_on: none
- next_actor: builder (project session) — write the retirement note
- status: closed retired early, superseded by b/vendor

### b/after
- execution_mode: interactive
- task: b-after
- depends_on: b/retired, b/shipped
- next_actor: human
- status: open

## Closure

Open.

## Decision stream

- D1 confirmed 2026-10-01 — Bare statuses convert.
  evidence: user 2026-10-01
IN
cp "$B/initiatives/bare.md" "$ROOT/bare.orig"
cat > "$B/initiatives/bareodd.md" <<'IN'
---
kind: initiative
slug: bareodd
status: active
created: 2026-10-07
---

# Bare odd

## Targets

### c/fine
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: blocked

### c/progress
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: in progress — half done

### c/partial
- execution_mode: interactive
- depends_on: none
- next_actor: human
- status: open · next: human

## Closure

Open.

## Decision stream

- D1 confirmed 2026-10-01 — Odd statuses stay.
  evidence: user 2026-10-01
IN
rc=0; bout="$(MEMORY_DIR="$B" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY="$TODAY" bash "$MIG")" || rc=$?
assert_exit 0 "$rc" "bare statuses: migration exits 0"
bb="$(cat "$B/initiatives/bare.md")"; bl="$(cat "$B/initiatives/logs/bare.md")"
assert_contains "$bb" $'### b/open\n- execution_mode: interactive\n- depends_on: none\n- status: open · next: human · blocked_by: none\n\n' "bare open: converted, no scope line"
assert_contains "$bb" $'### b/blocked\n- execution_mode: interactive\n- depends_on: none\n- status: blocked · next: none · blocked_by: none\n\n' "bare blocked: converted, next_actor none -> next: none, no scope line"
assert_contains "$bb" $'### b/vendor\n- execution_mode: interactive\n- depends_on: none\n- scope: waiting on vendor\n- status: blocked · next: builder (project session) — chase the vendor · blocked_by: none\n' "'blocked <words>': state is the first token, words go to scope"
assert_contains "$bb" $'- scope: 2026-11-16 pending review (see #123)\n- status: open · next: human · blocked_by: none\n' "'open <date> <words>': words kept verbatim in scope"
assert_contains "$bb" $'### b/retired\n- execution_mode: interactive\n- depends_on: none\n- scope: retired early, superseded by b/vendor\n- status: closed\n' "'closed <words>': keeps its heading, words to scope, status: closed alone"
assert_contains "$bl" $'## 2026-11-17 — b/retired (migrated by 3.0.0)\n\n- next_actor: builder (project session) — write the retirement note' "'closed <words>': its next_actor line goes to the log"
assert_contains "$bb" $'| b/shipped | - | BB-1 | see log |\n| b/early | - | - | see log |\n| b/when | 2026-11-01 | BB-3 | see log |\n| b/glued | - | - | see log |\n' "bare done / done <words> collapse; date only when the next token is a date"
for id in b/shipped b/early b/when b/glued; do
    assert_not_contains "$bb" "### $id" "$id heading removed (collapsed)"
done
assert_contains "$bl" $'## 2026-11-17 — b/early (migrated by 3.0.0)\n\n### b/early\n- execution_mode: interactive\n- depends_on: none\n- next_actor: human\n- status: done shipped early\n' "collapsed 'done <words>' block goes to the log verbatim"
assert_not_contains "$bb" "| b/retired |" "'closed <words>' is not a Closed row"
assert_not_contains "$(sed '/^```/,/^```/d' "$B/initiatives/bare.md")" "next_actor" "bare: no next_actor line left"
assert_contains "$bout" "bare.md: 6 Target(s) converted, 4 collapsed into Closed rows" "bare: counts reported"
assert_not_contains "$bout" "unmatched line left unchanged (fix by hand): $B/initiatives/bare.md:" "bare: no unmatched line in the convertible file"
lost=""
while IFS= read -r line; do
    for w in $line; do
        printf '%s\n%s\n' "$bb" "$bl" | grep -qF -- "$w" || lost="$lost $w"
    done
done < <(sed -n 's/^- status: //p; s/^- next_actor: //p' "$ROOT/bare.orig")
assert_eq "" "$lost" "bare: no word lost"
tsv="$(MEMORY_DIR="$B" bash "$REPO_ROOT/scripts/initiative-status.sh" --tsv bare 2>/dev/null)"; rc=$?
assert_exit 0 "$rc" "bare: initiative-status.sh accepts the result"
assert_eq "closed" "$(printf '%s\n' "$tsv" | awk -F'\t' '$1 == "b/retired" { print $7 }')" "bare: 'closed <words>' Target state is closed"
assert_eq "b/retired (at closed)" "$(printf '%s\n' "$tsv" | awk -F'\t' '$1 == "b/after" { print $6 }')" "bare: dependent of 'closed <words>' stays unsatisfied; the done edge is satisfied"
assert_contains "$bout" "bare.md: fences written" "bare: fences written"
# Statuses whose first token is outside the vocabulary, or a partial new-format
# status, stay unmatched and byte-identical; the file is refused
bo="$B/initiatives/bareodd.md"
assert_contains "$(cat "$bo")" $'- status: blocked · next: human · blocked_by: none\n' "bareodd: the matchable bare status is converted"
assert_contains "$bout" "unmatched line left unchanged (fix by hand): $bo:22: - status: in progress — half done" "'in progress — …' stays unmatched and reported"
assert_eq "- status: in progress — half done" "$(sed -n 22p "$bo")" "'in progress — …' line number points at the line"
assert_contains "$bout" "$bo:28: - status: open · next: human" "partial new-format status with next_actor stays unmatched"
assert_contains "$(cat "$bo")" $'- next_actor: human\n- status: in progress — half done\n' "'in progress' Target left byte-identical"
assert_contains "$(cat "$bo")" $'- next_actor: human\n- status: open · next: human\n' "partial Target left byte-identical"
assert_contains "$bout" "bareodd.md: fences skipped" "bareodd: refused file skips fences"
# Idempotent
before="$(snap "$B/initiatives/bare.md" "$B/initiatives/logs/bare.md" "$bo" "$B/initiatives/.state/bareodd.pre-3.0.0.md")"
lsbefore="$(ls -a "$B/initiatives" "$B/initiatives/logs" "$B/initiatives/.state")"
bout2="$(MEMORY_DIR="$B" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY=2026-11-18 bash "$MIG")"
assert_eq "$before" "$(snap "$B/initiatives/bare.md" "$B/initiatives/logs/bare.md" "$bo" "$B/initiatives/.state/bareodd.pre-3.0.0.md")" "bare: second run byte-identical"
assert_eq "$lsbefore" "$(ls -a "$B/initiatives" "$B/initiatives/logs" "$B/initiatives/.state")" "bare: second run creates no files"
assert_not_contains "$bout2" "bare.md:" "bare: second run does not report the migrated file"
# Recovery route: fix the state word by hand, re-run, the Target converts
sed -i.bak 's/^- status: in progress — half done$/- status: open — half done/; s/^- status: open · next: human$/- status: open/' "$bo"; rm -f "$bo.bak"
rc=0; bout3="$(MEMORY_DIR="$B" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY=2026-11-18 bash "$MIG")" || rc=$?
assert_exit 0 "$rc" "recovery: re-run exits 0"
assert_contains "$(cat "$bo")" $'- scope: half done\n- status: open · next: human · blocked_by: none\n' "recovery: the fixed Target converts on re-run"
assert_contains "$bout3" "bareodd.md: fences written" "recovery: the file now parses and gets its fences"

# A file with only grammar errors (no next_actor, no old-shape status) is not
# rewritten, but each offending status is reported with its line number
Q="$ROOT/gramonly"; mkdir -p "$Q/initiatives"
cat > "$Q/initiatives/gram.md" <<'IN'
---
kind: initiative
slug: gram
status: active
created: 2026-10-07
topics: []
---

# Gram

## Targets

### q/fine
- execution_mode: interactive
- depends_on: none
- status: open · next: human — check · blocked_by: none

### q/vendor
- execution_mode: interactive
- depends_on: none
- status: blocked on vendor reply

## Closure

Open.
IN
cp "$Q/initiatives/gram.md" "$ROOT/gram.orig"
rc=0; qout="$(MEMORY_DIR="$Q" REPO_ROOT="$REPO_ROOT" MIGRATION_3_0_0_TODAY="$TODAY" bash "$MIG")" || rc=$?
assert_exit 0 "$rc" "grammar-only file: migration exits 0"
assert_eq "- status: blocked on vendor reply" "$(sed -n 21p "$Q/initiatives/gram.md")" "grammar-only file: fixture line 21 is the bad status"
assert_contains "$qout" "3.0.0: $Q/initiatives/gram.md:21: status does not match the 3.0.0 grammar; fix by hand (lint ERRORs it)" "grammar-only file: bad status reported with its line number"
assert_eq "1" "$(printf '%s\n' "$qout" | grep -c 'gram.md:')" "grammar-only file: only the bad status is reported"
assert_same "$ROOT/gram.orig" "$Q/initiatives/gram.md" "grammar-only file left byte-identical"
assert_not_file "$Q/initiatives/.state/gram.pre-3.0.0.md" "grammar-only file: no backup"
assert_not_file "$Q/initiatives/logs/gram.md" "grammar-only file: no log"

# No MEMORY_DIR/initiatives: nothing to do
mkdir -p "$ROOT/empty"
rc=0; MEMORY_DIR="$ROOT/empty" REPO_ROOT="$REPO_ROOT" bash "$MIG" || rc=$?
assert_exit 0 "$rc" "no initiatives directory exits 0"

finish
