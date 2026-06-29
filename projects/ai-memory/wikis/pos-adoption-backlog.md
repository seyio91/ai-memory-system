# POS Adoption Backlog

Living list of features to port from POS into our memory system. Source analysis: [pos-comparison.md](pos-comparison.md). Each item is reframed for *our* architecture — the rule is **derive from a single source of truth, don't add hand-kept files**.

Status: `idea` → `approved` (signed off, not yet planned) → `planned` (plan filed) → `building` → `done` · `rejected` (kept for the rationale).

| # | Feature | Gives us | Effort | Priority | Status |
|---|---------|----------|--------|----------|--------|
| 1 | Handoff `resume_point` in `/checkpoint` | Actionable "open file X, Y is stubbed, start at Z" resume line | XS | High | **approved** |
| 2 | ~~Per-project `QUICK-START.md`~~ | — | — | — | **rejected** |
| 3 | ~~Explicit tiered-loading policy~~ | — | — | — | **rejected** |
| 4 | `validate-skills.sh` static check | CI-grade lint for the skills store (frontmatter/tier/size/placeholders) | S | Med | **approved** |
| 5 | Skill template + partials (`--dry-run` drift) | One-edit propagation of shared skill sections | M | Low | **approved** |
| 6 | Lightweight self-rating feedback | Quantitative signal on which skills to improve | M | Low | **approved** |
| 7 | Two-Path Pattern as a principle | Every scripted action also hand-doable (tool portability) | XS | Low | **approved** |
| 8 | Derived state snapshot (`state.md` / "In Flight") | One on-demand cross-project view of what's active/in-flight | S | High | **approved** |
| 9 | ~~Declarative one-shot onboarding~~ | — | — | — | **rejected** |
| 10 | Skill `tier` frontmatter contract | Machine-checkable target-write boundary; skill owns its whole folder for state | S | High | **approved** |
| 11 | Target-tree post-run boundary check | Auto-enforce that read-only skills don't touch the target/system trees (git-diff) | S | High | **approved** |
| 12 | Skill creator | Scaffold a new skill to our schema (frontmatter + store dir + sections) | M | Med | **approved** |
| 13 | Skill installer / intake pipeline | Normalize an existing/remote skill into our schema, inject blocks, validate, link | M | Med | **approved** |

> **Items 4–6 and 10–13 form one subsystem** — see "Skill subsystem" below for the cross-cutting decisions that bind them.

---

## Details

### 1. Handoff `resume_point` in `/checkpoint`
POS's highest-ROI feature. Our checkpoints capture task/done/next/blockers; POS adds a prose **`resume_point`** ("open `WebhookController.php`, `handleSubscription()` is stubbed, start with `customer.subscription.created`"). Add an explicit `resume:` line to the `/checkpoint` template. **Adapt:** lives in `working.md` checkpoints, not a separate handoff file — we already have the checkpoint surface.

### 4. `validate-skills.sh` static check
POS runs 6 checks (<5s): SKILL.md exists, valid frontmatter, required fields, valid tool names, <500-line flag, no unresolved `{{PLACEHOLDER}}`. We lint *memory* (`/lint-memory`) but have no equivalent for the skills store. Clean, self-contained script. **Adapted checks** (per the harness-agnostic decision): drop POS's "valid tool names" check (we have no `allowed-tools`); instead assert `metadata.tier` ∈ {`target-read-only`, `target-write`}. **No `memory_store` check** — a skill may write anywhere inside its own `skills/<name>/` folder at any time, so there's no declared sub-path to validate. Keep: SKILL.md present, valid frontmatter, required fields, size flag, no stray placeholders.

### 5. Skill template + partials
Shared sections as partials; regenerate; `--dry-run` exits 1 on drift. **Decision: don't build full skill-templating** (POS's own lesson — not before ~15 skills + real duplication; we're at ~13, heterogeneous, low duplication). **Right-sized scope:** a *minimal* partial system covering only the **injectable block** the subsystem actually needs — the self-rating / improvement-loop block (for #6), applied **to first-party skills only** (imported/remote skills get it only on explicit request, per #6c). Not a general template engine. (No "Memory store" partial — the own-folder write rule is implicit, not a declared/templated section.)

