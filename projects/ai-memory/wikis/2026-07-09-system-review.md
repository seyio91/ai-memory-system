---
topic: system-review-2026-07
created: 2026-07-09
status: triage — plan input; archive when the follow-up plans ship
---

# System review — 2026-07-09

Four-agent review (engine / injection pipeline / executor+enforcement / tests+release+docs)
against `docs/system-overview.md` §9's questions. Working tree at review time: v1.1.0 +
uncommitted cross-model-validator diff. Suite 32/32 green (run twice independently).

**Verdict on the uncommitted `validate` diff: correct, safe to commit.** All 8 plan success
criteria verified (no-chaining real, read-only path, degrade, model threading,
`AI_MEMORY_ROLE` export, exit codes). Its doc misses are in the doc-rot section.

## High

1. **Deny-list flag-interposition bypass — verified live.** `scripts/deny-list.txt:11-19`
   matches binary immediately followed by subcommand. Through the Antigravity guard with
   `AI_MEMORY_ROLE=task`: `terraform -chdir=envs/prod apply`, `kubectl -n foo delete pod x`,
   `kubectl --context=prod apply -f x.yaml`, `gh --repo o/r pr merge 12` → all **allow**.
   (Chaining `a && terraform apply`, env-prefix, absolute path, `sh -c` are caught.)
   Also missing: `helm uninstall` / `helm delete`. Fix: allow interposed flags, e.g.
   `terraform([[:space:]]+-[^[:space:]]+)*[[:space:]]+apply\b`, or tokenize before matching.
2. **`set -e` aborts install mid-run for a hooks_json harness without `guard_script`** —
   `scripts/drivers/hook.sh:132`: `[ -n "$gs" ] && info …` as the function's last statement
   returns 1 under `set -euo pipefail`. Reproduced under bash 3.2: install exits after the
   hooks step; skills/commands/config stamping silently skipped. Latent (antigravity sets
   `guard_script`) but breaks the advertised extension point. Fix: `|| true` / `return 0`.
3. **JSON merge destroys user config on unparseable input** — `drivers/hook.sh:115-121`
   (also 51-57): `except Exception: data = {}` then rewrite. A JSONC / trailing-comma
   `hooks.json` / `settings.json` is wholesale replaced, no backup — contradicts install.sh's
   "backs up what it overwrites". Fix: back up before rewrite; abort merge on parse failure.
4. **Live client data in a tracked doc, repo headed public** — `docs/demo-runbook.md:21,87,98,173`
   hardcodes a real machine username + a client repo path (names redacted here — this wiki is
   itself tracked). Actionable under the remove-going-forward decision. Separately: ~18 tracked
   `projects/ai-memory/archive/` files carry client org names (e.g.
   `archive/plans/reorg-followups.md:13`, `archive/plans/system-showcase.md:65`) — covered by
   the deliberate keep-history decision, but reconfirm explicitly before flipping public.

## Medium — enforcement layer (one theme)

- **Antigravity deny-list fails open with no jq/python3** — `jsonutil.sh:45-62` returns empty
  → `[ -n "$CMDLINE" ]` skips the deny loop entirely (verified: `terraform apply` → allow).
  The read-only allowlist fails *safe* in the same condition. Fix: no parser ⇒ deny.
- **Riskiest coverage cell: codex `task` role.** Only enforced infra-deny is the optional,
  out-of-repo `~/.codex/rules/default.rules`; absent that it's prompt-only *with* shell +
  workspace-write. Argues for pulling the backlogged manifest `guard` capability forward.
- **Antigravity `exec_readonly` unverified at exec time** — manifest value is byte-identical
  to `exec_cmd` incl. `--dangerously-skip-permissions`; read-only rests entirely on the guard
  being registered in `~/.gemini/config/hooks.json` (which the python3-absent install path
  leaves unregistered). `executor.sh` never probes. Fix: manifest `exec_readonly_requires`
  probe honored by executor.sh.
- **Model suffix leaks onto degrade** — `scripts/executor.sh:81-87`: a foreign
  `harness:model` value degrading to the subagent plane prints `subagent:<foreign-model>`
  (verified `subagent:gpt-5-turbo`). Clear `R_MODEL` when degrading. Pre-existing for
  explore; validate inherits.
- **`executor.sh --role` as trailing arg hangs forever** — `executor.sh:156` `shift 2` no-op
  under bash 3.2, no `set -e`, while-loop respins. Confirmed hang.

