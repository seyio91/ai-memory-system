#!/usr/bin/env bash
# Sandbox test for migrations/3.0.0-initiative-format.sh. Fixtures are modelled
# on real vault-eks shapes. MIGRATION_3_0_0 points the test at a mutated copy
# for mutation proofs.
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
- next_actor: inception (project session) — P4 non-prod/prod/cde per the runbook, after each env's Vault is initialised
- status: open — Okta OIDC app per environment with group gating (no CLI callback, D1)

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
- status: closed 2026-09-30 — abandoned after the spike

### Closed

| Target | Closed | Jira | Outcome |
|---|---|---|---|
| eps/zero | 2026-09-02 | EPS-0 | shipped |

## Closure

Closed 2026-09-30.
IN
printf '# Progress log — shut\n\n## 2026-09-15 — eps/one\n\nhand entry\n' > "$I/logs/shut.md"
cp "$I/logs/shut.md" "$ROOT/shutlog.orig"

# --- two next_actor lines; labels that end a Progress segment (live shapes) ------
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
- next_actor: inception (project session) — P4 per the runbook
- next_actor: orchestrator (project session)
- status: open — Okta app per environment (D1). Progress: staging P1 done 2026-11-16 (inception#2259 merged). Next, in eks: write the root beside that `backend.tf`. Admin sets temporary `VAULT_TOKEN`. P2 done 2026-11-16: variable set moved. Remaining: P4 non-prod/prod/cde under each env's deploy ticket

### zeta/addon
- execution_mode: interactive
- task: zeta-addon
- depends_on: none
- next_actor: orchestrator (project session)
- status: open — staging port. Progress: P1 merged; P2 merged. Staging port complete; next: non-prod/prod/cde. Seed: k8s-addons investigation `vault-addon-estate-port`.

## Closure

Open.

## Decision stream

- D1 confirmed 2026-10-01 — Okta app per environment.
  evidence: user 2026-10-01
IN
cp "$I/multi.md" "$ROOT/multi.orig"
chmod 640 "$I/multi.md"

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
assert_contains "$body" $'- scope: Okta OIDC app per environment with group gating (no CLI callback, D1)\n- status: open · next: inception (project session) — P4 non-prod/prod/cde per the runbook, after each env\'s Vault is initialised · blocked_by: none\n' "next_actor with an action carries into next:"
assert_contains "$body" $'- task: beta-config-root\n- scope: (staging) — waiting on beta/addon; owner to confirm\n- status: blocked · next: none · blocked_by: none\n' "next_actor none -> next: none; (…) middle kept in scope"
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
assert_contains "$body" $'### Closed\n\n| Target | Closed | Jira | Outcome |\n|---|---|---|---|\n| alpha/proof | 2026-10-19 | ABC-10, ABC-11 (container ABC-1) | see log |\n| alpha/naming | - | ABC-12 | see log |\n| gamma/old-build | - | - | see log |\n\n## Closure' "Closed table at the end of Targets with date, jira and see log"
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
assert_contains "$mb" "- status: open · next: inception (project session) — P4 per the runbook · blocked_by: none" "first next_actor value becomes next:"
assert_contains "$ml" $'## 2026-11-17 — zeta/two (migrated by 3.0.0)\n\n- next_actor: inception (project session) — P4 per the runbook\n- next_actor: orchestrator (project session)\n\nProgress: staging P1 done 2026-11-16 (inception#2259 merged).\n' "all next_actor lines and the Progress segment go to the log"
# Labels end a Progress segment; the rest stays in scope
assert_contains "$mb" "- scope: Okta app per environment (D1). Next, in eks: write the root beside that \`backend.tf\`. Admin sets temporary \`VAULT_TOKEN\`. P2 done 2026-11-16: variable set moved. Remaining: P4 non-prod/prod/cde under each env's deploy ticket" "'Next, in eks:' label ends the Progress segment; trailing prose and 'Remaining:' stay in scope"
assert_contains "$mb" "- scope: staging port. Seed: k8s-addons investigation \`vault-addon-estate-port\`." "'Seed:' label ends the Progress segment"
assert_contains "$ml" $'Progress: P1 merged; P2 merged. Staging port complete; next: non-prod/prod/cde.' "a lower-case 'next:' inside a sentence does not end the segment"
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
assert_contains "$gb" "- scope: 2026-11-16" "dated middle: date carried into scope"
assert_not_contains "$gb" "- status: open (asserted) " "(...) middle: old status line converted"
assert_contains "$gb" "- scope: (asserted) — prose" "(...) middle: kept in scope"

# No MEMORY_DIR/initiatives: nothing to do
mkdir -p "$ROOT/empty"
rc=0; MEMORY_DIR="$ROOT/empty" REPO_ROOT="$REPO_ROOT" bash "$MIG" || rc=$?
assert_exit 0 "$rc" "no initiatives directory exits 0"

finish
