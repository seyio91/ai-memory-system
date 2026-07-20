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

Expect `tests: N passed, 0 failed`, plus clean `python`, `doc-vs-code`, and `shellcheck` lines. The runner has selectors for mid-edit iteration — `--only PAT`, `--changed [REF]`, `--tests-only`, `--no-lint` — but a selecting run prints a `SELECTED RUN` banner and a closing `*** NOT A FULL RUN ***`. **Those are for iterating, never for gating.** Reconcile the summary counter against the file listing before calling a run complete; a truncating pager hides scope.

**Drop a changelog fragment** if you changed user-visible behavior — `changelog.d/<id>.<kind>.md`, where kind is `breaking` / `feature` / `fix` / `upgrade`. Don't edit `CHANGELOG.md` directly; it's assembled from fragments at release time. Format and rationale: [changelog.d/README.md](changelog.d/README.md).

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