## Medium — robustness

- **`json_field` is python3-only** (`harnesses/claude/hooks/memory_common.sh:65-68`) — no jq
  fallback (siblings have one). Without python3, PROMPT/CWD/SESSION_ID parse empty → every
  Claude hook silently dormant, no error. Mirror `jsonutil.sh:json_get`'s jq→python3 chain.
- **Non-atomic, globally-shared `~/.codex/AGENTS.md`** — `scripts/build-context-md.sh:26-44`
  writes in place; concurrent `codex-mem.sh` launches from different projects race (last
  write wins; truncated reads possible; `--executor` fan-out widens the window).
  Fix: `tmp.$$` + `mv`; consider per-project out-file.
- **Migration runner stdin inheritance** — `scripts/sync-system.sh` `run_migrations` (~315):
  `bash "$file"` inherits the loop's stdin; a migration reading stdin consumes the remaining
  pending list, run reports success. Latent (no migrations exist yet); self-heals next sync.
  Fix: `bash "$file" </dev/null`.
- **`detect_harness` hardcodes harness names** (`install.sh:51-65`) — "adding a harness =
  manifest only" is false for auto-detection; needs a manifest `detect` key. Related:
  `$MEMORY_DIR` expansion is ad hoc per consumer (hook.sh, executor.sh) not centralized in
  `_mf_expand` — a manifest `skills_dir = $MEMORY_DIR/…` would mkdir a literal `$MEMORY_DIR`.
- **Link scripts clobber foreign symlinks** — `link-skills.sh:57-63` (same in
  link-agents.sh:73-79, link-commands.sh:57-63): any same-named symlink pointing elsewhere is
  rm'd + relinked, contradicting their own headers. Only repair links resolving into
  canonical roots; WARN otherwise.
- **Per-prompt hot path: 3 python3 boots + ~10 forks** (`inject_memory.sh:17-19`,
  `memory_common.sh:67,88`) — ~100-200ms/prompt of process startup on the breadcrumb path.
  One `jq -r '[.prompt,.cwd,.session_id]|@tsv'`; `${dir%/*}` instead of `dirname`.
- **Existing `statusLine` overwritten unconditionally** (`drivers/hook.sh:58`) despite the
  merge's no-clobber docstring.

## Doc rot (the named gotcha recurred in the newest commit)

Validate-role commit misses: `docs/harnesses/antigravity.md:88,95,117,124` (still
"explore role", no `_VALIDATE`); `README.md:35` (validator sentence omits the validate role);
stale comment `scripts/executor.sh:~193`.

Older drift: 4 doc call-sites describe the removed `~/.claude/memory_sessions/` marker
mechanism (`docs/scripts.md:45`, `docs/harnesses/claude.md:25`, `docs/knowledge-lifecycle.md:48`,
`docs/workflows.md:89`) — actual mechanism is SessionStart injection + `.recompact` sentinels
in `$MEMORY_DIR/.sessions` (`MEMORY_STATE_DIR`). `docs/system-overview.md`: "27 test files"
(32), "tracked = … identity.md" (untracked since v1.0.0), release channel called backlogged
(shipped v1.1.0), "golden tests pin Claude/Codex byte-for-byte" (only Codex AGENTS.md is
fixture-pinned; xml formatter deliberately omits domain — scope the claim).
"Capability floor" prose (`config.local.sh.example:56`, `harnesses/claude/CLAUDE.md:75`)
describes no implemented mechanism — it's just an un-suffixed default.
`/sync-system` doc: `--dry-run` claims "mutates nothing" but runs `git fetch --tags`.
`/test-system` doc predates the validate-skills gate and omits `AI_MEMORY_ROLE` from the
scrub list. `release.sh:37` usage() sed range drifted (prints 6 comment lines).

**Structural fix:** nothing tests a command doc against the script it invokes; even a grep
test asserting doc-mentioned flags/vars exist in the script would have caught most of this.

## Test-coverage gaps

