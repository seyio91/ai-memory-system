---
plan: deny-list-hardening
status: active
created: 2026-07-09
owner: claude (orchestrator)
task_provider: notion
task_ref: 398f6850-c619-816d-b1f8-e57e2d046df6
---

# Harden the executor deny-list

## Goal

Make the executor deny-list actually deny. Close the flag-interposition bypass, add the
missing destructive `helm` verbs, make a missing JSON parser **fail closed**, and let a user
extend the list without bricking their instance's ability to sync.

## Success criteria

> **STATUS 2026-07-09: the round-5/6 open bypass is now CLOSED (see `## Open — round-5 finding`,
> retained as the record). Six adversarial rounds, 23 bypass classes, all with regression tests;
> 155 assertions; suite green. Ready for a 7th pass and merge into 1.2.0.**

- [x] **Flag interposition is denied**, including the wrapper∘`sh -c` composition:
      `terraform -chdir=envs/prod apply`, `kubectl -n foo delete pod x`,
      `gh --repo o/r pr merge 12`, `az --debug repos pr update --status completed`, **and**
      `timeout 5 sh -c "terraform apply"`, `sudo -u root sh -c "terraform apply"`,
      `nice -n 10 ionice -c2 sh -c "…"` — the round-6 fix scans a wrapper's tail for a
      payload-bearing binary. `timeout 5 eval "terraform apply"` stays **allowed** (a wrapper
      cannot exec the `eval` builtin, so it runs nothing).
- [x] **Interposition in the *wrapper* is denied too** (found during execution, not planned):
      `sudo -u root kubectl delete pod x` — `sudo -u` takes a value, so the wrapper-skip loop
      stopped on `root` and called *that* the binary. Same bug class, one level up.
- [x] **Shell re-entry is denied** (found during execution): `bash -lc "…"`, `bash -xc "…"`,
      `sh -c"…"` (glued), `eval "terraform apply"`, `eval terraform apply`, `$(terraform apply)`,
      and backtick substitution. The first four were **regressions** the pre-existing substring
      regex would have caught — introduced by binary-gating the adjacency matcher.
- [x] **No regression on what already worked:** `terraform apply`, `terraform apply -auto-approve`,
      `echo hi && terraform apply`, `FOO=1 terraform apply`, `/usr/local/bin/terraform apply`,
      and `sh -c "terraform apply"` all still denied.
- [x] **A missing OR RULE-LESS `deny-list.txt` denies.** The guard skipped layer 1 when the spec
      file was absent — an absent rules file is indistinguishable from a disarmed guard, and this
      repo is a tree an executor can write to. The validator then pointed out that guarding
      *existence* is not guarding *armed-ness*: `: > deny-list.txt` disarms as well as `rm` does.
      Both now deny.
- [x] **A lone `&` is a separator, not a character** (validator finding). `sleep 1 & terraform
      apply` backgrounds `sleep` and **runs terraform**. Only `&&` was split. Also `|&`.
- [x] **Transparent exec-wrappers are recognised** (validator finding): `timeout 5 terraform
      apply`, `nice -n 10 …`, `flock /tmp/l …`, `setsid`, `stdbuf`, `xargs`, `ionice`, `chrt`,
      `script`, `watch`, `parallel`, `doas`, `su`, `runuser`, `exec`. Only
      `sudo|env|command|nohup|time` were known. `timeout` is what an honest agent types.
- [x] **Herestrings and process substitution are followed** (validator finding):
      `bash <<< "terraform apply"`, `bash <<<"…"`, `cat <(terraform apply)`.
- [x] **Basename must match exactly:** `terraform2 apply` and `myterraform apply` are allowed.
- [x] **`su`/`runuser` are `-c`-payload binaries, not plain wrappers** (round-2 validator, the
      DO-NOT-SHIP finding). `su - deploy -c "terraform apply"` is their *only* real idiom;
      listing them as wrappers made the payload an opaque token — coverage in name only, which
      is worse than an admitted gap.
- [x] **Shell syntax cannot hide the binary in the head slot** (round-2): `( terraform apply )`,
      `{ terraform apply; }`, `if …; then terraform apply; fi`, `for … do …`, `while … do …`,
      `trap "terraform apply" EXIT`. Parens/braces are separators; `then`/`do`/… are skipped as
      structural leaders.