### 6. Lightweight self-rating feedback
Skill writes a friction note when it hits a gap → aggregate → signals what to fix. **Decisions:** (a) **workflow-skills only** — skip the reference/knowledge packs (`grafana-oss`, `tempo`, `prometheus`, `claude-api`): there's no execution to rate. Targets: `renovate-manager`, `observability-check`, `fiter-infrastructure-analyzer`, `brainstorming`. (b) Feedback **lands in the skill's own folder** (`skills/<name>/`), not a central dir — aggregation is a `skills/*/` glob (see #10). (c) For **remote/third-party skills, do NOT append the self-rating block by default** — only when the user explicitly requests it. Self-rating is a first-party concern; imported skills stay untouched. *When* requested, still use a **clearly demarcated appended section**, never inline edits, so a re-install from upstream re-applies idempotently (fork-safety). (Our own new skills get the block by default via the creator, #12.) **Caveat:** different axis from the Validator — this is skill *friction/ergonomics*, not output correctness; only worth the tokens on skills run repeatedly.

### 7. Two-Path Pattern as a principle
Everything achievable two ways — script OR hand-edit — producing identical results. We mostly do this already; make it an explicit authoring rule so new scripts (`new-project`, `link-skills`) always keep a manual equivalent.

### 8. Derived state snapshot — "In Flight" view
POS's `.state/snapshot.yaml` aggregates per-context status into one dashboard. **Critical adaptation:** POS hand-maintains `status.yaml` per context (drifts — they admit it). We **derive** instead: `last touched` from file mtime/`git log`, `current goal` from each `memory.md`, `in flight/blocked` from latest `working.md` checkpoint + `todo.md` unchecked count. Generated by the same machinery as `index.md`. Constraints: **on-demand, not auto-injected** (depth-first); it's the lean *awareness* layer, fully compatible with `delegate-don't-load`. Projection pattern per `domain/pluggable-providers.md`.

### 10. Skill `tier` frontmatter contract
Lifts **renovate-manager's existing convention** (the reference implementation — `skills/renovate-manager/renovate-reviews/` + its "Memory store" section + `references/memory.md`) into the shared schema so every skill inherits it. **One** neutral frontmatter field under `metadata:`:
- `tier:` — coarse label, **not a tool array** (a tool array would just be `allowed-tools` cosplay without the enforcement). Enforceable axis is binary: `target-read-only` vs `target-write`.

**No `memory_store` field** (dropped — it would just go stale/undefined). The rule is universal and implicit instead: **a skill may write anywhere inside its own `skills/<name>/` folder, at any time, regardless of tier.** That defines the **three write zones**: (1) target/project tree — gated by `tier`; (2) the skill's **own folder** (`skills/<self>/**`) — always writable, no declaration needed; (3) system memory (`projects/*/memory.md`, `working.md`, `index.md`, *other* skills' dirs) — **off-limits by default**, even though it's in the memory repo. renovate-manager draws all three lines by hand today (L65, L290, L292–306); this generalizes them — minus the declared sub-path, since "own folder" needs no naming.

### 11. Target-tree post-run boundary check
Makes #10's `tier` enforceable, harness-agnostically, via two cheap git diffs after a skill run — no tool introspection, identical for Claude and Codex:
- **Target repo:** `git diff --quiet` → must be clean for a `target-read-only` skill.
- **Memory repo:** diff must be **confined to the skill's own folder `skills/<self>/`** (any path under it) — any change to `projects/`, `working.md`, `index.md`, or *another* skill's dir = violation.

**Decision: automatic per-run** for read-only-tier skills (the diff is near-zero cost), via a lightweight dedicated check — *not* the full Validator, which stays reserved for correctness on state-mutating work. Layers under execpolicy (which floors the destructive class regardless). **Trade-off accepted:** enforcement is *detective* (catches the write after) not *preventive* for the non-destructive write class — fine in our domain, where dangerous writes are execpolicy-covered and untidy ones are git-recoverable.

