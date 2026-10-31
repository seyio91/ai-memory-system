---
plan: require-python3-and-fail-guard-closed
status: done
completed: 2026-11-01
created: 2026-10-31
owner: claude (orchestrator)
task_provider: local
task_ref: guard-no-parser-path-should-fail-closed-in-bypass-mode
---

# Require python3 >= 3.9 and fail the guard closed when no parser is found

## Goal
Make python3 >= 3.9 an explicit, preflight-checked requirement (it already is one in practice), and have `scripts/hooks/guard.sh` deny in every context when no JSON parser is found, rather than failing open for the main session, which let deny-listed commands run in bypass mode.

## Success criteria
1. `install.sh` exits non-zero with an actionable message, changing nothing, when `python3` is absent or older than 3.9. It proceeds as today on 3.9 or later.
2. `scripts/sync-system.sh` runs the same check **before** any checkout, merge or migration, and aborts with the tree untouched when it fails.
3. The check is one shared function (in `scripts/_lib.sh`). It is not duplicated.
4. `guard.sh` with no jq/python3 on PATH denies (exit 2, reason "no jq/python3" on stderr) in main-session, subagent and executor contexts alike. `test_shared_hooks.sh` asserts the main-session deny, replacing the old fail-open asserts.
5. The other `guard_fail` paths (missing or empty deny-list) keep their current main-session fail-open behaviour. This plan doesn't change them.
6. New tests in `test_install_harness.sh` and the sync tests drive a stub `python3` that reports 3.8, and a PATH with no `python3`, and assert the abort and that nothing changed. Each one is mutation-checked: disable the check and the test fails.
7. README, `docs/install.md` (a Prerequisites section) and the guard description in docs state the requirement and the new no-parser behaviour. `scripts/check-docs.sh` passes.
8. `changelog.d/require-python3.breaking.md` exists, and `assemble-changelog.sh --check` passes.
9. The full `bash scripts/run-tests.sh` (with the signing overrides) is green.

## Design
- **Shared preflight** `require_python3` in `scripts/_lib.sh`: `command -v python3` plus `python3 -c 'import sys; sys.exit(sys.version_info < (3,9))'`. On failure it prints the found version (or "not found") and a fix hint, then returns non-zero.
- **`install.sh`** calls it right after argument parsing, before harness resolution or any write.
- **`sync-system.sh`** calls it before the dirty-tree check and the checkout, so a failing machine never ends up at a new ref with unreinstalled wiring.
- **`guard.sh`**: the no-parser branch calls `deny` directly instead of `guard_fail`, matching `harnesses/antigravity/hooks/pretooluse.sh`. Update the header comment.
- Rejected: grepping the raw input for `bypassPermissions`/`dontAsk` and denying only there. That keeps a fail-open path in a state that now means "broken install", and leaves three hook variants behaving differently.
- Rejected: preflight in `install.sh` only. `sync-system.sh` would fail after the checkout.

## Decisions (locked)
- Floor is 3.9 (revised 2026-10-31 from 3.11). Only the TOML scripts (`resolve-skills.sh`, `install-skill.sh`, `list-skills.sh`) need 3.11 for `tomllib`, and they carry their own check; install, sync without `--update`, taskctl, lint and the hooks run on 3.9 (verified on macOS CLT 3.9.6). The guard fix only needs a parser.
- The changelog kind is `breaking` (major bump): install and sync now refuse machines with no python3 (or < 3.9) that they used to accept.
- `jq` stays optional.
- `memory_write_guard.sh` stays fail-open, so editing never breaks.

## Phases

### Phase 1 — shared preflight in install.sh and sync-system.sh
`require_python3` in `_lib.sh`, called from both entry points, with stub-python tests for each.
**Verify:** criteria 1, 2, 3 and 6 pass; the targeted test files are green.

### Phase 2 — guard no-parser path denies everywhere
Change `guard.sh`'s no-parser branch to `deny`, update the header comment, and flip the asserts at `test_shared_hooks.sh` (~L456–462) to expect exit 2 for the main session.
**Verify:** criteria 4 and 5 pass, and `test_shared_hooks.sh` is green.

### Phase 3 — docs, changelog, full gate
**Depends:** P1, P2
README, `docs/install.md` Prerequisites, the guard docs (`docs/workflow.md` / `docs/harnesses/claude.md`, wherever the no-parser fail-open is described), and the changelog fragment.
**Verify:** criteria 7, 8 and 9 pass.

## Risks / open questions
- **Deferred:** the statuslines (claude/copilot/antigravity) still require `jq`. Possible follow-up: a python3 fallback.
- **Deferred:** the no-python3 fallbacks in `scripts/drivers/hook.sh` (manual statusLine instructions) and `scripts/list-skills.sh` become dead code. Removing them, plus the matching `test_install_harness.sh` case, is a separate cleanup.
- Hermetic test PATHs: any existing test that runs `install.sh` or `sync-system.sh` under a scrubbed PATH without python3 will now abort. Find them in P1 and give them a real python3.
- Machines with no python3 (or < 3.9) will hit the abort on their next `/sync-system`. The breaking note must give the fix.
