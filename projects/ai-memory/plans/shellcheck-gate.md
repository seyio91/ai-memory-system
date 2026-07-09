---
plan: shellcheck-gate
status: active
created: 2026-07-09
owner: claude (orchestrator)
task_provider: notion
task_ref: 397f6850-c619-812d-8677-fff1cfe873ad
---

# Shellcheck as a static-analysis gate

## Goal

Hard-fail `run-tests.sh` on shellcheck findings at severity `info` or above, across every
`.sh` under `scripts/` and `harnesses/`, with a curated disable set so the signal is real.

## Why this is NOT what the task record said

The captured task claimed the gate would have caught the `install.sh` abort found by the
2026-07-09 system review — the `A && B`-as-last-statement bug class. **That is false**, and
the plan must not be justified on it:

- The review's bug (`drivers/hook.sh`, a guard notice as a function's last statement returning
  1 under `set -euo pipefail`) is **invisible to shellcheck at every setting**, including
  `-o all` with `check-set-e-suppressed`. Probe-verified 2026-07-09.
- `SC2015` is an unrelated check (`A && B || C` is not if-then-else), sits at severity `info`
  (so the once-proposed `-S warning` gate would never fire on it), and all 9 sites are in
  `scripts/tests/test_*.sh`.
- That bug is already fixed (v1.2.0) and pinned by a behavioural test (`84a546b`), which is
  the only control that covers the class.

**The honest justification is prospective:** shellcheck finds **zero** real bugs in the tree
today at any floor, and the gate exists to stop the *next* `SC2086` from landing. Scoping it
against a real-but-fixed bug it cannot see would ship a gate that proves nothing.

Baseline as of 2026-07-09, excluding `SC1091`/`SC1090`: **0 error, 19 warning, 66 info, 70 style.**
Of the 19 warnings, 13 are in tests and the 6 in production are false positives or dead locals.

## Design

### The floor is `info`, not `warning`

`SC2086` — unquoted expansion, word-splitting and globbing — is severity **`info`**. A gate that
hard-fails at `warning` can never fire on the single most consequential shell bug class. So the
floor is `info`; `style` stays out (70 findings, mostly `SC2250` brace preferences).

Scoping this gate is what surfaced the one genuine `SC2086` in the tree: the deny-list guard
passed its spec files as a space-joined string, so a `$REPO` containing a space silently loaded
fewer rules. Fixed separately in `34fca1a`, before this plan. The other 5 sites are deliberate,
`IFS`-scoped splits.

### Curated disables, not a baseline file

Three codes are noise here and are disabled repo-wide in `.shellcheckrc`:

| Code | Count | Why disabled |
|---|---|---|
| `SC1091`/`SC1090` | 76 | "source not followed" — the `. "$SCRIPT_DIR/_lib.sh"` idiom, unanalysable by design |
| `SC2016` | 20 | single quotes intentionally suppress expansion (heredocs, `awk`/`perl` bodies) |
| `SC2034` | 8 | vars set for a sourced `_lib.sh`, or captures that exist to swallow stdout |

Everything else fires. The 6 deliberate word-splits take an **inline**
`# shellcheck disable=SC2086` with a one-line justification — inline, so the exemption is
visible at the site and dies with the code, unlike a baseline file that rots silently and
gets regenerated on autopilot.

Rejected: a `.shellcheck-baseline` of today's 66 findings. It churns on every refactor, and the
accepted findings are never revisited — the same "an artefact records a verification and then
gets trusted in place of one" trap recorded in `memory.md`.

### Wiring

A `== shellcheck ==` stage in `run-tests.sh`, gating the exit code, next to the existing
`taskprovider (python)` stage. `find … -exec shellcheck -f gcc {} +` is the reliable
invocation — `shellcheck -f json $files` returns empty under the Bash-tool zsh.

Shellcheck is a **dev/CI-only** dependency, so the zero-runtime-dependency bet is untouched.
The stage must **skip with a notice, not fail**, when `shellcheck` is absent, or it breaks
`install.sh` on a fresh machine and every consumer instance that runs the suite.

## Success criteria

1. `.shellcheckrc` exists and disables exactly `SC1091`, `SC1090`, `SC2016`, `SC2034`, each with a comment.
2. `run-tests.sh` has a `== shellcheck ==` stage whose failure sets a non-zero suite exit code.
3. With `shellcheck` on PATH, the suite passes on a clean tree at severity `info`.
4. The stage **skips with a printed notice and exit 0** when `shellcheck` is not installed.
5. Every remaining `SC2086` site carries an inline `# shellcheck disable=SC2086` with a justification.
6. A deliberately-introduced `SC2086` (unquoted `$var` in a new prod script) **fails the suite** —
   verified by adding it, running, and reverting. The gate is proven to fire, not assumed to.
7. No production behaviour changes: `git diff` touches only comments, `.shellcheckrc`, and `run-tests.sh`.
8. `docs/scripts.md` documents the gate, the floor, and how to justify an inline disable.

## Decisions (locked)

- **Floor = `info`.** `warning` cannot see `SC2086`; `style` is 70 findings of brace-preference noise.
- **Curated disables over a baseline file.** Exemptions live at the site, not in a rotting ledger.
- **Skip, don't fail, when shellcheck is absent.** A dev-only tool must not gate a consumer's suite.
- **The gate catches nothing today, and that is fine.** Its value is prospective; it is *not* the
  control for the `set -e` last-statement class. That control is a behavioural test.
- **No `-o all`.** Optional checks add `SC2250`/`SC2292` brace-and-`[[` churn for no defect coverage,
  and still miss the bug that motivated the task.

## Phases

- **Phase 1 — `.shellcheckrc` + inline disables.** Create the rc with the 4 disables; annotate the
  6 `SC2086` sites; fix the `resolve-skills.sh:154` dead `local line`. Tree reaches zero findings
  at `-S info`.
- **Phase 2 — `run-tests.sh` stage.** Add `== shellcheck ==`, gate the exit code, skip-with-notice
  when the binary is absent. Prove criterion 6 by introducing and reverting a real `SC2086`.
- **Phase 3 — docs.** `docs/scripts.md` gate section; CHANGELOG `### Added`.

CI wiring is explicitly **out of scope** — no CI exists for this repo yet; `run-tests.sh` is the gate.

## Risks / open questions

- `shellcheck` version skew: severity assignments can move between releases, so a code that is
  `info` on 0.11 may be `style` elsewhere and silently stop gating. Pin nothing, but note it —
  the suite is run by a handful of known instances.
- The 4 repo-wide disables are a standing bet that those codes never carry signal here. `SC2034`
  is the weakest of the four: it *can* catch a genuinely dead variable. Accepted because 8 of 8
  current hits are false positives, and a dead variable is not a defect class worth 8 annotations.
