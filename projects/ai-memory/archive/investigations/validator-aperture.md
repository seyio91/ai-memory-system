---
investigation: validator-aperture
status: open
created: 2026-09-20
owner: claude (orchestrator)
task_ref: 3e1f6850-c619-8185-a7b4-c934dbb2466d
---

# Validator aperture — why two bug-grade defects survived two clean rounds

**Origin:** platform-agent PR #17 (M2 Phase 7, the eval runner), 2026-09-20. The branch passed
two full validator rounds — Part A green, Part B cleared, PR-READY — and CI green. A PR review
bot then found five real defects, two of them High, both of which would have silently invalidated
the Phase 8 baseline the runner exists to produce.

## The two misses

1. **A correct proposal scored as a broken task.** `runTask` resolved the original file content
   from `Config.Originals` (populated in exactly one test, never by the CLI) or from successful
   `read_file` calls. But `agents/prompt.go` tells the agent to use `get_workload` and call
   `read_file` "only when needed", and `get_workload` returns full file content. So the most
   likely agent path produced an empty original, `score.decodeYAML` returned `yamlProblemEmpty`,
   and the scorer rejected the ORIGINAL. Seeing it requires reading three files together, two of
   them merged in other phases.
2. **Every multi-task report flagged incomparable.** `incomparable` compared every summary's
   `TaskHash` to `summaries[0]`'s. Distinct tasks have distinct hashes by construction, so any
   report covering more than one task was globally flagged and every summary inherited it. The
   baseline is ~5 tasks x 3 runs. A flag that is always on is a flag nobody reads, and D6a's
   whole mechanism dies with it. `TestIncomparable` passed because it only used same-task summaries.

## Why the validator missed them

- **Its contract is the phase, not the system.** Part A is the phase's `**Verify:**` line; Part B
  is the defect-class list the orchestrator supplies. Neither defect violates a Verify clause. It
  passed a branch that met its contract — so the contract was the defect, not the checking.
- **The class was listed and it still missed.** "Silent degradation: a required value missing
  turned into a zero value or empty string instead of failing" describes miss 1 exactly. A class
  list says WHAT to look for, not WHERE. Both misses live at seams between the diff and
  already-merged code.
- **Orchestrator hypotheses anchored it.** Round 1 it was handed seven specific hypotheses and
  verified all seven well (one refuted with evidence, one with a sharper mechanism than the
  orchestrator had). That is where the budget went. Hypothesis-led review buys depth and costs
  aperture; both are real and the cost was not priced.
- **Nobody ran the thing.** It ran the tests. It never executed the runner on a realistic task set
  and looked at the output — miss 2 is visible in ten seconds in a 5-task report. This repeats a
  lesson platform-agent memory already records: validate against the real checkout, not fixtures;
  verifying a criterion is how bugs surface.
- **The bot is decorrelated differently.** It reads the whole PR cold with no idea what the
  orchestrator wanted checked. The validator reads it through the orchestrator's priors. Giving
  the validator a GOOD hypothesis list made it a worse open-ended searcher.

## Proposed changes to `agents/validator.md`

1. **Production-path trace.** For every config field, map or option the diff introduces, name its
   producer on the real path — not the test path. "Who populates this in production?" finds miss 1
   on its own.
2. **Run it, don't just test it.** Execute the deliverable on realistic input and paste the output
   into the report. Passing tests are not the same evidence as looking at what it emits.
3. **Cold pass before hypotheses.** Give open-ended review its own budget, or split into two
   validators — one hypothesis-led, one cold. The orchestrator's list must not arrive first.
4. **Cross-seam scope.** The brief names the merged components the diff leans on, and reading them
   is explicitly in scope rather than out of it.

Keep the PR bot in the loop before merge regardless: it is cheap and decorrelated by construction.

## Open question

Whether 3 is worth two validator invocations per phase, or whether ordering alone (cold pass first,
hypotheses delivered as a follow-up message to the same agent) buys most of it for one invocation.
The resumable-subagent pattern used throughout M2 makes the single-agent version cheap to try first.

## Addendum 2026-09-21 — platform-agent PR #21 (M3 `gates/`): the same misses, again

