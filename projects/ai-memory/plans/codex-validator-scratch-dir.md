---
plan: codex-validator-scratch-dir
status: in_progress
created: 2026-09-22
owner: claude (orchestrator)
task_provider: notion
task_ref: 3e3f6850-c619-81b7-a76e-f0b33f2f0070
---

# Writable scratch dir for codex validator runs

## Goal

Let a codex validator run tests and the deliverable: its validate face runs `workspace-write`
rooted in a fresh scratch dir (network off), so `/tmp` and the scratch are writable while the repo
under test stays kernel-denied; explore and other harnesses keep their read-only faces.

## Success criteria

1. `executor.sh --role validate` resolves a harness's `exec_validate`, else `exec_readonly`, else
   the subagent plane; `explore` still uses `exec_readonly` only. `test_executor.sh` covers all
   three validate paths and an unchanged explore path.
2. `harnesses/codex/manifest` declares `exec_validate = …codex-mem.sh --validator {prompt}`;
   other manifests unchanged.
3. `codex-mem.sh --validator` creates a fresh scratch dir (`mktemp -d`), runs codex with
   `--sandbox workspace-write -C <scratch>`, network off, `GOCACHE`/`GOTMPDIR` inside the scratch,
   never adds the repo or its `.git` to writable roots, and removes the scratch on every exit path
   (success, codex failure, signal). `test_codex_mem.sh` asserts the flags, the absence of
   writable_roots/network, and cleanup on success and failure.
4. `agents/validator.md` Role: scratch `git worktree`, or on sandboxed planes a `git clone --shared`
   inside the scratch dir; never write to the repo under test.
5. Docs (`docs/workflow.md`, `docs/harnesses/adding-a-harness.md`, and any manifest-key reference)
   describe `exec_validate` and the validate role as repo-read-only, scratch-writable.
   Changelog fragment exists.
6. Live exercise: one `AI_MEMORY_EXECUTOR_VALIDATE=codex` run clones via `--shared`, runs
   `scripts/tests/test_executor.sh`, and pastes the output; in the same run `touch <repo>/x` and
   `git -C <repo> worktree add` fail "not permitted"; repo `git status --porcelain` identical
   before/after; scratch dir absent afterwards.
7. Full suite green (file count reconciled), lint WARN set unchanged, shellcheck clean.

## Design

Probe (2026-09-22, codex 0.150.0): `--sandbox workspace-write -C <scratch>` → `mktemp -d` OK,
scratch writes OK, repo `touch` denied, `git worktree add` denied (`.git/worktrees`),
`git clone --shared` + `test_executor.sh` in the clone OK.

- **New manifest key `exec_validate`**, validate-only, falling back to `exec_readonly`. Keeps the
  explore face fully read-only and every other harness unchanged.
- **`codex-mem.sh --validator`** owns the codex-specific parts: mktemp, `-C`, env, trap cleanup.
  `executor.sh` stays generic.
- Validator scratch copy is a `--shared` clone on sandboxed planes (worktree needs `.git` writes).

Rejected:
- Widen codex `exec_readonly` — explore shares it and must stay read-only.
- Orchestrator runs tests and pastes output — evidence stops being the validator's own.
- Read-only sandbox plus a writable-path config — no such knob verified for `read-only` mode.

## Decisions (locked)

- Network off for validator runs.
- Scratch dir deleted on every exit.
- The validate role is described as repo-read-only, scratch-writable.

## Phases

### Phase 1 — resolver: `exec_validate`
`scripts/executor.sh`: validate role reads `exec_validate`, else `exec_readonly`, else subagent
degrade (existing message). Explore untouched. Tests in `scripts/tests/test_executor.sh` with
sandboxed manifests.
**Verify:** criterion 1 — `/bin/bash scripts/tests/test_executor.sh` green; mutation (drop the
`exec_validate` lookup) fails the new case; explore assertions unchanged.

### Phase 2 — `codex-mem.sh --validator`
`harnesses/codex/scripts/codex-mem.sh` mode + `harnesses/codex/manifest` line. Tests in
`scripts/tests/test_codex_mem.sh` (stub codex binary records argv/env/cwd).
**Verify:** criteria 2–3 — tests green under `/bin/bash`; stub sees `workspace-write`, `-C <scratch>`,
no `writable_roots`, no `network_access=true`; scratch gone after a zero and a non-zero stub exit.

### Phase 3 — prompt and docs
`agents/validator.md` Role, `docs/workflow.md`, `docs/harnesses/adding-a-harness.md` (+ any
manifest-key table), `changelog.d/codex-validator-scratch-dir.feature.md`.
**Verify:** criteria 4–5 — each file states the rule; `grep -n exec_validate docs/` hits the
manifest-key reference.

### Pre-PR checkpoint
**Depends:** P1, P2, P3
Criteria 6–7: live codex validate run with the repo-status and scratch-absence checks; full suite;
lint set diff; then branch + PR.

## Risks / open questions

- Go module downloads need network; tests work only with a warm module cache (reads of
  `~/go/pkg/mod` are allowed).
- The codex memory hook resolves no project from a scratch cwd — validator runs without injected
  project memory (the validator prompt is prepended anyway).
- `workspace-write` defaults (`/tmp`, `$TMPDIR` writable) are codex behaviour, not ours; a codex
  release that changes them breaks run-it silently — the live exercise is the only guard.
- Other sandboxed harnesses (agy has `--sandbox`) could adopt `exec_validate` later.
