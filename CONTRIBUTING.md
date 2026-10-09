# Contributing

Thanks for looking at this. It's a personal project first — a memory tree that its own tooling is developed inside — so a few of the conventions below exist for reasons that aren't obvious from the outside. This file explains those rather than restating general git etiquette.

## The one thing to know first

**This repo is both the engine and an instance of it.** `projects/ai-memory/` is the tracked dogfood project — the memory *about* developing this memory system. Everything else under `projects/`, plus most of `domain/`, is personal content and gitignored.

That means a clone is a working memory tree, not just source. `install.sh` wires it into a harness. Read **[docs/install.md](docs/install.md)** before running anything if that's surprising.

## Before you open a PR

**Run the full suite.** Not a selected run:

```bash
bash scripts/run-tests.sh
```

Expect `tests: N passed, 0 failed`, plus clean `python`, `doc-vs-code`, and `shellcheck` lines. The runner has selectors for mid-edit iteration — `--only PAT`, `--changed [REF]`, `--tests-only`, `--no-lint` — but only `--only` and `--changed` print a `SELECTED RUN` banner and a closing `*** NOT A FULL RUN ***`. `--tests-only` and `--no-lint` print no banner — the only sign is `skipped` on the stage lines. **All four are for iterating, never for gating.** Reconcile the summary counter against the file listing before calling a run complete; a truncating pager hides scope.

**Drop a changelog fragment** if you changed user-visible behavior — `changelog.d/<id>.<kind>.md`, where kind is `breaking` / `feature` / `fix` / `upgrade`. Don't edit `CHANGELOG.md` directly; it's assembled from fragments at release time. Format and rationale: [changelog.d/README.md](changelog.d/README.md).

## Testing discipline

**Verify a mutation landed and stayed isolated before trusting it as evidence.** Confirm the change actually took effect (`cmp`/`diff` against the pre-mutation file) and that it hit only the line under test — `bash -n` catches a mutation that broke syntax instead of the logic, and when sibling checks share text, target the mutation by line number. An unverified mutation can "pass" for reasons that have nothing to do with the control being tested.

**Mutually redundant guards are individually unkillable by mutation.** When two conditions both gate the same defect, deleting either one alone still leaves the suite green, so neither is actually pinned — remove the redundant guard so the one that's left becomes mutation-provable.

**A suite that inherits your global git config isn't hermetic, and a green CI run won't tell you that.** Local commit/tag signing makes fixture repos fail with errors that read as release-logic bugs, not environment; CI has no signing config, so its green result only proves CI's environment is bland, not that the suite is hermetic.

**A test file outside the runner's glob is silently ungated.** The suite reports green and exercises nothing for a test location that was never wired into the runner.

**A `set -e` test that dies mid-run hides every assertion after the death point.** Wrap fallible checks in `set +e` / `rc=$?; set -e` so a failure reaches the reporter instead of aborting the file silently.

**Derive expected values from the same config the code reads — never hardcode them.** A hardcoded expectation rots the moment the config changes, and the assertion keeps "passing" against stale data.

**Seed the empty-list case explicitly in any fixture that walks a collection.** It's the case most likely to be both untested and fatal for real input.

**`git check-ignore` needs `--no-index` whenever the ignore *rules* themselves are under test.** Against a tracked path it short-circuits on the index and reports "not ignored" without reading `.gitignore` at all, so the test passes for free regardless of the rules.

**The lint WARN baseline is a measurement, not a constant.** Derive it fresh immediately before and after your change and compare the warning *sets*, not the counts — a count can move for reasons entirely unrelated to what you touched.

## Shell constraints

**Scripts target macOS `bash` 3.2.** This is the portability floor, and it is not theoretical — CI runs the suite on `macos-latest` precisely to catch it. No `mapfile`, no associative arrays, no `${var,,}`. A bash-5 Linux runner will happily accept code that breaks for every macOS user.

**`shellcheck` is pinned to 0.11.0** in CI, deliberately — not `apt`/`brew`, whose versions differ per runner. An unpinned linter makes CI flaky as checks change between releases. Match the pin locally if you're chasing a CI-only finding.

Watch for BSD-vs-GNU divergence in `stat`, `sed -i`, `date`, and `find`. Three latent bugs of exactly this shape surfaced the first time CI ran on both platforms — including `stat -f`, which means *format* on BSD and *file-system* on GNU, so it silently returns a wrong value instead of failing.

## Conventions that carry weight

**Two-Path principle.** The store is markdown first. Every script that mutates the tree must have a hand-editable equivalent producing the same on-disk result — a human can checkpoint, archive, or scaffold by editing files directly. Never invent a format only a tool can read or write, and document the manual path.

**Executable tests cannot gate prose.** Slash commands in `commands/` are natural-language instructions an agent follows; nothing in `scripts/tests/` executes them. A command shipped here with a step that said "skip to Step 8" twice — silently skipping Step 7, the step that did the actual work — while the full suite stayed green and its lint backstop passed mutation testing in both directions. **If you change a command's prose, exercise it end to end on its most common path**, not just its interesting one.

**A control isn't trusted until you've watched it fail.** If you add a check, lint rule, or gate, break the thing it's supposed to catch and confirm it goes red. A green result from a control that has never been observed failing is not evidence.

**Markdown here is not inert.** `docs/scripts.md` carries an env-var table that is machine-checked against the code (`check-docs`), and doc changes have shipped real defects. CI therefore runs the full suite on documentation PRs, with one narrow exemption: the **root community files** — `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`. Nothing reads them. That was verified, not assumed: `lint-memory.sh` only globs `domain/*.md` and `projects/*/…`, `check-docs` only parses `docs/scripts.md`, and the tests matching `README` use it purely as a sandbox fixture filename.

The exemption is implemented as a gate job that still reports a status — never `paths-ignore`, which reports *no* status and would deadlock a required check under branch protection.

**Don't grow that list without re-running the same verification.** An ignore list that rots fails *open*: it silently skips checks that should have run, which is the dangerous direction. Note the asymmetry — `docs/**` is emphatically **not** exempt, because `docs/scripts.md` is machine-checked and `docs/` ships to consumers in every release tag.

## Commits and routing

Conventional commits with a scope: `feat(hooks):`, `fix(lint):`, `docs(scripts):`, `chore(archive):`.

Routing is decided by **what** changed, not how big the diff is:

| Tree | Route |
|---|---|
| `scripts/`, `harnesses/`, hooks, `install.sh`, `docs/`, `.github/`, skills, tracked `domain/` files | branch + PR |
| `projects/**` (plans, todos, archive moves — bookkeeping about work) | straight to `main` |

As an outside contributor you'll essentially always be in the first row. "It's only a doc" is not an exemption — `docs/` ships to consumers in every release tag.

CI runs on `pull_request` only. Because it tests the merge result, it already reports what `main` will look like.

## Scope

Issues and PRs are welcome, but this is a single-maintainer project built around one person's workflow, and some of its opinions are load-bearing rather than incidental. If you're planning something substantial, **open an issue first** — it's much easier to talk through a design than to unwind a finished PR that cuts against a decision recorded in `projects/ai-memory/memory.md`.

By contributing you agree your work is licensed under the [MIT License](LICENSE).
