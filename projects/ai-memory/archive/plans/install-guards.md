---
plan: install-guards
status: done
completed: 2026-10-08
created: 2026-10-08
owner: claude (orchestrator)
task_provider: local
task_ref: install-memory-write-guard-and-a-claude-deny-list-guard-via-the-manifest
---

# Install the memory write guard and a Claude deny-list guard via the manifest

## Goal

Ship the memory write guard and a Claude deny-list guard through `install.sh`, so every Claude instance gets both from the manifest instead of a hand-wired `settings.json` entry. Then shrink the doctrine's inline deny-list to a pointer at `scripts/deny-list.txt`, with `executor.sh` injecting the list into CLI executor prompts.

## Success criteria

- [x] `harnesses/claude/manifest` declares `infra_guard = PreToolUse:Bash` (→ `guard_script`) and `memory_write_guard = PostToolUse:Write|Edit` (→ new key `write_guard_script`); `validate-manifest.sh` accepts the new key; `test_hook_mapping.sh` pins the Claude role list.
- [x] Installing into a `settings.json` seeded with this instance's hand-wired write-guard entry leaves **exactly one** write-guard entry and **exactly one** guard entry (`test_install_harness.sh`), and preserves unrelated hooks and keys.
- [x] A swept native (Claude/Codex) entry whose command, matcher or extra keys differ from what install writes is printed verbatim with the `.bak` path; identical entries are swept silently; a retired-marker match (`inject_memory.sh`, `arm_recompact.sh`) is reported as `removed (retired hook)`. Each case has a test.
- [x] `AI_MEMORY_GUARD_SCOPE` (config, default `executor`) is baked into Claude's guard command by install. With the default, `guard.sh` with no role exits 0 (consumers unchanged). With `all`: a deny-listed Bash call **from a subagent** (`agent_id` present) is denied (exit 2); **from the main session** (no `agent_id`) it returns `permissionDecision: "ask"`; a non-matching call passes. Tests for each.
- [x] Guard failure modes: with a role set **or** a raw `"agent_id"` match in stdin (grep, so it works with no parser), a missing deny-list or no JSON parser still denies; in main-session `all` mode the same failures exit 0 and emit `{"systemMessage": …}` on stdout (the only output Claude shows for a non-blocking hook). Tests for both, including the no-parser subagent case.
- [x] Codex, Copilot and Antigravity guard behaviour is unchanged: the scope var is baked only for the `claude` manifest, `test_codex_hooks.sh:85`'s pinned guard command is untouched, and `test_install_harness.sh` asserts Codex's guard command carries no `AI_MEMORY_GUARD_SCOPE`.
- [x] `executor.sh --run` prepends the deny-list (`scripts/deny-list.txt` + `scripts/deny-list.local.txt` if present) to every CLI executor prompt, for every role, ahead of the validator preamble; a missing/empty `scripts/deny-list.txt` aborts `--run` with exit 1 (fail closed, like the guard); `test_executor.sh`'s byte-for-byte prompt pins (L325, L332) and the standalone-copy test are updated.
- [x] `doctrine/orchestrator.md` states the deny-list by pointer only (no command list), the delegation rule says CLI prompts get the list from `executor.sh` and subagent prompts paste it from the file; `test_orchestrator_core_overlay.sh` anchors updated; `docs/workflow.md` and the other docs naming the doctrine as the list's home are repointed.
- [x] `AI_MEMORY_GUARD_SCOPE` is in the `docs/scripts.md` env-var table (`check-docs.sh` passes) and in `templates/config.local.sh.example`; a `changelog.d/<id>.feature.md` fragment exists and names the write guard as newly active on every Claude install; no `breaking` fragment.
- [x] Full suite green (signing overrides); lint WARN set unchanged; `check-docs.sh` clean.
- [x] Post-merge, this instance: `AI_MEMORY_GUARD_SCOPE="all"` in `config.local.sh`, `/sync-system`, then `~/.claude/settings.json` has one write-guard and one guard entry and no hand-wired copy; a live `terraform apply --help` (denied by the matcher, runs nothing) from the main session prompts, and from a subagent is denied with the guard's reason (not `rtk hook claude`'s); the `ask` outcome is recorded for each permission mode this instance uses (default, `acceptEdits`, bypass, `-p`).

