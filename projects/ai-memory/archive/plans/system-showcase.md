---
plan: system-showcase
status: done
created: 2026-07-06
completed: 2026-07-06
owner: claude (orchestrator)
---

# Plan — Memory System Showcase (doc + diagrams + live demo)

## Goal
Produce a durable, teach-focused showcase of the ai-memory system for a **technical
adopter** audience, delivered as a **~60-min live interactive demo** run against the
**real system and real projects**. Three coordinated artifacts: a walkthrough
**document** (the durable reference that outlives the talk), a **diagram set**
(Mermaid for the durable set + 1–2 Excalidraw heroes for the talk), and a **demo
runbook** (ordered, copy-pasteable beats timed to 60 min). The narrative thesis:
*memory that compounds across sessions and repos with no DB and no retrieval — just
markdown + hooks.*

## Success criteria
- `docs/showcase.md` exists and covers all three capability tiers, each capability
  framed as *what it does · why it's built that way · the file/command behind it*.
- Diagram set renders: 6 diagrams total — 4 Mermaid (marker resolution, delegate-don't-load,
  O/E/V + promotion, manifest→drivers→targets) embedded in the doc, plus 2 Excalidraw
  heroes (three-layer model, injection flow). Every Mermaid block renders; each `.excalidraw`
  opens.
- `docs/demo-runbook.md` exists: ordered beats, exact copy-paste commands, a "say / reveal"
  note per beat, mapped to the 60-min budget, cross-referenced to doc sections + diagrams.
- **Every command in the runbook executes clean against the real tree** in a dry pass
  (read beats + `/state`, `/activity`, `/reindex`, `run-tests.sh`, `install.sh --list`,
  the fresh-repo `/pin`→capture→`/promote-memory` chain).
- The runbook's write-beats touch only the fresh demo repo and gitignored projects —
  **never the tracked `ai-memory` project** — and each has a documented revert.
- A full dry-run of the arc completes in ≤60 min (rehearsal timing noted in the runbook).

## Design
- **Real system, not a sandbox** (user decision): the demo runs against the live tree
  and real projects. Authenticity is the point for adopters. Write-beats are confined to
  a **freshly onboarded repo** + gitignored projects so nothing mutates tracked memory.
- **Document = primary durable artifact** (goal is educate/document); the demo is its
  executable companion. Weight effort toward doc rigor + accurate diagrams.
- **Narrative over feature-list**: capabilities are revealed as beats in the
  "compounding memory" story; the killer beat is capture → new session → recall →
  "it's just a file."
- **TPE cluster as the Related-Projects centerpiece**: `tpe` / `tpe-stacks` /
  `tpe-kubernetes` are a real related set AND share the `tpe` category, so cross-project
  relationships and category grouping reinforce each other in one beat.
- **Diagram format** (user decision): Mermaid for the durable, in-repo, diffable set;
  Excalidraw only for the 1–2 most-shown hero diagrams.
- Alternatives considered:
  - *Disposable hermetic sandbox* → rejected: user wants real-project authenticity;
    fresh-repo onboarding covers the write-safety need instead.
  - *Excalidraw for everything* → rejected: harder to keep in sync with an evolving
    system; Mermaid stays in git and diffs.
  - *Slides/recorded* → rejected: format is live interactive.

## Decisions (locked)
- Audience: technical adopters. Format: live interactive. Budget: ~60 min. Goal: educate/document.
- Runs against the **real system + real projects**; write-beats on a **new repo** + gitignored projects only.
- Categories are set (platform / myccv / tpe) → `/state` + `/activity` grouping is demo-ready.
- Related Projects centerpiece = TPE cluster.
- Diagrams: Mermaid + 1–2 Excalidraw heroes.
- Artifact homes: `docs/showcase.md`, `docs/demo-runbook.md`, diagrams under `docs/diagrams/`.
- **Fresh-repo onboarding target = `/Users/sobaweya/Projects/ccv-terraform/flexo`** — verified git repo, currently unpinned (no marker), no `projects/flexo` yet, origin `git@github.com:CCV-Group/flexo.git`. Genuinely cold onboard for the `/new-project`/`/pin` → capture → `/promote-memory` chain. **Kept post-demo** as a real project (no revert); the onboarding beat is a permanent, authentic addition.
- **Reveal the injected `<memory:*>` block via SessionStart output** (not a manual `inject_memory.sh` run) — start a fresh session in the repo and show the injected payload as it actually arrives.
- **Capture→recall across a session boundary via `/checkpoint`** — checkpoint into `working.md`, start a new session, show the checkpoint recalled on SessionStart.

## Phases
### Phase 1 — Content skeleton + capability inventory
- Draft `docs/showcase.md` outline: problem → thesis → three-layer model → injection-vs-retrieval → capability tour (3 tiers) → try-it-yourself.
- Lock the capability→beat→diagram mapping (the 60-min table from the discussion).

### Phase 2 — Diagrams
- Author 4 Mermaid diagrams inline in the doc (marker resolution, delegate-don't-load, O/E/V + promotion, manifest→drivers→targets).
- Author 2 Excalidraw heroes (three-layer model, injection flow) under `docs/diagrams/`.
- Verify each renders / opens.

### Phase 3 — Document body
- Write the capability tour: for each capability, *what · why · file/command behind it*, grounded in real files (identity.md, a real project memory.md, index.md, executor.sh, install.sh, run-tests.sh).
- Embed diagrams at their beats.

### Phase 4 — Demo runbook
- Write `docs/demo-runbook.md`: beat-by-beat, exact commands, say/reveal notes, minute budget, cross-refs to doc + diagrams.
- Specify the fresh-repo onboarding beat (`/new-project` or `/pin` → capture in working.md → `/promote-memory`) and the capture→recall session-boundary beat.
- Document a revert for every write-beat.

### Phase 5 — Dry-run + validation
- Execute every runbook command against the real tree (read beats + generators + the fresh-repo chain on a throwaway repo).
- Time the full arc; confirm ≤60 min; fix any command that doesn't run clean.
- Validate against Success criteria.

## Risks / open questions
- **60-min budget is tight** for all three tiers; Phase 5 timing may force trimming Tier-3 depth (harness-agnostic or O/E/V) to a diagram + narration rather than a full live run.
- Excalidraw hero fidelity vs. time: heroes are polish; if Phase 2 runs long, ship Mermaid versions and upgrade later.
_Resolved (folded into Decisions): fresh-repo target = `ccv-terraform/flexo` (**kept** as a real project post-demo — no revert path in the runbook); reveal via SessionStart output; capture→recall via `/checkpoint`._