Zero coverage: `harnesses/claude/hooks/block_task_tools.sh` (**enforcement gate; only file
presence asserted** — a bad exit code silently disables the todo.md rule),
`codex-mem-checkpoint.sh`, Claude `statusline.sh` (Antigravity's IS behaviorally tested).
Indirect-only: link-* scripts, drivers, `build-context-md.sh`, `jsonutil.sh`.
Drift risk with no test: the deliberately duplicated `detect_project` / `json_escape` pairs
(`memory_common.sh` vs `_lib.sh`/`jsonutil.sh`) — in sync today, nothing pins that.

## Low (grab-bag)

- Injection: hand-rolled `json_escape` fallback passes control chars (CR) → invalid JSON
  (`memory_common.sh:58-61`); antigravity hook dies silently on malformed stdin and a missing
  `invocationNum` downgrades the first call to breadcrumb (`preinvocation.sh:29,39`);
  recompact sentinel consumed before the project check (`inject_memory.sh:29-33`); sentinel
  2-day prune only runs on compact events; `md.sh:45` word-splits filenames with spaces;
  marker content unvalidated (`../foo` escapes projects root) and walk skips `/` + doesn't
  resolve symlinks; no payload size cap (bloated working.md ships whole).
- Engine: `validate-manifest.sh:20` enum check accepts multi-word values; `--harness` as last
  arg dies silently (`install.sh:71`); validator WARNs discarded on success + predictable
  `/tmp/vm.$$` path; manifest values can't contain `#` (undocumented); delivery failures
  downgraded to `info`, partial install prints "Done"; stale codex manifest comment
  (`harnesses/codex/manifest:10-12`); command store hardcoded to `harnesses/claude/commands`
  (documented-deliberate); link scripts never prune dead symlinks (additive-only idempotency).
- Executor: probe falls back to `exec_cmd`'s first word even when the command came from
  `exec_readonly` (latent); `--show` exits 1 on a successful subagent resolve
  (`executor.sh:195-200`).
- Misc: `.gitignore:78-79` `!/.skill-data/.gitkeep` negation is dead (dir-excluded);
  `sync-system.sh` `resolve_channel` runs even in `--to` mode (invalid channel aborts a
  one-shot that doesn't need it); `_assert.sh:15` unused `HOOKS_DIR` is the suite's only
  real-`$HOME` reference; CMD-key charset docs narrower than code (`-` accepted).

## §9 review-question verdicts

- **Manifest abstraction leaky?** Mostly honest — parse path genuinely never sources data,
  drivers clean, manifests diff plausibly. Leaks: auto-detection, command store pinned to
  `harnesses/claude/`, read-only semantics living outside the manifest (the `guard` gap).
- **Enforcement patchwork a real risk?** Yes — weakest layer reviewed. Two verified
  fail-opens (flag bypass, no-parser bypass) + the codex-task cell. Everything else degrades
  safe; enforcement is where it degrades open.
- **Per-prompt cost?** Architecture right (breadcrumb design); implementation wastes 3
  python boots/prompt — easy win.
- **Selectors single-source?** Yes — all three consumers verified through
  `content_sections`; no drift. Only the duplicated hook-lib functions are at risk, untested.
- **bash-3.2 liability?** No violations found; quoting above average. Liability shows as
  edge-case shell bugs (`shift 2` hang, `set -e` returns, word-split `find`) — a shellcheck
  CI gate would catch most. The zero-dependency bet is holding.

## Verified-correct (checked, no issue)

release.sh guards all present/ordered (dirty → main → fetch → state → diverged → monotonic →
suite), `--cleanup=verbatim` closes the `#`-strip incident (regression-tested),
`AI_MEMORY_ROLE` refusal works. Migration runner: strict filename validation, atomic marker
writes, failure-resumable as documented. sync-system channel logic / `--to` ephemerality /
detached-HEAD recovery match docs and tests. `.gitignore` split otherwise matches claims; no
secrets (token-pattern grep) in tracked files. Suite genuinely hermetic (env scrub, mktemp
sandboxes, fake `$HOME`, local bare-repo origins, no network) — caveat: lint/validate-skills
passes run read-only against the real tree.

## Priority order

1. Deny-list patterns + fail-closed (+ the enforcement Mediums — one theme, candidate plan:
   manifest `guard` capability).
2. hook.sh `set -e` abort + JSON-merge backup.
3. `docs/demo-runbook.md` scrub (pre-public gate) + archive-tracking reconfirmation.
4. Doc-rot sweep — fold the antigravity.md / README misses into the validate-role commit;
   consider the doc-vs-script grep test.
5. Rest opportunistically (robustness Mediums, then Lows).