## Design

**Manifest + install (`scripts/drivers/hook.sh`).** Claude's manifest gains the two roles. The native role table maps `memory_write_guard` → `write_guard_script`, with command shape `env MEMORY_DIR=… bash <script>` (same as the hand-wired entry, so this instance's entry is swept silently). `memory_write_guard.sh` joins the sweep markers. Claude's guard command carries `AI_MEMORY_GUARD_SCOPE=<config value>`. The native merge pairs each swept entry with the entry it writes by exact (event, matcher, command, keys); any unpaired swept entry is reported verbatim with the backup path.

**Guard (`scripts/hooks/guard.sh`).** Enforce when `AI_MEMORY_ROLE` is set **or** `AI_MEMORY_GUARD_SCOPE=all`. In `all` mode with no role, the payload's `agent_id` decides: present → deny (exit 2), absent → emit `hookSpecificOutput.permissionDecision: "ask"` JSON (exit 0). Failure paths (no parser, missing/empty deny-list) deny when a role is set or `agent_id` is present, and fail open with a warning in the main session. Default scope `executor` keeps the current role-gated behaviour for every harness.

**Executor (`scripts/executor.sh`).** `--run` builds a deny-list preamble from the spec files and prepends it to the prompt for all roles, using the existing validator-preamble pattern.

**Doctrine.** The inline list is replaced with a pointer to `scripts/deny-list.txt` (+ local); the hook is the control on every plane, the prompt restatement is defence in depth.

**Rejected alternatives**
- Detect subagents to guard executors only: the user chose every session; `agent_id` is used only to choose deny vs ask.
- Drop the role gate in `guard.sh` for every harness: changes interactive Codex/Copilot sessions, outside this task.
- Keep a non-standard swept entry in place: the instance stays off the managed shape until someone acts.
- Drop the prompt restatement: no second layer when a hook is missing on an instance.
- Orchestrator-only restatement (read the file each time): relies on the model remembering; `executor.sh` makes it automatic on the CLI plane.
- Hard-code `all` for every consumer: imposes a global interactive block on every install.

## Decisions (locked)

- Deny-list guard covers every Claude session (main + subagents) on instances that opt in.
- Memory write guard ships to Claude only.
- Install replaces the hand-wired entry, and reports any non-standard entry it sweeps, for all native-merged hooks.
- Enforcement is a per-harness env flag (`AI_MEMORY_GUARD_SCOPE`), not a change to the role gate.
- Doctrine deny-list shrinks to a pointer in this plan; `executor.sh` injects the list into CLI executor prompts.

**Provisional — recommended in the grilling round, not yet explicitly confirmed by the user:**
- Q1: scope is config-driven, engine default `executor`, this instance sets `all`.
- Q2: guard failures deny for executors/subagents, fail open with a warning in the main session.
- Q3 (**resolved in P5, user-confirmed 2026-10-08**): main session gets `ask` only when `permission_mode` is `default`, `plan` or `acceptEdits`; any other mode (incl. `bypassPermissions`) or a missing field denies; subagents/executors always deny. Live test showed Claude silently allows an unshown `ask` in bypass mode. Shipped as PR #126.
- Q4: write-guard bypass via Bash is deferred (Risks).
- Q5: the sweep report covers the native merge (Claude/Codex) only.
- Q6: retired-marker sweeps are reported as `removed (retired hook)`.

## Phases

