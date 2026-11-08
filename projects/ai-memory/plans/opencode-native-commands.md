---
plan: opencode-native-commands
status: in_progress
created: 2026-11-08
owner: claude (orchestrator)
task_provider: notion
task_ref: 412f6850-c619-816d-aec7-db9613743e34
---

# Plan — opencode: deliver commands as native slash commands

## Goal
Deliver the memory system's commands to opencode v2 as native slash commands in `~/.config/opencode/commands/`, correcting #152's wrong "opencode has no native slash commands" premise.

**Before:** `harnesses/opencode/manifest` sets `commands = skill`; `/checkpoint`, `/state`, `/start` etc. never autocomplete in opencode; `docs/harnesses/opencode.md:46` claims opencode has no native slash commands.
**After:** `install.sh --harness opencode` symlinks every `commands/*.md` into `~/.config/opencode/commands/`; an interactive opencode v2.2.6 session lists and runs them as `/<name>` with `$ARGUMENTS` substituted; docs state the native surface.

## Non-goals
- Hiding the command-skills that remain visible via the shared `~/.agents/skills` (codex/copilot/antigravity still deliver them) — accepted duplication.
- Changing any other harness's command delivery.
- A migration script.

## Success criteria
- R1 [acceptance] Spike evidence recorded in `## Decisions`: on opencode v2.2.6, with a temp config dir, (a) whether a frontmatter-less command `.md` loads, (b) a symlinked command loads, (c) `$ARGUMENTS` is substituted, (d) the global `~/.config/opencode/commands/` is scanned — each with the command/output proving it.
- R2 [acceptance] `harnesses/opencode/manifest` has `commands = native`, `commands_dir = ~/.config/opencode/commands`; `bash scripts/validate-manifest.sh` passes.
- R3 [acceptance] A hermetic install test (`HOME` in a temp dir) of `install.sh --harness opencode` leaves one symlink per `commands/*.md` in `<HOME>/.config/opencode/commands/`, resolving into the repo's `commands/`.
- R4 [acceptance] If R1(a) shows frontmatter-less files are skipped: every `commands/*.md` starts with a frontmatter block carrying a one-line `description:`, and Claude still loads them (a `claude` session lists `/checkpoint` with that description). Otherwise R4 is N/A, recorded in Decisions.
- R5 [acceptance] Live: after install, an interactive opencode v2.2.6 session runs `/threads` (or another read-only command) and the agent follows that command's body; evidence quoted in the validator report.
- R6 [acceptance] `docs/harnesses/opencode.md` no longer claims there are no native slash commands and describes `~/.config/opencode/commands/` plus the accepted skill duplicates; `changelog.d/opencode-native-commands.fix.md` present; `bash scripts/run-tests.sh` green (full run).
- R7 [parity] Claude, codex, copilot and antigravity command delivery unchanged — vs `29c0ad0`: their assertion blocks in `test_install_harness.sh` are unchanged and pass.

## Design
- Flip the opencode manifest to the existing `native` surface (`install.sh` → `scripts/link-commands.sh <commands_dir>`); no new driver code expected.
- If opencode needs frontmatter, add `description:` to the canonical `commands/*.md` (Claude reads the same field), keeping plain symlinks.
- Command-skills from other harnesses stay in `~/.agents/skills`; opencode lists them as skills too — accepted.
- Rejected: hide duplicates via opencode permission config → needs a config edit #152 deliberately avoided.
- Rejected: native only when opencode is the sole `~/.agents` consumer → install-order dependent.
- Rejected: generated opencode copies with injected frontmatter → second source to keep in sync.

**Builds on:** `scripts/link-commands.sh`, `install.sh` commands surface (lines ~207–245), `harnesses/claude/manifest` (`commands = native`), PR #152, `scripts/tests/test_install_harness.sh`.

## Decisions (locked)
- Base: `29c0ad0d376d54ee0664d7f942f1e2ad3a278aaa`.
- Native commands for opencode; skill duplicates accepted.
- Frontmatter, if required, goes in the canonical command files.
- P1 spike (v2.2.6, standalone server + `session.command` API, expansion read back from stored user message, no model call): (a) frontmatter-less loads — YES → R4 N/A, no frontmatter added; (b) symlink (target outside config dir) loads — YES; (c) `$ARGUMENTS` substituted, incl. quoted/backticked forms in `pin.md`/`new-project.md` — YES; (d) `$HOME/.config/opencode/commands/` (plural) scanned — YES, `.opencode/commands/` and `OPENCODE_CONFIG_DIR` too. All 21 repo commands resolve to their own bodies — no clashes. Unknown frontmatter keys ignored, frontmatter stripped from prompt. `opencode run "/x"` does NOT expand slash commands (literal text) — Phase 3 must use the TUI or the API.
- Binary evidence (v2.2.6): command loader scans `{command,commands}/**/*.md` with `symlink:!0`, names by relative path, substitutes `$ARGUMENTS`/`$n`; returns early when frontmatter parse yields nothing.

## Phases
### Phase 1 — Spike: opencode command loading
- Temp `OPENCODE_CONFIG_DIR`/`HOME`, symlinked frontmatter-less and with-frontmatter test commands; establish R1 (a)–(d) via `opencode run` or the TUI command list.
- Record findings in this plan's `## Decisions` (orchestrator housekeeping; the executor reports, does not edit the plan).

**Files touched:** none (scratch dir only)
**Risk:** low
**Depends:** none
**Verify:** R1 — each of (a)–(d) answered with the command and output that proves it.

### Phase 2 — Manifest, frontmatter, tests, docs
- Manifest switch; `description:` frontmatter on `commands/*.md` iff Phase 1 says required; hermetic install test asserting the symlinks; docs and changelog fragment; `UPGRADING.md` note only if re-install is needed and the test-enforced pairing requires it.

**Files touched:** `harnesses/opencode/manifest`, `commands/*.md`, `scripts/tests/test_install_harness.sh`, `docs/harnesses/opencode.md`, `changelog.d/opencode-native-commands.fix.md` (new)
**Risk:** medium
**Depends:** Phase 1
**Verify:** R2, R3, R4, R6, R7 — `bash scripts/run-tests.sh` green; `validate-manifest.sh` passes; install test asserts the symlink set.

### Phase 3 — Live verification
- `install.sh --harness opencode` on the real instance from the branch, `opencode service restart`, run a read-only command in an interactive session.

**Files touched:** none
**Risk:** low
**Depends:** Phase 2
**Verify:** R5 — transcript excerpt showing `/threads` listed and executed.

## Risks / open questions
- Frontmatter parse may reject Claude-only keys if added later (`allowed-tools`, `argument-hint`) — keep frontmatter to `description:` unless the spike shows unknown keys are ignored.
- Name collisions: opencode built-in commands (e.g. `/init`, `/share`) vs ours — check the spike's command list; none of the 21 names is expected to clash.
- [feasibility CAUTION] Phase 3's `install.sh --harness opencode` and `opencode service restart` act on the live instance with no dry-run — preview with `bash scripts/link-commands.sh --dry-run ~/.config/opencode/commands` first.
- Phase 3 installs from a branch onto the live instance — a branch switch here is a live downgrade; run from a worktree install or return to `main` after merge and re-run `install.sh`.
