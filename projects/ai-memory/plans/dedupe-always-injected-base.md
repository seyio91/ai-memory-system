---
plan: dedupe-always-injected-base
status: in_progress
created: 2026-10-07
owner: claude (orchestrator)
task_provider: local
task_ref: deduplicate-the-always-injected-base-identity-orchestrator-harness-claude-md
---

# Deduplicate the always-injected base

Initiative `memory-md-hygiene`, Target `ai-memory/dedupe-base`. Findings: investigation `memory-md-audit-2026-10` (System findings #4). Revised 2026-10-07 after a three-explorer review of the injection pipeline, install/migration path and doctrine consumers.

## Goal

Split orchestrator doctrine into a tracked, release-updated core plus a gitignored local overlay. State each rule once across the base, reduce the Claude harness CLAUDE.md to a hook-failure stub, and point rarely-used detail at the docs that already hold it, so every harness gets the same current doctrine at a smaller size.

## Success criteria

- [ ] Always-loaded base on this instance (`identity.md` + core + overlay + Claude stub) is ≤ 18 KB, down from ~31 KB (`wc -c`). If P1's measurement shows the core alone cannot land under ~14 KB, stop and re-scope before P2.
- [ ] Across core + overlay + stub, each of these is stated exactly once (grep): executor deny-list, the three task tiers, the TaskCreate ban, the archive rule. Counting `identity.md`, the deny-list appears exactly twice.
- [ ] The "Small items inline" text is gone from every base file.
- [ ] `templates/orchestrator.template.md` no longer exists; `doctrine/orchestrator.md` is tracked; `orchestrator.local.md` and `orchestrator.md.pre-*` are gitignored; `/orchestrator.md` stays ignored.
- [ ] A rendered session payload for Claude (xml), Codex (md) and Antigravity (xml, via `preinvocation.sh`) contains `orchestrator` then `orchestrator-local`, in that order; the breadcrumb lists `orchestrator-local:`; `check-memory-size.sh --payload` reports no ERROR for `ai-memory`, and its pre-filter counts core + overlay.
- [ ] Legacy fallback: with a root `orchestrator.md` present and no `orchestrator.local.md`, the root file is injected as `orchestrator-local` and the breadcrumb carries a one-line deprecation; with both present, the overlay wins and the root file is ignored.
- [ ] The memory-maintenance rules (update immediately, where entries go, checkpoint rhythm, promote, wiki-page offer, reorganize trigger), the plan-mode-nudge rule and the skills-authoring rule appear in the core and not in the Claude stub. The stub's fallback line is imperative and names both doctrine files.
- [ ] The core keeps, verbatim in intent: the `--which` decision tree and the run-`--run`-in-background rule; the Task Contract core rule (draft criteria, surface before executing, never start blank); the validator brief fields `scope:` / `risk:` / `hypotheses:`; the heading names `Brainstorm gate`, `Task Contract`, `Cross-project relationships`, `Orchestration`.
- [ ] The migration `migrations/1.6.0-orchestrator-core-overlay.sh`, run twice on a fixture holding a full-copy `orchestrator.md`, produces identical trees: one `.pre-1.6.0` backup, an empty-seeded overlay, a printed notice; an existing overlay is never overwritten; an existing backup is never clobbered.
- [ ] `UPGRADING.md` has `## 1.6.0` (`test_upgrading_doc.sh` green); a `changelog.d/<id>.upgrade.md` fragment exists; no fragment of kind `breaking`.
- [ ] A test pins the dedupe: `doctrine/orchestrator.md` byte ceiling and the grep-once invariants from criterion 2. Its file name contains `orchestrator-core-overlay` so `run-tests.sh --changed` maps the migration to it.
- [ ] Precedence (`identity` > overlay > core > project memory) is stated consistently in all eight places listed under Design → Precedence sites.
- [ ] `bash scripts/run-tests.sh` passes (with the local signing overrides); the lint WARN *set* compared before and after shows no new WARN caused by this change; `check-docs.sh` passes.
- [ ] No stale references remain: `grep -rn 'orchestrator.template' --exclude-dir=projects --exclude-dir=.git .` matches only CHANGELOG/UPGRADING history; `grep -rn '~/.claude-memory/orchestrator.md'` matches nothing outside history.

## Design

**Layers (stated precedence):** `identity.md` > `orchestrator.local.md` (overlay) > `doctrine/orchestrator.md` (tracked core) > project memory. The overlay is *additive with stated precedence*: the model sees both files and a markdown overlay cannot delete core text, exactly as identity > orchestrator works today and as `scripts/deny-list.txt` + `deny-list.local.txt` already do.

- **Tracked core — `doctrine/orchestrator.md`.** Built from the current template (the newer doctrine: validator Part B, risk tiers, round cap, shared-state criteria, decision-stream / stream-first rules). Deduplicated: deny-list once, pointing at `scripts/deny-list.txt`; tiers once; TaskCreate ban one line (`block_task_tools.sh` enforces it on Claude). Gains: the `design-brainstorm` vs `grilling` gate; the memory-maintenance rules from CLAUDE.md:34-48; CLAUDE.md:5 (ignore harness plan-mode/TaskCreate nudges) and CLAUDE.md:29 (never author skills in `~/.claude/skills/`), which exist nowhere else. The "enforced after every write" claim at CLAUDE.md:42 is reworded — the write guard is hand-wired on this machine only, until `install-guards` ships it. Ships with every tag, so all four harnesses update on sync. Adopting the template is a behaviour change for this instance (it lacked the validator brief fields).
- **Local overlay — `orchestrator.local.md`** (gitignored, `config.local.sh` convention). Personal additions only. This instance's overlay carries the `git-cli` rule.
- **On-demand detail → existing docs, no new file.** Task Contract detail already lives in `docs/workflow.md:45-52`; executor env-var/config/fallback detail in `docs/workflow.md:66-81`, `docs/scripts.md`, `templates/config.local.sh.example`. The reorganize-memory procedure moves from CLAUDE.md:52-61 into `docs/knowledge-lifecycle.md` (`docs/workflows.md:80` re-pointed). The core keeps a one-line rule + pointer for each. Validator mechanics stay in `agents/validator.md`. A never-injected `doctrine/orchestrator-detail.md` was dropped: zero lint coverage, one more file to drift, and the content already has homes.
- **Injection.** `content-core.sh` reads `orchestrator` from `doctrine/orchestrator.md`; new `orchestrator-local` kind, presence-gated, ordered directly after `orchestrator`. **Every kind-list and formatter arm must change, because unknown kinds are silently dropped:** `scripts/content-core.sh:16,128-129`; `scripts/hooks/lib.sh:107-108` (full) and `:283-284` (breadcrumb); `harnesses/antigravity/hooks/preinvocation.sh:40,42`; `scripts/formatters/xml.sh:10,23-26,65`; `scripts/formatters/md.sh:20-21,51`; `scripts/check-memory-size.sh:341`. Legacy fallback (N/N+1 rule in `migrations/README.md`): a root `orchestrator.md` with no overlay is injected as `orchestrator-local` plus a breadcrumb deprecation line, so a consumer who `git pull`s without `/sync-system` keeps their doctrine. Known, unchanged: `scripts/build-context-md.sh:39` omits `orchestrator` today.
- **Claude stub — `harnesses/claude/CLAUDE.md`** (~1 KB, Claude-only, reached via the `@`-import shim). Floor rules plus an imperative fallback: "if `<memory:orchestrator>` is absent from context, read `doctrine/orchestrator.md` and `orchestrator.local.md` now." `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` is set globally on this machine and `skills/load-memory` claims it suppresses SessionStart `additionalContext`; the current session receives the payload via UserPromptSubmit chunks, so the claim is unverified — P3 spikes it before relying on the stub. Codex's hand-owned `~/.codex/AGENTS.md` is out of scope.
- **Migration — `migrations/1.6.0-orchestrator-core-overlay.sh`** (version from `assemble-changelog.sh --bump`: 12 feature + 6 fix fragments → 1.6.0; the fragment for this PR is `upgrade`, never `breaking`). If root `orchestrator.md` exists: move to `orchestrator.md.pre-1.6.0` unless that backup exists (then leave both and say so); seed an empty `orchestrator.local.md` only if absent; print a notice to port personal rules. Idempotent, forward-only. `install.sh:247` seeds the empty overlay instead of copying the template; `:263` reworded.
- **Precedence sites (all eight):** `doctrine/orchestrator.md` header, `harnesses/claude/CLAUDE.md`, `docs/file-formats.md:13-14`, `README.md:11`, `templates/identity.template.md:4,37-38`, `skills/load-memory/SKILL.md:12` (local), `docs/showcase.md:87`, `docs/workflow.md` (add; it does not state it today).

**Rejected alternatives**
- Per-instance full copy + drift lint: drift still fixed by hand on every instance; template fixes never reach consumers.
- Drift out of scope: the dedupe lands in a file that keeps drifting; the audit finding recurs.
- One merged injected block: precedence invisible; size checks cannot budget separately.
- A real override/merge mechanism: markdown has none; prose precedence is what the system already uses.
- Detail into slash commands: command delivery differs per harness (codex gets a doc; copilot/antigravity unverified).
- A new `doctrine/orchestrator-detail.md`: unlinted, duplicate of `docs/workflow.md`.
- Auto-diff migration: the live copy is both ahead of and behind the template; a script cannot judge it.
- Delete CLAUDE.md outright: no fallback when the hook fails.
- No legacy fallback: a raw `git pull` would silently stop injecting an edited `orchestrator.md`.

## Decisions (locked)

- Overlay is additive with stated precedence; identity wins over both.
- Two injected blocks: `orchestrator` (core) then `orchestrator-local` (overlay).
- Deny-list copies in the base: `identity.md` + one in core; CLAUDE.md copy and second orchestrator copy dropped. Shrinking to a pointer waits for `install-guards`.
- `git-cli` rule → this instance's overlay; `grilling` gate → core.
- Migration = backup + empty overlay + notice; no auto-diff; legacy fallback in code for one release.
- No `doctrine/orchestrator-detail.md`; detail points at existing docs.
- Version 1.6.0; fragment kind `upgrade`.

## Phases

### Phase 1 — Author the core
Create `doctrine/orchestrator.md` from the template; dedupe; add the grilling gate, maintenance rules, plan-mode and skills-authoring lines; reword the write-guard claim; replace env-var/Task-Contract/reorganize detail with one-line rules + pointers to `docs/workflow.md` / `docs/knowledge-lifecycle.md`; keep the load-bearing items listed in criterion 8; keep heading names. Move the reorganize procedure into `docs/knowledge-lifecycle.md`. Delete the template. Add the dedupe-pinning test (byte ceiling + grep-once).
**Verify:** `wc -c doctrine/orchestrator.md` ≤ ~14 KB (gate — stop and re-scope if not); grep-once counts hold on the core alone; template gone; `grep -c 'scope:' doctrine/orchestrator.md` ≥ 1; new test passes.

### Phase 2 — Injection wiring + legacy fallback
Repoint `orchestrator` to `doctrine/orchestrator.md`; add `orchestrator-local` at all seven edit sites (content-core, lib.sh ×2, antigravity preinvocation ×2, xml.sh, md.sh) plus `check-memory-size.sh:341`; implement the legacy fallback and breadcrumb deprecation; `.gitignore` entries; update `test_shared_hooks.sh` (paths at `:17,36,43-52,64,147`) and add cases: overlay present, overlay absent (no block emitted), legacy root file present, both present.
**Depends:** P1
**Verify:** `render-session-payload.sh` for claude, codex and antigravity shows both blocks in order and the breadcrumb line; the four fixture cases pass; `check-memory-size.sh --payload ai-memory` clean.

### Phase 3 — Claude stub + sbp spike
Spike: with `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`, confirm whether SessionStart `additionalContext` is suppressed and whether the UserPromptSubmit chunk path still delivers the full payload; record the answer in the plan. Rewrite `harnesses/claude/CLAUDE.md` to the ~1 KB stub with the imperative fallback; update `block_task_tools.sh:20` path; update `docs/harnesses/claude.md:90-96,134`, `harnesses/claude/manifest:24` comment.
**Depends:** P1
**Verify:** `wc -c harnesses/claude/CLAUDE.md` ≤ ~1.2 KB; no maintenance rule, tier text or deny-list remains in it; spike result written down; `test_install_harness.sh` passes.

### Phase 4 — Migration, install, release notes, docs
Add `migrations/1.6.0-orchestrator-core-overlay.sh` with backup-collision guard; `install.sh:247,263`; `UPGRADING.md` `## 1.6.0` (+ fix the 1.4.0 note at `:166-173`); `changelog.d/<id>.upgrade.md`; migration test (fixture, run twice, existing overlay, existing backup); `test_install_harness.sh` (add `doctrine/` to the fake repo at `:18-21`; rewrite `:27,105-106,128-133` for overlay seeding / no-overwrite). Docs: `docs/install.md` (lines 40-52, 59, 80-106, 119, 162), `docs/file-formats.md:5-14`, `docs/workflow.md` (add precedence; `:47,87,105`), `docs/harnesses/codex.md:59`, `docs/harnesses/antigravity.md:88`, `docs/showcase.md:86-87`, `docs/workflows.md:80`, `docs/knowledge-lifecycle.md:37,56`, `README.md:11,29,147-166`, `templates/identity.template.md:4,37-38`, `commands/new-plan.md:28,44,69`, `commands/start.md:24`.
**Depends:** P2
**Verify:** migration test green (idempotent, overlay untouched, backup not clobbered); `test_upgrading_doc.sh` and `check-docs.sh` pass; both stale-reference greps clean; `assemble-changelog.sh --bump` still prints 1.6.0.

### Phase 5 — Instance cutover + full validation
At a session boundary: run the migration here; port the `git-cli` rule into `orchestrator.local.md`; fix local `skills/load-memory/SKILL.md` (read both doctrine files; use `.agents/memory-project`); append `D7-proposed` to `initiatives/memory-md-hygiene.md` ("doctrine = tracked core + local overlay; per-instance `orchestrator.md` retired"); measure every criterion; full suite; compare lint WARN sets; render live payloads.
**Depends:** P3, P4
**Verify:** every box in `## Success criteria` ticked with evidence (sizes, grep counts, payload excerpts, suite summary line, D7 line present).

## Risks / open questions

- Deny-list shrink to a pointer deferred until `install-guards` gives Claude a guard hook.
- Copilot/antigravity slash-command delivery unverified; pointing detail at `docs/` avoids depending on it.
- Size: Claude payload is 77.5 KB / 9 chunks and `projects/ai-memory/memory.md` (45 KB) dominates; this plan saves ~5 KB. The wins are drift elimination and cross-harness maintenance rules, not chunk count. The ≤ 18 KB base target is tight — P1 gates it.
- The sbp-profile suppression claim is unverified; if true, the stub fallback is the only always-loaded doctrine on this machine.
- A consumer who edited their full-copy `orchestrator.md` keeps it injected via the legacy fallback for one release; after that, only the backup and notice remain (by design, no auto-diff).
- Live sessions read doctrine from the tree; P5 changes the running doctrine mid-instance — do it at a session boundary.
- `memory_write_guard.sh` and `build-context-md.sh`'s missing `orchestrator` are pre-existing gaps surfaced here; both out of scope (`install-guards` owns the first).
