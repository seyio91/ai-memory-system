---
task_ref: 3e4f6850-c619-81fc-8fc3-d2478b7bedbf
---

# Decision status lifecycle — `-proposed` is write-only

Found 2026-09-23 while trimming `initiatives/k8s-platform-agent.md`.

## Symptom

33 stream entries sit at `-proposed` across every initiative in the tree, most of them
shipped and running. The ratio climbs with initiative age, which is the shape of a leak:

| Initiative | proposed / entries |
|---|---|
| aws-account-cost-reduction | 1 / 12 |
| eks-cost-reduction | 5 / 11 |
| fineract-provisioning-dispatch | 9 / 24 |
| k8s-platform-agent | 18 / 32 |

`-proposed` never meant "not built" — `initiatives/_template.md:24-25` defines it as a
decision "from one project awaiting another's confirmation". It is a cross-repo handshake
state, so shipping the code was never what clears it.

## Cause 1 — three producers, zero consumers

- `orchestrator.md:63` — "append the next `D<n>-proposed` to that initiative's
  `## Decision stream` now, not at handover."
- `orchestrator.md:64` — "Record a cross-repo decision in the initiative decision stream
  at decision time as `-proposed`."
- `scripts/initiative-status.sh:476` — warns when a Target advanced with no new entry:
  "append the missing `D<n>-proposed` entry or ack". This one is wired into session start
  (`scripts/tests/test_session_start_memory.sh:103`).

So the system nags for more of a state it has no mechanism to drain. Nothing in the
doctrine, the scripts, the skills or lint ever clears one.

## Cause 2 — the format punishes the correct action

Status lives inside the identifier (`D22-proposed`), so confirming a decision **renames its
key**. 71 references across the tree carry the suffix, including sibling projects:
`projects/fiter-argo-apps/working.md` points at `D9-proposed`, `D10-proposed` and
`D12-proposed`. D9 and D10 were confirmed in the initiative, so those pointers are already
orphaned.

Writing "CONFIRMED" into the entry body costs nothing and breaks nothing. Clearing the
suffix breaks 71 pointers. Everyone took the cheap option — D9, D10, D14 and D15 all record
the confirmation in prose — and after D15 the suffix stopped being maintained at all, so
D17, D18 and D22 now contradict themselves outright:

- `D17-proposed` — body: "Confirmed by seyi 2026-09-20"
- `D18-proposed` — body: "six decisions confirmed by seyi"
- `D22-proposed` — body: "(user-agreed 2026-09-21, M3 design)"

Two places encode one fact and only one is maintained. Same drift class as an initiative
duplicating a project `memory.md`.

## Cause 3 — no trigger was ever named

The template says "until confirmed" and never says what confirms. With no observable
trigger there is no moment at which the transition is due, and at team size 1 the
confirming "other project" is the same person — the handshake is with yourself, so it never
surfaces as a step. D6a already documented this exact failure mode for CODEOWNERS.

Evidence the gap was noticed and had nowhere to live:
`projects/fiter-argo-apps/working.md` carries "Confirm or reject **D9-proposed**" as an open
item across four consecutive checkpoints (lines 101, 132, 158), then it falls off.

## Fix, in dependency order

1. **Status out of the ID** — `- D22 [proposed]`, not `D22-proposed`. The ID becomes stable,
   so confirming is a field edit rather than a rename. Everything below fails without this.
   Migration is cheap: lint and any resolver strip a trailing `-proposed` when resolving a
   reference, so the 71 existing pointers keep working untouched.
2. **Name the trigger** — a cross-repo decision is confirmed when the bound repo has
   ABSORBED it: profile merged, schema changed, PR landed. Record as
   `confirmed: <date> — <evidence>`. Held to the same "checkable, not aspirational" bar the
   Task Contract already sets for success criteria.
3. **Give the state a consumer** — `initiative-status.sh` gains the symmetric check to the
   one at :476: status `proposed` while `evidence:` names a merged PR, or the body says
   confirmed / user-agreed, is a contradiction. That check alone flags D17, D18 and D22
   today.
4. **Surface it where it is read** — `## State` carries "N proposed, oldest M days". The
   existing warning already fires at session start and still leaked 33 entries, so a count
   in the section actually opened beats another line of script output.
5. **Drain at the moment you are already there** — extend the doctrine's "Decision stream at
   phase completion": when appending an entry, check whether this Target's earlier proposed
   entries are now absorbed. No extra context, the file is already open.

## Scope

`orchestrator.md` + `templates/orchestrator.template.md` (bullets at :63-64 / :62-63),
`initiatives/_template.md` (:24-25), `scripts/initiative-status.sh`, `scripts/lint-memory.sh`.
Related: [[initiative-structure]] — same workflow, different defect (that one is about the
file being unreadable from a bound repo; this one is about status never clearing). Both
land in `initiatives/_template.md`, so sequence them.

## Migration — the three existing initiatives (user: note it here, 2026-09-23)

Fixing `initiatives/_template.md` only helps NEW initiatives: `commands/new-initiative.md`
copies the template verbatim, and nothing rewrites a file already on disk. The three
others stay on the old shape until someone migrates them:

| Initiative | lines | proposed | `binds:` lines |
|---|---|---|---|
| aws-account-cost-reduction | 159 | 1 | 0 |
| eks-cost-reduction | 296 | 5 | 0 |
| fineract-provisioning-dispatch | 566 | 9 | 0 |

15 stuck entries. All three use the old entry shape `- D<n>:` / `- D<n>-proposed:` and
**none carries a single `binds:` line**, so the migration is larger than a suffix rewrite.

Two halves, and only one is scriptable:

- **Mechanical** — `- D<n>-proposed:` → `- D<n> proposed —`, and add the decision-count
  line to `## State`. Safe to script. Do NOT rewrite the 71 `D<n>-proposed` references
  elsewhere in the tree; lint resolves the suffix to the bare id instead (fix 1).
- **Judgment, per entry** — authoring the `binds:` line means reading each decision to
  work out which repos it constrains, and the confirm pass means testing each proposed
  entry against its bound repo for absorption. Neither is scriptable. On
  `k8s-platform-agent.md` this was the bulk of the work: 15 of 18 confirmed on evidence,
  3 left proposed with an `unconfirmed:` line saying what would clear them.

**Reference implementation: `initiatives/k8s-platform-agent.md`**, migrated by hand
2026-09-23 (787 → 489 lines). It is ahead of the template, so read it rather than
designing from this document — it already carries the status-as-field shape, the dated
confirmations, the `unconfirmed:` lines, the `## State` count and the `## Binding index`
fence.

Sequencing: template + scripts first (both tasks), then migrate one initiative per
sitting. The migration is not blocking — an unmigrated initiative keeps working, it just
keeps leaking.