Six validator rounds on the branch; the last two were PR-READY. The PR bot then found 8 real
defects, 3 security-grade: helm option injection via a proposed `releaseName` (`--help` exits 0
and bypasses schema+render), `repoURL`-only changes validated against the wrong chart, unbounded
`valueFiles` (tmp/argv exhaustion). The other five: valueFiles order regrouped (breaks
last-file-wins), agent-authored bad refs reported as environment errors, `Rejected()` returning a
verdict before a later gate's Error, truncated helm stdout treated as success, and duplicate keys
silently last-wins. Also PR #20 (same slice): 5 bot findings after two clean validator rounds.

Causes the proposals above already cover: **anchoring**. Every brief led with the orchestrator's
hypotheses, and the validator confirmed that list instead of searching cold. The validator's own
background `/code-review high` returned zero findings, but it ran on the round's fix diff only.

Causes NOT covered by the proposals above. Add these:

5. **Review unit = diff + impact radius, not the whole repo.** (Refined with the user, 2026-09-21.)
   The validator reviews a diff, then finds and reviews the code the diff affects:
   - callers of every changed or new exported function/type (and their error/return handling)
   - callees and merged components the diff relies on (the seam: proposal 4)
   - consumers of any changed contract: struct fields, error sentinels/messages, interfaces, file
     formats, CLI flags, config keys (grep/LSP find-references; also text contracts like error
     strings matched elsewhere)
   - the production producer of every new input (proposal 1)
   Which diff: per fix round, the fix diff + its impact radius. Once per phase before PR-READY,
   the CUMULATIVE PR diff (`origin/main...HEAD`), cold, + its impact radius. "Full branch" here
   means that cumulative diff (what a PR bot reads), never the whole repository. The #21 misses
   were all inside the cumulative diff but outside the fix-round diffs the late rounds were
   scoped to.
   Limit: find-references misses dynamic coupling (interface dispatch, reflection, string-matched
   errors, files read by other processes), so the brief names known indirect consumers explicitly.
6. **Defect classes missing from the Part B list:**
   - untrusted input reaching an exec'd command's argv, i.e. option injection (`--` before
     positional args; validate names)
   - counts from untrusted input with no bound (list lengths → files, args, goroutines)
   - order not preserved when a list is split or regrouped (precedence and last-wins semantics)
   - parse ambiguity: duplicate keys, multiple documents, lenient decoders
   - truncation or partial reads reported as success (a bounded buffer that fills silently)
   The first three are the ones the bot marked security-grade.
7. **Same-model executor and validator.** After codex hit its quota the executor moved to the
   Claude subagent plane, and the validator was already there. That removed the cross-model
   decorrelation the validate role exists for. When the executor is `subagent`, set the validator
   to a different model family (e.g. `AI_MEMORY_EXECUTOR_VALIDATE=codex:<model>`), or say in the
   brief that decorrelation is lost and require the cold full-branch pass.
8. **A decorrelated full-branch review is a pipeline step, not a bot dependency.** Not every repo
   has a PR bot (user, 2026-09-21), and Bitbucket/Azure repos may have none at all. Make it part of
   validation, provider-agnostic: once per phase, just before PR-READY, run one cold review of
   `origin/main...HEAD` on a DIFFERENT model family from the executor, e.g.
   `executor.sh --role validate` resolved to `codex` read-only when the executor is `subagent`,
   or the reverse. Give it the plan's decisions list, the extended defect classes (6) and no
   hypotheses. If no second model family is available, run it anyway as a same-model
   `/code-review` over the full branch and label it "not decorrelated" in the report.
   Where a PR bot exists (qodo on FITER1 GitHub repos), open the PR as DRAFT and triage the bot's
   findings before marking it ready. That is a bonus layer, not the mechanism.
   Cost: one full-branch read per phase, not per fix round. Fix rounds stay diff-scoped.

