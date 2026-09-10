---
kind: investigation
task_ref: 3d7f6850-c619-81e9-b9c1-fe26d24274ff
status: open
created: 2026-09-10
---

# `task_ref: none` has no scope, and rule 10 carries a guard nothing can kill

Two findings from reviewing PR #104 after merge. The second was the one being looked for; the first was found on the way and is the more serious of the two.

## Finding 1 — `task_ref: none` silences rule 9 on investigations (fail-open)

PR #104 introduced `task_ref: none` as the explicit marker for a deliberately plan-only plan. Nothing scopes the value to plans.

Lint rule 9 (`scripts/lint-memory.sh:220-226`) exists to force every live investigation onto a task lifecycle, and it tests **emptiness only**:

```sh
if [ -z "$(extract_fm_field "$f" task_ref)" ]; then
    emit "WARN:  $f has no task_ref — attach the task it serves ..."
fi
```

`none` is non-empty, so it passes. Measured on the real tree:

| investigation frontmatter | lint WARNs |
|---|---|
| baseline (no probe file) | 18 |
| probe with **no** `task_ref` | 19 |
| probe with `task_ref: none` | **18** |

So `task_ref: none` is an undocumented escape hatch from rule 9. This matters because the two artifacts are not symmetric: a plan may legitimately be plan-only (that is the whole point of the marker), but **an investigation is never legitimately unbacked** — rule 9's entire purpose is that an investigation with no lifecycle anchor never gets archived. The marker introduced for one artifact silently became a bypass for another.

Note the direction of the failure: it fails **open**, and it fails open on the exact rule whose job is to prevent an omission. Same class as the gap PR #104 set out to close.

## Finding 2 — rule 10's inner guard is unreachable

`scripts/lint-memory.sh:234-250`. The outer guard at line 238 already skips every investigation whose `ref` is empty or `none`:

```sh
if [ -z "$ref" ] || [ "$ref" = "none" ]; then
    continue
fi
```

Past that point `$ref` can never be `none`. The inner condition at line 245 is:

```sh
if [ "$plan_ref" != "none" ] && [ "$plan_ref" = "$ref" ]; then
```

The second conjunct forces `plan_ref = ref`, and `ref != none`, so `plan_ref != none` is **always true whenever it is evaluated in a way that matters**. It cannot change the outcome.

Confirmed empirically during PR #104's verification: removing either guard alone leaves `test_lint_memory.sh` at 64 passed / 0 failed. Only removing **both** produces the expected 2 failures. That is the diagnostic signature of mutual redundancy — and it means neither guard is individually pinned by a test, so either could be deleted later by someone "simplifying", with the suite staying green.

## Why the two are one task

Both are the same defect class — an unscoped value and an unpinned guard — and both live in the same twenty lines. Fixing Finding 1 requires deciding what `none` means per artifact, which is exactly the decision that determines whether rule 10's guards are redundant or load-bearing. Splitting them would mean touching the same block twice and re-deriving the same question.

## Constraints

- macOS `bash` 3.2; `MEMORY_DIR`-resolved; run tests with `/bin/bash`.
- Lint baseline is **18** WARNs and must stay 18 after the change — a rule that starts flagging real tree content is a finding to surface, not a number to adjust.
- Whatever guard survives must be **mutation-provable**: deleting it alone must fail a test. That is the acceptance bar, not "the tests still pass".
- `task_ref: none` is now shipped vocabulary (v1.5.0+ consumers have it), so tightening rule 9 is a behaviour change that needs a changelog fragment and an `UPGRADING.md` consideration if it would newly warn on an existing tree.

## Open questions

- Should rule 9 reject `none` outright on investigations, or accept a different marker (e.g. archive the file instead)? Rejecting outright is the simpler rule but assumes no one has already used `none` on an investigation to silence the lint.
- Is `none` meaningful on any artifact other than a plan? Initiatives and todos do not carry `task_ref`; if plans are the only legitimate carrier, the scope check belongs in one place rather than per-rule.
