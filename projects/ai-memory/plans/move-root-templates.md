---
plan: move-root-templates
status: done
created: 2026-07-20
completed: 2026-07-20
owner: claude (orchestrator)
---

# Plan — Move root seed templates into `templates/`

## Goal
Five seed files sit in the repo root purely because that is where `install.sh` reads them:
`config.local.sh.example`, `identity.template.md`, `index.template.md`,
`orchestrator.template.md`, `skills.toml.example`. They are engine inputs, not things a user
opens, and they crowd the root alongside the files that *are* front-door (`README.md`,
`install.sh`, `UPGRADING.md`). Move all five under `templates/`, updating every live consumer.
Basenames are unchanged — this is a path move only.

## Success criteria
- `templates/` contains exactly the five files, and none of them remains at the repo root
  (`git ls-files --full-name | grep -v /` shows no `*.template.md` / `*.example`).
- A fresh install into an empty tree still seeds all five targets: `identity.md`,
  `orchestrator.md`, `index.md`, `skills.toml`, and the `config.local.sh` stub.
  `test_install_harness.sh` passes with its fixtures relocated.
- `skill_manifest_template()` returns the `templates/` path; `test_lib.sh` asserts it.
- `.gitignore` still tracks all five (`git check-ignore -v` reports none of them ignored) and
  still ignores the five live counterparts at root.
- Full suite green: `run-tests.sh` → `tests: N passed, 0 failed` with the per-file count
  reconciled against the summary counter and no partial-run banner; `check-docs` 0 findings;
  shellcheck 0 findings; lint at the 5-warning baseline (no new warnings).
- No live doc still points at a root path for these five: a repo-wide grep outside
  `archive/`, `CHANGELOG.md`, and the historical `UPGRADING.md` sections returns nothing.
- A changelog fragment exists and `assemble-changelog.sh --check` passes.

## Design
- **Chosen:** `git mv` the five into `templates/`, keeping basenames. Update the four live
  consumer classes — `install.sh` seed paths, `scripts/_lib.sh:skill_manifest_template`,
  `.gitignore` (one real negation + comments), and docs/tests.
- **No migration script.** `install.sh` seeds only when the target is missing, existing
  instances already have all five live files, and the new `install.sh` ships in the same tag
  as the moved templates. Nothing on a consumer instance resolves a template path at runtime.
- *Alternative — drop the `.template`/`.example` suffixes* → rejected (user decision): the
  folder would imply the role, but basenames appear in `UPGRADING.md`/`CHANGELOG.md` history
  and the suffix guards against editing a template thinking it is the live file.
- *Alternative — also move `domain/_template.md` and `projects/_template/`* → rejected (user
  decision): they are not root clutter, they sit inside the trees they seed, and moving them
  churns `new-project.sh`, several `.gitignore` negations, and lint globs.

## Decisions (locked)
- Basenames unchanged; path move only.
- Scope is the root five. `domain/_template.md` and `projects/_template/` stay put.
- No migration; no `UPGRADING.md` section required.
- Historical references in `CHANGELOG.md`, the per-version `UPGRADING.md` sections, and
  `archive/` are **not** rewritten — they describe the tree as it was at that version.

## Phases
### Phase 1 — move + engine
- `git mv` the five files into `templates/`.
- `install.sh`: 5 seed paths (`skills.toml.example` ×2, `identity`, `orchestrator`, `index`)
  plus the generated-stub comment.
- `scripts/_lib.sh:skill_manifest_template` → `templates/skills.toml.example`.
- `.gitignore`: repoint the `!/skills.toml.example` negation; refresh the 4 stale comments.

### Phase 2 — tests
- `test_install_harness.sh`: fixture writes + the seeded-copy assertion.
- `test_lib.sh`: `skill_manifest_template` expectation.
- `test_brainstorming_skill_tracking.sh`: catalog path.
- Verify each relocated fixture path actually exercises the new location (a fixture that
  writes to the old path would let the suite pass while the real install is broken).

### Phase 3 — docs + changelog
- `docs/install.md` (tree diagram + 3 prose refs), `docs/file-formats.md` (2 rows),
  `docs/harnesses/claude.md` (2 refs).
- Changelog fragment (`fix`).
- Full suite, then branch + PR (system change).

## Risks / open questions
- **A test fixture that still writes the old path passes vacuously.** `test_install_harness.sh`
  builds a fake tree; if fixtures move but an assertion still reads the root path, the suite
  stays green while a fresh install seeds nothing. Mutation-check: point one seed at a
  nonexistent path and confirm the suite fails.
- **`.gitignore` negation is the silent one.** If `!/skills.toml.example` is not repointed, the
  file becomes untracked and vanishes from the next release tag — a fresh install then has no
  catalog to seed from, and nothing in the suite would notice. Assert with `git check-ignore`.
- Root already has `.docscheck-exempt`, `.shellcheckrc` etc.; this plan does not touch dotfiles.