### 12. Skill creator
Authors a **new** skill to our schema: frontmatter (`name`, `description`, `metadata.tier`, `metadata.compatibility`) and (for workflow skills) the injected self-rating block. The skill is free to use its own `skills/<name>/` folder for state — no declared store dir to scaffold. Ends by running `validate-skills.sh` (#4). POS's `skill-creator` analogue, minus the `allowed-tools`/portable-strip steps we don't use.

### 13. Skill installer / intake pipeline
Takes an **existing** skill (local dir or remote source) and conforms it to our schema before linking. We already have the **link half** (`link-skills.sh` global, `sync-project-skills.sh` project-scoped); the missing piece is **intake/normalize**: `fetch → normalize frontmatter to our schema → validate (#4) → place in skills/<name>/ → link`. **No self-rating injection by default** — imported/remote skills are left as-is; the block is appended only on explicit request (per #6c), and when added it must be a demarcated section so it survives re-install (fork-safety).

---

## Skill subsystem (items 4–6, 10–13)
Items 4–6 and 10–13 are **one subsystem**, not independent features. The cross-cutting decisions that bind them:

1. **Enforcement stays harness-agnostic.** No `allowed-tools` (Claude-only; Codex ignores it). Safety = **execpolicy** (hard floor, destructive class) + **Validator** (correctness on state-mutating work) + the **target-tree git check** (#11, tier boundary). One SKILL.md serves both Claude and Codex unchanged.
2. **renovate-manager is the spec.** It already implements destination-scoped write boundaries + per-skill memory by hand. The subsystem's job is to **generalize its convention into the schema/creator/validator** so every skill gets it by default.
3. **The boundary is destination, not tool.** "Read-only" means *no writes to the target tree* — a review skill still writes its verdict/self-rating, just to its **own folder**. Three zones (#10): target tree (tier-gated), the skill's own `skills/<self>/` folder (writable, no declaration), system memory + other skills' dirs (off-limits).
4. **Skill memory is per-skill, co-located** (anywhere under `skills/<name>/`) — not central, and not a declared sub-path. Aggregation for the improvement loop is a `skills/*/` glob.
5. **Build order:** #10 (schema) → #4 (validate) + #11 (post-run check) → #12/#13 (creator/installer) → #6 (self-rating, on top, workflow-skills only). #5 is a minimal partial mechanism in service of #6/#10/#12, not standalone templating.

---

## Rejected (kept for rationale)
- **Per-project `QUICK-START.md` (POS Tier-1 summary)** — solves POS's problem, not ours. Measured: our auto-injected payload is `identity` (84) + `memory.md` (median ~55) + `working.md` (usually <15) ≈ **~140 lines typical, ~320 worst case** — already POS-Tier-1-sized, so no token payoff. And we have **no tiered-loading gate** to load a lite file *through* (the SessionStart hook injects `memory.md`/`working.md` unconditionally); a QUICK-START would just be a redundant copy unless we first build #3's escalation machinery to save tokens we aren't short on. **Salvage:** its cross-project-lite value → #8 (derived "In Flight" view); its content kernel (Key Files / Commands) → add as a section to the `memory.md` template if ever wanted. **Revisit trigger:** any project's injected payload crossing ~300 lines *after* `working.md` is kept trimmed (today only fiter-infrastructure is near it, due to a bloated 130-line working.md — a checkpoint-hygiene issue, not a tiering one).
- **Explicit tiered-loading policy (POS 3-tier)** — depends on #2 and dies with it: its lite Tier-1 rung *is* the rejected QUICK-START. The remaining rungs already exist and are already governed by `identity.md` — Tier 2 (`memory.md`) is injected unconditionally; Tier 3 (load domain on demand, delegate token-heavy work to subagents, three-task-tiers) is already written there. So #3-minus-#2 = documenting behavior we already have, solving the same token non-problem (base payload ~140 lines). No new mechanism, no payoff.
- **`allowed-tools` per-skill tool grants** — Claude-native, not honored by Codex; breaks the one-SKILL.md-both-harnesses model. Replaced by neutral `metadata.tier` (#10) + the git-diff boundary check (#11) + execpolicy + Validator. *Decision: keep enforcement harness-agnostic.*
- **`metadata.tools: [...]` tool array** — `allowed-tools` cosplay under a different key: same maintenance, no enforcement. The tier is a coarse label, not a tool list.
- **Central skill-feedback store** (POS's `.handoff/feedback/`) — overridden by the established per-skill co-located convention (renovate-manager). Aggregation is a glob, not a reason to centralize.
- **Declarative one-shot onboarding (`new-project.sh` flags)** — not worth it: the agent already populates the frontmatter fields on request, which covers the actual workflow. No batch-onboarding case has come up to justify a manifest. Revisit only if repeated multi-project onboarding becomes a real pain.
- **Central `pos.yaml` registry** — no fan-out/generation payoff for us; duplicates the `projects/` tree; reintroduces the drift we engineered out with a derived `index.md`. (The declarative-fill part is also rejected — see above.)
- **`@shortcut` context switching** — ours is better: switch is implicit from the repo you're in (`.claude/memory-project` pin), no alias to maintain.
- **Full multi-tool portability (Cursor/Windsurf/Copilot)** — POS pays real complexity for breadth our Claude+Codex scope doesn't use.
- **Capability-level task routing** — POS admits it's aspirational; our Orchestrator already picks executor/model per task.