- [x] **`busybox sh -c` and `find -exec` are followed** (round-2).
- [x] **Single quotes suppress substitution** (round-2 false positive): `echo '$(terraform
      apply)'` and `git commit -m 'run $(terraform apply) later'` are **allowed** — the shell
      would not execute them. Double quotes still deny (`echo "$(terraform apply)"`), because
      the shell *does*. A deny-list that blocks legitimate work gets switched off.
- [x] **The recursion depth cap denies** (round-2 test gap): a 10-deep `$(…)` nest with a benign
      innermost payload is denied by the cap; a 2-deep nest of the same shape is allowed, proving
      the cap is what fired.
- [x] **Arming check matches what the loader accepts:** a file of bare single words loaded zero
      specs while passing the "has rules" grep. Both now require binary + subcommand.
- [x] **An apostrophe inside double quotes does not mask a substitution** (round-4, HIGH, and
      *caused by* the round-3 FP fix): `echo "it's $(terraform apply)"` is denied. All three
      scanners now share one quote model. `echo '$(terraform apply)'` stays allowed.
- [x] **`find` executes only `-exec`/`-execdir`/`-ok` payloads** (round-4 false positive):
      `find . -name terraform -o -name apply` executes nothing and is allowed;
      `find … -exec kubectl apply -f {} \;` is denied.
