---
plan: install-guards
status: in_progress
created: 2026-10-08
owner: claude (orchestrator)
task_provider: local
task_ref: install-memory-write-guard-and-a-claude-deny-list-guard-via-the-manifest
---

# Install the memory write guard and a Claude deny-list guard via the manifest

## Goal

Ship the memory write guard and a Claude deny-list guard through `install.sh`, so every Claude instance gets both from the manifest instead of a hand-wired `settings.json` entry. Then shrink the doctrine's inline deny-list to a pointer at `scripts/deny-list.txt`, with `executor.sh` injecting the list into CLI executor prompts.

## Success criteria

- [ ] `harnesses/claude/manifest` declares `infra_guard = PreToolUse:Bash` (→ `guard_script`) and `memory_write_guard = PostToolUse:Write|Edit` (→ new key `write_guard_script`); `validate-manifest.sh` accepts the new key; `test_hook_mapping.sh` pins the Claude role list.
- [ ] Installing into a `settings.json` seeded with this instance's hand-wired write-guard entry leaves **exactly one** write-guard entry and **exactly one** guard entry (`test_install_harness.sh`), and preserves unrelated hooks and keys.
- [ ] A swept native (Claude/Codex) entry whose command, matcher or extra keys differ from what install writes is printed verbatim with the `.bak` path; identical entries are swept silently; a retired-marker match (`inject_memory.sh`, `arm_recompact.sh`) is reported as `removed (retired hook)`. Each case has a test.
- [ ] `AI_MEMORY_GUARD_SCOPE` (config, default `executor`) is baked into Claude's guard command by install. With the default, `guard.sh` with no role exits 0 (consumers unchanged). With `all`: a deny-listed Bash call **from a subagent** (`agent_id` present) is denied (exit 2); **from the main session** (no `agent_id`) it returns `permissionDecision: "ask"`; a non-matching call passes. Tests for each.
- [ ] Guard failure modes: with a role set, a missing deny-list or no JSON parser still denies; in main-session `all` mode the same failures exit 0 with a visible warning. Tests for both.
- [ ] Codex, Copilot and Antigravity guard behaviour is unchanged (their existing guard tests are green with no edits to their expectations).
- [ ] `executor.sh --run` prepends the deny-list (`scripts/deny-list.txt` + `scripts/deny-list.local.txt` if present) to every CLI executor prompt, for every role, ahead of the validator preamble; tested.
- [ ] `doctrine/orchestrator.md` states the deny-list by pointer only (no command list), the delegation rule says CLI prompts get the list from `executor.sh` and subagent prompts paste it from the file; `test_orchestrator_core_overlay.sh` anchors updated; `docs/workflow.md` and the other docs naming the doctrine as the list's home are repointed.
- [ ] `AI_MEMORY_GUARD_SCOPE` is in the `docs/scripts.md` env-var table (`check-docs.sh` passes) and in `config.local.sh.example`; a `changelog.d/<id>.feature.md` fragment exists; no `breaking` fragment.
- [ ] Full suite green (signing overrides); lint WARN set unchanged; `check-docs.sh` clean.
- [ ] Post-merge, this instance: `AI_MEMORY_GUARD_SCOPE="all"` in `config.local.sh`, `/sync-system`, then `~/.claude/settings.json` has one write-guard and one guard entry and no hand-wired copy; a live `terraform apply` from the main session prompts, and from a subagent is denied.

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
- Q3: main session gets `ask`, subagents/executors get `deny`. **Reopens** "block every session" → "confirm in the main session".
- Q4: write-guard bypass via Bash is deferred (Risks).
- Q5: the sweep report covers the native merge (Claude/Codex) only.
- Q6: retired-marker sweeps are reported as `removed (retired hook)`.

## Phases

### Phase 1 — Guard scope, deny/ask split, failure modes
`scripts/hooks/guard.sh`: `AI_MEMORY_GUARD_SCOPE` gate; `agent_id` → deny vs `ask` JSON; failure paths split by executor/subagent vs main session. Tests in the guard test file for each case, plus the unchanged default.
**Verify:** guard tests cover default-scope no-op, `all`+subagent deny, `all`+main ask, non-match pass, both failure modes in both contexts; existing Codex/Copilot/Antigravity guard tests unchanged and green.

### Phase 2 — Manifest roles, install mapping, sweep report
`harnesses/claude/manifest` roles + `write_guard_script`/`guard_script`; `validate-manifest.sh` `KNOWN_KEYS`; `hook.sh` role table, marker, scope baked from config, report-on-diff (native merge) incl. retired markers; `config.local.sh.example`; `docs/scripts.md` env-var row.
**Depends:** P1
**Verify:** `test_install_harness.sh` proves one write-guard + one guard entry after install over a seeded hand-wired entry, silent sweep for identical entries, verbatim report + `.bak` path for a customised one, retired-hook report; `test_hook_mapping.sh` pins Claude roles; `check-docs.sh` clean.

### Phase 3 — Executor deny-list preamble
`scripts/executor.sh --run` prepends the deny-list preamble for all roles, ahead of the validator preamble.
**Verify:** executor test asserts the preamble (base + local rules) precedes the prompt for task/explore/validate and that the validator preamble still follows it.

### Phase 4 — Doctrine pointer, docs, release notes
`doctrine/orchestrator.md` list → pointer and revised delegation rule; `test_orchestrator_core_overlay.sh` anchors; `docs/workflow.md`, `docs/harnesses/*.md`, `README.md`/`docs/showcase.md` where they describe the list's home or Claude's guard; `changelog.d/install-guards.feature.md`.
**Depends:** P2, P3
**Verify:** no command list remains in `doctrine/orchestrator.md`; grep finds no doc naming the doctrine as the list's home; fragment present; full suite green, lint WARN set unchanged, `check-docs.sh` clean.

### Phase 5 — Instance cutover (post-merge)
Set `AI_MEMORY_GUARD_SCOPE="all"` in `config.local.sh`, `/sync-system`, inspect `~/.claude/settings.json`, live-test main-session ask and subagent deny.
**Depends:** P4 (merged)
**Verify:** last success criterion, with the `settings.json` excerpt and both live outcomes recorded here.

## Risks / open questions

- Write guard is bypassed by Bash writes (`sed -i`, `cat >>`, `python3`) to memory files; only `Write|Edit` is seen. Settling it needs a cheap way to attribute a Bash call to a file write.
- Write guard for Codex and the other harnesses: each harness's PostToolUse payload must be checked first.
- Heredoc false positives (`cat > f <<EOF … helm upgrade … EOF`) remain; the main session pays one confirmation, executors are denied. A matcher that distinguishes heredoc-to-file from heredoc-to-shell is a separate change.
- `agent_id`/`agent_type` presence in Claude's PreToolUse payload is from the hooks docs, not yet observed here; P5's live subagent test is what confirms it. If absent, every call looks like the main session and subagents get `ask` instead of `deny`.
- Doctrine shrink means a subagent-plane delegation relies on the orchestrator pasting the list; the hook is the enforcing layer there.