**First trial of 5 + 6 (same day, #21 at ff573c9).** The validator ran a cold pass first, on the
cumulative PR diff plus the code it calls, then the Q1-Q8 checks. It found 4 new bug-grade defects
that six hypothesis-led rounds had missed: a symlink-escape read in `$values/` resolution
(`pins` guards it, `gates` did not — a seam bug), the YAML merge key rejected everywhere (a
restriction in disguise), an environment-code set duplicated in two functions that disagreed, and
a new workload's first chart pin going unlabelled. Three of the four came from its full-branch
`/code-review high`, and it re-verified each one itself. This was still same-model (codex was on
quota), so it is evidence for cold scope and ordering, not for decorrelation.

9. **Cap validation rounds at 5 per phase, then escalate to the user.** (User, 2026-09-21.) A
   "round" is one validator verdict on the branch, counting PR-bot review rounds that triggered
   fixes. When round 5 still ends NOT-READY, the orchestrator stops the loop and escalates with:
   bug-grade findings per round (is it converging?), which defect classes keep recurring, and
   options — continue with a named scope, narrow the phase, accept documented risks, or redesign.
   Origin: #21 reached 7 rounds (4 validator, 1 bot, 1 cold, and a 6th fix round in flight), and
   the finding count did not fall monotonically: 4, 6, 1, 0, 8 (bot), 4 (cold). Each widening of
   scope found more.

**Cross-model trial (#21 at 5a2ddea, codex read-only).** Codex found 2 validation bypasses that
every Claude round (executor, validator, cold pass) had missed: a `.yml` workload appset skipped
all workload gates, and an appended second YAML document in an appset was never parsed. That is
evidence for proposal 7 (decorrelation), separate from the evidence for cold scope.
Practical gap: codex's read-only sandbox denied Go its build temp dir (`/tmp`), so it could not
run the tests at all and reported only static traces. A codex validator needs `GOTMPDIR`,
`GOCACHE` and a scratch dir inside a writable allowed path, or a sandbox profile that permits a
temp dir, or it cannot run the deliverable (proposal 2).

## Cost model (2026-09-22) — widening the aperture without paying per round

Where the cost is: rounds × scope per round, not any one pass. #21's cold cumulative pass found
4 bug-grade defects six hypothesis rounds missed, so the lever is *reallocating* spend, not adding
it. Levers, best value per token first:

- **Run it (2)** — cheap, one command + output. Push the cost to authoring: the phase `**Verify:**`
  names a realistic runnable command, so the validator never invents one.
- **Scope by round type (5, 8)** — fix rounds stay fix-diff + one-hop radius; the cumulative cold
  pass runs once per phase, just before PR-READY.
- **Cold-first in one invocation (3)** — answers the open question above: hypotheses go in the same
  brief behind an explicit "only after cold findings are written" gate. Leakier than two
  validators, one invocation cheaper. Not via resume/follow-up message — the fresh-executor rule
  forbids it because a resumed turn replays the whole transcript.
- **Bound the impact radius (5)** — one hop (callers, callees, contract consumers) by
  grep/find-references; the brief names known indirect consumers. Unbounded, it becomes a
  whole-repo read.
- **Cross-model on the final pass only (7, 8)** — one extra call per phase, never per round. Also
  spreads quota across providers (both planes hit limits on 2026-09-20).
- **Model split by part** — Part A is evidence-matching (Sonnet/Haiku); Part B cold review gets
  the strongest model.
- **Round cap (9)** — bounds the worst case; lower for low-risk phases.

**Risk-tier the pipeline** (the largest time lever; needs the per-phase risk tag in task
`3dbf6850-c619-81eb-afbf-d64578a651d6`):
- low (prose, docs, consumer-less config) → Part A only
- medium (ordinary code) → Part A + diff review; one cold pass at PR-READY
- high (untrusted input, exec/argv, shared state, output consumed by later phases, security) →
  everything, incl. cross-model and run-it

**Per-phase vs per-PR:** validate per phase only when a later phase depends on it; independent
phases fold into the one cumulative cold pass at PR time.

**Uncounted cost:** each escaped bug returns as bot round + fix round + validator round — at
least one full round anyway, plus PR latency. Front-loading the cold pass on #21 plausibly
removes rounds 2–6, so the wider aperture may be net cheaper. Unmeasured: no per-phase
token/round counts exist. Task `3dbf6850-c619-817a-a5dd-c77db8f66182` (per-delegation metrics)
would supply them and let the tiers be tuned from data.