- [x] **No false positives:** `kubectl get pod delete-me`, `kubectl get pods -l app=delete`,
      `git commit -m "kubectl delete"`, `echo terraform apply` are all **allowed**.
      (`echo` is a behaviour *change* — today's substring regex denies it. Intended.)
- [x] `helm uninstall` and `helm delete` are denied. `helm install` / `helm upgrade` still denied.
- [x] **Fails closed:** with neither `jq` nor `python3` on `PATH`, a guarded call
      (`AI_MEMORY_ROLE` set) is **denied** with a parser-missing reason. Unguarded interactive
      `agy` (no `AI_MEMORY_ROLE`) is still allowed — the guard must not brick a human's shell.
- [x] **User overlay works and is additive-only.** A gitignored `scripts/deny-list.local.txt`
      is concatenated with the tracked defaults. A pattern there is enforced. There is **no**
      un-deny syntax; a `-foo` line is treated as an ordinary entry, not a removal.
- [x] **The tracked defaults are never hand-edited**, so `sync-system.sh:dirty_tracked_guard`
      cannot brick an instance that customised its list. Verified: add an overlay entry, run
      the dirty-tracked guard, observe it passes.
- [x] `scripts/run-tests.sh` green, with the matcher's allow/deny table covered case-by-case in
      `test_antigravity.sh` (or a new `test_deny_list.sh`).
- [x] Docs updated: `docs/harnesses/antigravity.md` (§Enforcement), `scripts/deny-list.txt`
      header, and a CHANGELOG `[Unreleased]` entry under **Fixed** (the bypass shipped in 1.1.0).

## Design

**Chosen: two matchers over one spec file, union of denials, additive overlay.**

### 1. The spec file stays one file, gains a second matcher

`deny-list.txt` entries become `<binary> <subcommand...>` specs (`terraform apply`,
`az repos pr update`) rather than raw regexes. Each spec is checked two ways, and **either**
match denies:

- **Tokenized match** — split the command line on shell operators (`&&`, `||`, `;`, `|`,
  newline); per segment, strip leading `VAR=val` assignments and `sudo`/`env`/`command`
  wrappers; take `basename` of the binary; drop flag tokens (`-*`); then look for the spec's
  subcommand words as a consecutive run. Catches `kubectl -n foo delete pod x`.
- **Adjacency match** — the old behaviour, `binary[[:space:]]+subcmd`, derived from the same
  spec. Catches `sh -c "terraform apply"` and other quoted/nested forms the tokenizer can't
  see into.

**Why both.** A pure tokenizer *loses* a case that works today: `sh -c "terraform apply"` has
binary `sh`, so no spec matches and it would be allowed — a silent regression in a security
control. Layering is strictly safer than replacing. Additionally, if the binary is a shell
(`sh`/`bash`/`zsh`) and a `-c` argument is present, re-run the whole check on that argument.

> **REVISED during execution (2026-07-09).** The two requirements above are *contradictory*:
> ungated adjacency denies `echo terraform apply` (the string is adjacent in that segment), but
> a criterion demanded `echo` be allowed. Resolving it by binary-gating adjacency — only run it
> when the segment's binary already equals the spec's — silently reopened four bypasses the old
> regex caught: `bash -lc "…"`, `bash -xc "…"`, `eval "terraform apply"`, `$(terraform apply)`.
>
> The criterion was the mistake: it traded a real bypass for cosmetic convenience. Rather than
> reinstate ungated adjacency (which would deny `git commit -m "kubectl delete"` — a commit
> message this repo actually writes), the escape *vectors* are handled explicitly:
> shell re-entry now recognises bundled and glued `-c` forms (`-lc`, `-xc`, `-c"…"`), `eval` is
> treated as shell re-entry, and `$(…)` / backtick bodies are extracted and re-checked. Adjacency
> survives as a binary-gated second opinion. `echo terraform apply` stays allowed.
>
> Residual, accepted: obfuscation the matcher cannot see through (base64, a script file, a
> wrapper binary). A deny-list is a backstop against an honest agent, not a sandbox.

> **SECOND ROUND (2026-07-09).** An adversarial validator, briefed to break the matcher rather
> than confirm it, found **six** more bypass classes after every success criterion already
> passed. Two were things an honest agent types: `sleep 1 & terraform apply` (a lone `&` was
> treated as an ordinary character, not a separator — only `&&` was split) and `timeout 5
> terraform apply` (the wrapper list knew only `sudo|env|command|nohup|time`). Also `|&`,
> herestrings (`bash <<< "…"`), process substitution (`cat <(…)`), and a **rule-less** spec
> file — the guard checked the file *existed*, so `: > deny-list.txt` disarmed it as
> effectively as `rm` would have, which is the very threat the missing-file check was added
> to stop.
>
> The lesson is not "add six cases." It is that a happy-path table, an author's own adversarial
> pass, and a full green suite all agreed this was correct — and it was not. Every criterion
> passed while the control was bypassable by a background `&`. **For a security control, the
> only validation that counts is one that tries to break it.** Each of the six is now a
> named regression test, because a bypass without a test comes back.

> **THIRD ROUND (2026-07-09) — verdict was DO-NOT-SHIP.** A second adversarial pass, briefed to
> find what the *fixes* broke, returned six more. The headline is the sharpest lesson in this
> plan: **`su` and `runuser` were added to the wrapper list in round 2, and that addition was
> worse than doing nothing.** Their only real idiom is `su - deploy -c "terraform apply"`, whose
> payload the wrapper path never extracts — so the code, the plan, and the docs all claimed
> coverage that did not exist. An admitted gap is safer than a false one: the gap gets a
> `residual` note someone reads; the false claim gets trusted.
>
> Also: subshell parens and brace groups put `(` / `{` in the head slot; `then`/`do` did the same
> after a `;` split; `busybox sh -c` and `find -exec` hid the binary. And a **false positive** —
> substitution extraction ignored single quotes, so `echo '$(terraform apply)'` was denied though
> the shell would never run it. False positives matter: a deny-list that blocks legitimate work
> gets switched off, and then it protects nothing.
>
> Three adversarial rounds found 5 + 6 + 6 = **17 bypass classes**, every one after the suite was
> green. Treat that ratio as the prior for the next security control, not as a story about this one.

> **FOURTH ROUND (2026-07-09) — verdict was DO-NOT-SHIP again, and the fault was the previous
> round's fix.** To kill the `echo '$(terraform apply)'` false positive, round 3 taught
> `_deny_substitutions` to track single quotes. It did **not** teach it double quotes — unlike the
> two other scanners in the same file, which track both. So an apostrophe inside a double-quoted
> string opened a phantom single-quote region and everything after it was skipped:
>
> ```
> echo "it's $(terraform apply)"      -> ALLOW    (bash runs it)
> echo "a b $(terraform apply)"       -> DENY     (no apostrophe)
> ```
>
> **A fix for a false positive created a false negative, triggered by an English contraction.**
> That is the shape of the danger: FP fixes narrow the matcher, and narrowing is where FNs are
> born. Both directions need adversarial tests, and the three scanners must share one quote model.
>
> Round 4 also corrected `find`, which round 3 had made a blanket wrapper: `find . -name terraform
> -o -name apply` executes nothing, and denying it is the "blocks legitimate work" failure the plan
> warns about. `find` now follows only `-exec`/`-execdir`/`-ok`.
>
> **FIFTH ROUND (2026-07-09) — DO-NOT-SHIP, and again the previous round's fix was the cause.**
> Round 4 gave `find` its own payload extractor, joining the post-`-exec` tokens with spaces.
> That flattened quoting: `find . -execdir sh -c "terraform -chdir=. apply" \;` became
> `sh -c terraform -chdir=. apply` on re-parse, losing the `-c` boundary — so the *direct* twin
> `sh -c "terraform -chdir=. apply"` denied while the `find` form **allowed**. The
> flag-interposition bug this entire plan exists to close, reopened by a fix for a false positive.
>
> Fixed by re-quoting tokens when rejoining. But the fix must NOT be applied to `eval`/`trap`:
> **`eval` concatenates its arguments and re-parses**, so quoting is flattened by the shell itself
> (`eval sh -c "terraform -chdir=x apply"` really does run bare `terraform`). `find -exec` execve's
> an argv and preserves boundaries. Two constructs, opposite semantics, one line apart — verified
> against real bash with a harmless `echo PWNED` probe rather than reasoned about. Round 4 also
> fixed `$'…'` ANSI-C quoting (a `\'` there is a literal, and treating it as a terminator inverted
> quote parity) and a latent clobber: payload recursion overwrote the global `DENY_TOKENS` the spec
> loop still needed, so the spec loop now runs first.
>
> **Final tally: five rounds, 21 bypass classes, 137 assertions.** *Three* of the 21 were
> introduced by fixes for earlier findings. Every round began with a green suite. The generalisable
> rule: **a fix that narrows a matcher to kill a false positive is the most likely place to create
> a false negative** — and neither direction is visible without an adversary.

### 2. Fail closed on a missing parser

`json_get_path` returns `""` for *all three* of: no parser, key absent, parse error. The guard
cannot tell them apart, and `pretooluse.sh:51` gates the deny loop on `[ -n "$CMDLINE" ]` — so
"no parser" reads as "no command line" and the loop is skipped entirely.

Add `json_parser_available()` to `jsonutil.sh`. In `pretooluse.sh`, **after** the
`[ -n "$ROLE" ] || allow` gate, deny when no parser exists. Placement matters: only executor
delegations fail closed; an interactive `agy` on a machine without `jq` keeps working.

### 3. Overlay: tracked defaults + gitignored local, additive only

`scripts/deny-list.txt` stays **tracked and never hand-edited**, so new defaults keep reaching
every instance on sync. `scripts/deny-list.local.txt` is gitignored; the guard reads both.

**Rejected: seed a gitignored `deny-list.txt` from a tracked `.example`** (the
`config.local.sh` / `identity.md` pattern). It **freezes the security list** — `helm uninstall`
would never reach an existing instance, because their copy is untracked and `install.sh` never
overwrites it. A safety net that cannot be updated centrally is worse than the bug being fixed.

**Rejected: an un-deny syntax in the overlay** (decision A, 2026-07-09). Additive only. The
guard's whole purpose is that an executor cannot apply to running infra; an escape hatch
defeats it and fails silently. "This project has no terraform" is not something the deny-list
should express.

## Decisions (locked)

- Spec format: `<binary> <subcommand...>`, not raw regex. Both matchers derive from it.
- **Union of two matchers** (tokenized + adjacency). Either match denies. Adjacency is
  **binary-gated** (see the revision note in Design) — it is a second opinion, not the net that
  sees inside `sh -c "…"`. That job belongs to explicit re-entry handling.
- Shell re-entry: recurse into `sh`/`bash`/`zsh` `-c` payloads including bundled (`-lc`, `-xc`)
  and glued (`-c"…"`) forms; treat `eval` the same way; extract and re-check `$(…)` and
  backtick bodies. Recursion depth is capped (8) and a cap hit **denies**.
- Wrappers (`sudo`/`env`/`command`/`nohup`/`time`) make the binary's position unreliable —
  `sudo -u root kubectl …` puts a flag *value* where the binary should be. After a wrapper,
  scan the tail for the spec's binary instead of trusting the head index.
- Missing JSON parser ⇒ **deny**, but only when `AI_MEMORY_ROLE` is set.
- Missing `deny-list.txt` ⇒ **deny**. An absent rules file must not read as an empty one.
- `deny-list.txt` tracked + never hand-edited; `deny-list.local.txt` gitignored, **additive only**.
- `echo terraform apply` becomes **allowed** (today's substring regex denies it). Accepted: the
  binary is `echo`. Recorded because it is a deliberate behaviour change, not an oversight.

## Phases

- **Phase 1 — matcher.** New `scripts/deny-match.sh` (sourceable + runnable): `deny_match
  <cmdline> <specfile...>` → exit 0 + reason on match. Implements tokenize + adjacency + `-c`
  recursion. Pure bash 3.2, no parser dependency.
- **Phase 2 — guard + fail-closed.** `jsonutil.sh:json_parser_available()`. `pretooluse.sh`
  routes through `deny-match.sh`, reads both spec files, denies on missing parser (guarded
  roles only).
- **Phase 3 — specs + overlay.** Rewrite `deny-list.txt` to spec format, add `helm uninstall` /
  `helm delete`. Gitignore `scripts/deny-list.local.txt`. Header explains: never edit this file,
  add to the local one.
- **Phase 4 — tests.** Case-by-case allow/deny table (every criterion row above), fail-closed
  case (stub `PATH` without `jq`/`python3`), overlay case, dirty-tracked-guard case.
- **Phase 5 — docs.** `docs/harnesses/antigravity.md` §Enforcement, deny-list header, CHANGELOG
  under **Fixed**.

## Risks / open questions

- **The tokenizer cannot see inside quotes.** `sh -c "terraform  -chdir=x apply"` (flag
  interposition *inside* a `-c` payload) escapes both matchers: the recursion re-tokenizes, but
  adjacency fails on the interposed flag and the tokenizer sees the payload as one argument
  unless it is re-split. Phase 1 must re-tokenize the `-c` payload, not just re-grep it.
  If that proves fiddly, record the residual gap rather than pretending it is closed.
- **This is one harness.** Codex gets its infra-deny from an optional out-of-repo execpolicy
  file; Claude subagents get the deny-list restated in the prompt only, with no gate. Fixing
  the list does not fix the coverage asymmetry — that is the backlogged manifest `guard`
  capability (`396f6850-c619-81b2-bbf2-f1be2352db0d`). Fix the list first: a correct list wired
  into one harness beats a bypassable list wired into three.
- **A deny-list is a backstop, not a security boundary.** It matches command *text*; a
  determined executor can obfuscate (base64, a script file, a wrapper binary). It exists to stop
  an honest agent from doing the obviously-forbidden thing. Do not let hardening it imply it is
  a sandbox.
- Malformed JSON on stdin still yields empty `CMDLINE` with a parser present, and for
  `AI_MEMORY_ROLE=task` that reads as "no command line" ⇒ allow. Out of scope; note it.

## Round-5/6 finding — CLOSED 2026-07-09 (was the resume point)

**This bypass is now FIXED** (`_deny_wrapper_reachable_payload` + the wrapper-tail scan in
`_deny_match_loaded`); 18 regression assertions cover it and its variants. Retained below as the
record of what it was and why the fix has the shape it does.**

**The bypass — a transparent wrapper with a value/flag argument, then a bundled `sh -c`:**

```
timeout 5 sh -c "terraform apply"    -> ALLOW   (bash runs it)
flock /tmp/l sh -c "terraform apply" -> ALLOW
nice -n 10 sh -c "terraform apply"   -> ALLOW   (probe-confirmed: `nice -n 10 sh -c "echo PWNED"` prints PWNED)
```

Both halves are independently covered and tested — `timeout 5 terraform apply` DENIES,
`sh -c "terraform apply"` DENIES — but their **composition** slips through.

**Mechanism (instrumented by the validator, confirmed here):** `_deny_command_start` skips a
wrapper by advancing exactly ONE token, landing on the wrapper's own positional value (`5` in
`timeout 5 …`). So `primary=5`, `_deny_takes_c_payload("5")` is false, and the `sh -c` payload
is never extracted. The `DENY_WRAPPED` tail-scan then looks for `terraform` as a token
*basename*, but the quoted payload `terraform apply` is one token whose basename is
`terraform apply` ≠ `terraform`, so it misses too.

**Not a round-5 regression** — it is a pre-existing gap in the wrapper command-start logic that
none of the five rounds touched. `flock /tmp/tf.lock sh -c "cd envs/prod && terraform apply"` is
a natural honest-agent idiom, so it is in scope for the stated threat model.

**The fix:** when `DENY_WRAPPED` is set, the tail scan must not only look for a spec binary — it
must also recognise a payload-bearing binary anywhere in the tail and extract *its* payload.
Equivalently: after skipping a wrapper, re-run the per-segment head analysis from the first real
command token rather than trusting `idx`.

**CORRECTED by round 6 (Fable) — the payload-binary set reachable THROUGH a wrapper is
`sh`/`bash`/`zsh`/`su`/`runuser` (with `-c`) + `find -exec`. It must NOT include `eval`/`trap`.**
`eval` and `trap` are shell builtins with no on-disk executable, so a wrapper cannot exec them —
`nice -n 10 eval "…"` errors `nice: eval: No such file or directory` and runs nothing (probe-
verified). So `timeout 5 eval "terraform apply"` does **not** run terraform, and denying it (as an
earlier draft of this sketch required) is a **false positive**. Keep `eval`/`trap` only as
*direct-head* handlers, never in the wrapper-tail set. The "re-run head analysis from the first
real token" phrasing hits this trap too, because head analysis classifies `eval` and extracts its
payload — so the re-run must exclude the eval/trap branch when it was reached via a wrapper.

**Regression tests the fix must add** (all currently ALLOW, all must flip to the stated verdict):
- `sudo -u root sh -c "terraform apply"` → DENY. **HIGHEST VALUE**: `sudo -u` is the canonical
  run-as-user idiom, and its *bare* form `sudo -u root kubectl delete pod x` already has a passing
  DENY test — so the composition *looks* covered and is not. The round-5 write-up framed this bug
  around `timeout/flock/nice` and never named `sudo`, the most natural wrapper of all.
- `stdbuf -oL sh -c "terraform apply"` → DENY · `xargs -n1 sh -c "terraform apply"` → DENY ·
  `watch -n5 sh -c "terraform apply"` → DENY (each masked by a passing bare-form sibling test).
- Stacked wrappers: `nice -n 10 ionice -c2 sh -c "terraform apply"` → DENY ·
  `time nice -n 10 sh -c "terraform apply"` → DENY.
- `nice -n 10 bash -lc "terraform apply"` → DENY · `nice -n 10 su - deploy -c "terraform apply"` → DENY.
- **Benign twins that must stay ALLOW:** `timeout 5 sh -c "echo hi"`, and critically
  **`timeout 5 eval "terraform apply"` → ALLOW** (locks in that the eval-through-wrapper false
  positive is never introduced).

**Accepted inherent limitation (do NOT try to fix — document as deliberate, like `echo`):**
`eval "$(echo terraform apply)"` runs terraform, but the static body `echo terraform apply` is
benign — the danger is only in echo's *runtime output*. Undecidable for a text-matcher; same
class as base64 / a script file. The threat model is an honest agent, not an attacker.

### State at pause
- Branch `fix/deny-list-hardening`, committed + pushed (`677837e`). NOT merged, NO PR.
- 137 assertions, full suite 34/34 green — **but green does not mean done**: every one of the
  found bypasses passed a green suite first. The open ones have no test yet, by deliberate choice
  (fixing them is the resume task).
- **Six rounds, 23 bypass classes.** 3 were introduced by fixes for earlier findings. Round 6
  (Fable — a different model family from the five Opus/Sonnet rounds) found the `sudo -u ∘ sh -c`
  variant AND caught that this plan's own fix sketch would have introduced a false positive. That
  is the case for cross-*family* validation, not just cross-model.
