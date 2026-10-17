---
task_ref: 3e4f6850-c619-81b4-bb8e-ee5009443544
---

# Initiative file structure — State + derived Binding index

Origin: review of `initiatives/k8s-platform-agent.md`, 2026-09-23.

## Problem

An initiative is the cross-repo artifact: from any bound repo you must be able to ask
"what is the state of the initiative?" and "what binds me?". `k8s-platform-agent.md`
could answer neither without reading all 617 stream lines.

Measured on the pre-trim file (787 lines, `initiatives/archive/k8s-platform-agent-2026-09-23-pre-trim.md`):

- **12 of 31 entries stated no binding at all** — including D3, D10, D26, D28, every one
  of which binds a sibling repo. The binding had to be inferred from prose.
- Where stated, four different phrasings: `Binds X:`, `binds X`, `repos are bound — X`,
  `Binds every repo that publishes ...`.
- D12 bound "Phase 6" — a plan since archived, so the binding no longer resolves.
- 21 of 31 entries carried `-proposed` and none was ever confirmed, so the suffix had
  stopped discriminating.
- ~70 lines of the `platform-agent/repo-bootstrap` Target duplicated
  `projects/platform-agent/memory.md`, and the duplicate was already stale (stopped at M7
  while the stream carried M8/M9). `memory.md` is auto-injected every session, so it is
  the most expensive possible place to duplicate anything.

## Structure applied (k8s-platform-agent.md, 787 → 469 lines)

1. `## State` — three status lines (slice, live, open-across-repos) plus a Target table:
   `Target | status | next_actor | depends_on`. No prose.
2. `## Binding index` — repo → decision IDs, inside an AUTOGEN fence.
3. `## Decision stream` — one entry per decision, permanently, fixed shape:

       - D<n> [proposed|confirmed|retired|superseded|shipped] — <decision, one sentence>.
         binds: <slug, slug | alias>. <SUPERSEDES|SUPERSEDED BY|RETIRED BY|QUALIFIES|...> <id>.
         evidence: <pointer>.

   A rationale paragraph only where a future reader would otherwise reverse the decision
   (D3, D9, D29 earn one). Retired entries keep their line forever, marked, pointing at
   the archive.
4. `## Targets` — status prose is the delta since the last state change, never a milestone
   narrative.

## Why author-by-decision, derive-by-repo

`binds:` sits on the entry being written, so there is no second place to forget — that is
what makes it sync-proof. A hand-authored by-repo table has the opposite property, and is
how 12 entries shipped with no binding.

The alias is where deriving beats hand-authoring outright: `profile-publishers` expands to
the repos publishing `.platform/agent.yaml`. When a fourth repo starts publishing, one
alias definition updates and every row is correct; hand-authored, you would have to find
each entry that said "every repo that publishes ..." (D19, D22a, D25, D29).

Two-Path holds: the table stays hand-writable and the script reproduces the same bytes.

Fallback — once `binds:` is structured, the question is answerable by grep even if the
fence is stale, so a stale fence degrades the read and never corrupts it:

    grep -A2 '^- D' initiatives/<slug>.md | grep 'binds:.*fiter-infrastructure'

## To build

1. **`initiatives/_template.md`** — add `## State` and `## Binding index` (with fence), and
   the stream-entry shape above with its status vocabulary.
2. **`scripts/regenerate-bindings.sh`** — invert `binds:` lines into the fence. Same
   pattern as `regenerate-index.sh`. Must expand group aliases and **dedupe**: an entry
   listing a repo explicitly *and* via an alias currently yields a duplicate (verified —
   D22 emits `fiter-argo-apps` twice).
3. **`scripts/lint-memory.sh`** — three checks: (a) every stream entry has a `binds:` line;
   (b) every token resolves to a known project slug or alias; (c) the fence matches a fresh
   derivation. **(a) is the valuable one** — it is what would have caught D3, D10, D26, D28.
4. `.state/<slug>.snapshot` already tracks `stream-entries <n>` for drift; the same parse
   feeds it, so it extends rather than duplicates. Updated by hand to 32 for this file
   (D6a became its own entry).

## Homes, no duplication

- **Initiative** — the cross-repo contract: what was decided, what it binds, what
  superseded it. Reachable from every bound repo. Primary.
- **Repo docs** — the enforced rule, in the repo that enforces it. `platform-agent`'s
  README already has "Decisions that constrain this repository" in the right shape. This is
  also the only version-controlled home: `/initiatives/*`, `/projects/*` and `/archive/`
  are all gitignored, so a trim of a memory file is irreversible unless the text is copied
  first.
- **`initiatives/archive/`** — the reasoning essays, for the few that earn one.
- **Never a project `memory.md`** — auto-injected every session.

Drift found while doing this, which is the standing argument for keeping the initiative
thin and pointing at repos: D19 recorded the identifier pattern as
`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` while the schema enforces `^[a-z0-9]+(-[a-z0-9]+)*$`
(not equivalent — `a--b` differs), and called the 1024-byte purpose cap a profile
constraint when it is `maxPurposeLength` in `agents/prompt.go`.

Related: [[decision-status-lifecycle]] — same workflow, different defect (that one is about
`-proposed` never clearing). Both land in `initiatives/_template.md`, so sequence them.