### Phase 1 — Guard scope, deny/ask split, failure modes
`scripts/hooks/guard.sh`: `AI_MEMORY_GUARD_SCOPE` gate; `agent_id` → deny vs `ask` JSON (`hookSpecificOutput.permissionDecision`, exit 0; allow still prints nothing); subagent detection falls back to a raw `grep -q '"agent_id"'` on stdin so the no-parser path can still deny; main-session fail-open emits `{"systemMessage": …}`. Tests in `scripts/tests/test_shared_hooks.sh` (guard block L277-311) for each case, plus the unchanged default.
**Verify:** guard tests cover default-scope no-op, `all`+subagent deny, `all`+main ask, non-match pass, both failure modes in both contexts; existing Codex/Copilot/Antigravity guard tests unchanged and green.

### Phase 2 — Manifest roles, install mapping, sweep report
`harnesses/claude/manifest` roles + `write_guard_script`/`guard_script`; `validate-manifest.sh` `KNOWN_KEYS`; `hook.sh`: role table (L331-341), a `WRITE_GUARD` prefix in all four prefix-driven places (env list L388-393, prefix tuple L482, info lines L499-503, no-python3 fallback L528-532), sweep marker, scope baked into the guard command **only when `name = claude`** (`$HARNESS`, L10 — the command shape is shared with Codex at L353-355), report-on-diff: collect dropped `(event, matcher, hook)` during cleanup (L440-469), diff against the added set after `add()` (L471-487), with a separate `retired` marker set for the `removed (retired hook)` label; `templates/config.local.sh.example`; `docs/scripts.md` env-var row. `test_install_harness.sh`'s `expected` dict (L163-172) is keyed by event and must become a list to hold two `PreToolUse` groups.
**Depends:** P1
**Verify:** `test_install_harness.sh` proves one write-guard + one guard entry after install over a seeded hand-wired entry, silent sweep for identical entries, verbatim report + `.bak` path for a customised one, retired-hook report; `test_hook_mapping.sh` pins Claude roles; `check-docs.sh` clean.

### Phase 3 — Executor deny-list preamble
`scripts/executor.sh --run` prepends the deny-list preamble for all roles, inserted before the validator block at L257-265; a missing/empty `scripts/deny-list.txt` aborts with exit 1. `test_executor.sh`: rewrite the two prompt pins (L325, L332) and give the standalone-copy test (L335+) a deny-list file.
**Verify:** executor test asserts the preamble (base + local rules) precedes the prompt for task/explore/validate and that the validator preamble still follows it.

### Phase 4 — Doctrine pointer, docs, release notes
`doctrine/orchestrator.md` (L78, L120-126, L201) list → pointer and revised delegation rule; `test_orchestrator_core_overlay.sh` anchors (L37-38) re-pointed at `scripts/deny-list.txt`; docs that name the doctrine as the list's home or describe Claude's hooks: `docs/workflow.md:90,111`, `README.md:106-107`, `docs/install.md`, `docs/showcase.md`, `docs/harnesses/claude.md` (gains both hooks), `docs/harnesses/{codex,antigravity,copilot,adding-a-harness}.md`; `changelog.d/install-guards.feature.md` (names the write guard as newly active for every Claude install).
**Depends:** P2, P3
**Verify:** no command list remains in `doctrine/orchestrator.md`; grep finds no doc naming the doctrine as the list's home; fragment present; full suite green, lint WARN set unchanged, `check-docs.sh` clean.

