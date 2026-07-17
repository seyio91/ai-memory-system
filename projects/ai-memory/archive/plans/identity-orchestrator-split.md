---
plan: identity-orchestrator-split
status: done
completed: 2026-07-17
created: 2026-07-16
owner: claude (orchestrator)
task_provider: notion
task_ref: 39ff6850-c619-819b-967f-f368365ec8fa
---

# Split identity.md into identity (voice) + orchestrator (doctrine)

## Goal

Separate the user voice/identity from the orchestration doctrine: `identity.md`
keeps only who the user is (role, stack, style, hard rules, defaults); a new
`orchestrator.md` carries the workflow doctrine (tiers, brainstorm gate,
orchestrator/executor/validator, task contract, cross-project rules), shipping
with a tracked engine default the user can change. The default's brainstorming
dependency ships in-engine as a tracked skill.

## Success criteria

1. `install.sh` seeds `orchestrator.md` from tracked `orchestrator.template.md`
   only when missing; an existing file is never overwritten (identity parity).
2. The full injection payload carries the orchestrator section in every
   harness format — xml `<memory:orchestrator>` (claude, antigravity) and md
   (codex, copilot) — ordered directly after identity; the per-prompt
   breadcrumb includes it wherever it includes identity.
3. `skills/brainstorming/` is tracked in git (gitignore negation); no
   brainstorming entry remains in `skills.toml.example`; `link-skills.sh` fans
   it out; the skill text is role-neutral (no "orchestrator is always Claude").
4. Full suite green including new seeding/injection/skill-tracking tests;
   shellcheck clean; doc-vs-code clean.
5. This instance ends with a trimmed voice-only `identity.md` + seeded
   `orchestrator.md`, and a live session shows both sections injected.
6. `UPGRADING.md` 1.4.0 documents the manual trim for existing instances.

## Design

Approved via brainstorm (2026-07-16). File pair mirrors identity exactly (the
1.1.0 lesson): tracked `orchestrator.template.md` at repo root — content = the
current role-neutral Orchestration + Task Contract + Cross-project sections —
seeded to gitignored `orchestrator.md`. Precedence stated in both templates:
identity hard rules > orchestrator doctrine > project memory.

Injection: new `orchestrator` section in `content-core.sh` (`_CS_ORDER`:
identity **orchestrator** project index domain working) reading root
`orchestrator.md`; added to both format render lists in `scripts/hooks/lib.sh`
(full + breadcrumb) and antigravity's `preinvocation.sh` section call.

Brainstorming ships in-engine: content moves to tracked `skills/brainstorming/`
(`.gitignore`: `!skills/brainstorming/`), catalog entries removed
(`skills.toml.example`; personal `skills.toml`/lockfile/`.skill-cache` handled
by the orchestrator, not the executor). `skill_roots` already prefers `skills/`
over `.skill-cache/`. Claude-pinned line in the skill replaced with role-based
phrasing. Establishes the rule: engine-shipped skills live tracked in
`skills/`; personal ones stay gitignored.

Rejected: domain-file placement (doctrine must be always-in-band); managed
section inside identity.md (defeats the separation); auto-split migration
(machinery rewriting personalised files — 1.1.0 lesson).

## Decisions (locked)

- Brainstorming ships tracked under `skills/` (user choice) — not via catalog.
- Existing instances: seed-only + manual trim; no migration script
  (install-time seeding runs on every sync).
- Section order: orchestrator directly after identity, same cadence.

## Phases

- [x] Phase 1 — engine: `orchestrator.template.md` + install.sh seed +
      .gitignore + content-core.sh section + lib.sh render lists (xml/md,
      full/breadcrumb) + antigravity preinvocation + identity.template.md
      stub repointed.
- [x] Phase 2 — skill ship: tracked `skills/brainstorming/` + gitignore
      negation + skills.toml.example cleanup + role-neutral text fix.
- [x] Phase 3 — tests (seed, injection order, skill tracking) + docs
      (file-formats, workflow, harness pages) + UPGRADING note + changelog.
- [x] Phase 4 — this instance: trim identity.md to voice-only; remove
      brainstorming from personal skills.toml/lockfile/.skill-cache; re-link;
      live injection verification (orchestrator section present in a real
      session).

## Risks / open questions

- Formatter assumptions: verify xml/md renderers handle a new section name
  generically (no hardcoded section enum beyond the lists being edited).
- Breadcrumb path list may be identity-hardcoded in the renderers — criterion 2
  covers it.
- Double-injection window for existing instances until they trim identity.md —
  accepted, documented (harmless duplication).