### Phase 5 — Instance cutover (post-merge)
Set `AI_MEMORY_GUARD_SCOPE="all"` in `config.local.sh`, `/sync-system`, inspect `~/.claude/settings.json` (the `rtk hook claude` PreToolUse:Bash entry coexists — confirm the reason shown is the guard's). Probe with `terraform apply --help` (denied by the matcher, executes nothing): main session → ask, subagent → deny. Record the `ask` outcome under each permission mode this instance uses; if bypass turns `ask` into allow, reopen Q3.
**Depends:** P4 (merged)
**Verify:** last success criterion, with the `settings.json` excerpt and both live outcomes recorded here.

## Risks / open questions

- Write guard is bypassed by Bash writes (`sed -i`, `cat >>`, `python3`) to memory files; only `Write|Edit` is seen. Settling it needs a cheap way to attribute a Bash call to a file write.
- Write guard for Codex and the other harnesses: each harness's PostToolUse payload must be checked first.
- Heredoc false positives (`cat > f <<EOF … helm upgrade … EOF`) remain; the main session pays one confirmation, executors are denied. A matcher that distinguishes heredoc-to-file from heredoc-to-shell is a separate change.
- `agent_id` is documented as present only inside subagent calls (`agent_type` also appears in `--agent` main sessions, so `agent_id` is the right key); P5 confirms it live.
- **`ask` under bypass-permissions / `acceptEdits` / `-p` is unverified** — the hooks docs only say it "escalates to the user". This instance runs in bypass mode; if `ask` resolves to allow there, the main-session guard is a no-op here and Q3 must be reopened (deny instead).
- **Matcher gap, verified:** `gh pr --repo o/r merge 12` and `gh pr -R o/r merge 12` are allowed — `_deny_spec_run_in_filtered` (`deny-match.sh:281-296`) needs the spec words consecutive, and a valued flag between them breaks the run. Captured as a backlog task; this plan names it, does not fix it.
- The matcher tokenizes the literal command string only. Verified allowed: `t=terraform; $t apply`, `terraform $(echo apply)`, `printf "terraform apply" | bash`, `bash -c "$CMD"`, `bash script.sh`, `make deploy`, `python3 -c "subprocess.run([...])"`, `ssh host terraform apply`, `docker run … terraform apply`, `gh api -X PUT …/pulls/N/merge`, plus list gaps (`kubectl replace|create|patch|scale|rollout`, `helm rollback`, `terraform import|taint|state rm`, `terragrunt`/`tofu apply`). These rely on the prompt layer and `identity.md`.
- Paid confirmations in the main session with `all`: `terraform apply --help`, `kubectl apply --dry-run=…`, `helm upgrade --dry-run …`, and any heredoc whose body line *starts* with a listed command (including editing `deny-list.local.txt` via heredoc).
- Doctrine shrink means a subagent-plane delegation relies on the orchestrator pasting the list; the hook is the enforcing layer there.

## Validation evidence (P1–P4, 2026-10-08)

- Per-phase validator verdicts: P1 READY, P2 READY, P3 NOT-READY → fixed (leading `---` would break clap-based `codex exec`) → READY; final pass split into code and docs halves after three stalled runs, both PR-READY; all `decorrelated: no`.
- Full suite `tests: 58 passed, 0 failed` (signing overrides); lint WARN set (90) identical to main's lint on the same tree; `check-docs: 41 rows, 0 findings`; `assemble-changelog.sh --check` rc=0.
- Shipped as PR #125 (`ff8d9e9`, 23 files). Doctrine 13,688 B; always-loaded base 17,391 B.

## Validation evidence (P5, 2026-10-08)

- PR #125 merged (`82d95db`); `AI_MEMORY_GUARD_SCOPE="all"` set in `config.local.sh`; `/sync-system` exit 0, no migrations, no report lines (the hand-wired write guard matched the managed entry byte for byte).
- `~/.claude/settings.json`: exactly one guard (`PreToolUse [Bash]`, `AI_MEMORY_GUARD_SCOPE=all`) and one write guard (`PostToolUse [Write|Edit]`); the only change is the added guard; all other hooks and keys unchanged.
- Probe `gh pr merge --help` (deny-listed, help only): subagent → denied by the guard's reason; main session in `bypassPermissions` → **ran unprompted** although the guard returned `ask` for the same payload. Captured payload confirmed a top-level `permission_mode: "bypassPermissions"`. Fix (deny outside default/plan/acceptEdits) verified live: main session now denied with `permission_mode=bypassPermissions` in the reason. PR #126.
- Follow-up tasks: `deny-match-misses-two-word-specs-split-by-a-valued-flag`, `guard-no-parser-path-should-fail-closed-in-bypass-mode`.
- Post-#126 (`c0e8e19`) live probe on `main`: main session in `bypassPermissions` denied with the mode in the reason.
