# Upgrading

## How instances upgrade

Instances upgrade through `scripts/sync-system.sh`. The channel is per instance, set in
gitignored `config.local.sh` with `AI_MEMORY_CHANNEL`.

| Instance | `AI_MEMORY_CHANNEL` | Gets |
|----------|---------------------|------|
| dev machine (the source checkout) | `dev` | ff-pull of the tracking branch |
| dogfood instance | `dev`, or one-shot `--to <ref>` | main / branches on demand |
| stable instance | `release` (default) | latest stable `v*` tag only; aborts when no stable tag exists |

A release-channel instance aborts with an actionable message if no stable `v*` tag
exists yet.

> **Do not point an instance at a tag earlier than `v1.1.0`.** At `v1.0.0`,
> `identity.md` was still tracked, so checking it out **silently overwrites** a
> personalised `identity.md` with the tag's copy — no conflict, no warning, and a
> clean tree afterwards. See [1.1.0](#110).

Precedence: `config.local.sh` is sourced after the process environment exists, so
values exported there win over one-off environment prefixes. To change an
instance's channel, edit `config.local.sh`; `AI_MEMORY_CHANNEL=release sync-system.sh`
will not override a configured `AI_MEMORY_CHANNEL`.

Common invocations:

```bash
sync-system.sh              # channel default
sync-system.sh --to v1.3.0  # check out an older tag for this run
sync-system.sh --to origin/main  # dogfood current dev state once
sync-system.sh --to <sha>   # bisect a specific commit
sync-system.sh --dry-run    # preview the chosen checkout and migrations
```

`--to` is ephemeral. It never changes the channel, so the next plain
`sync-system.sh` snaps the instance back to its channel default. A release-channel
consumer ends on a detached HEAD at the selected tag, and consumer instances never
commit.

`--to <branch>` checks out that ref as-is and does not fast-forward it. To dogfood
the current dev state, name the remote-tracking ref, for example
`--to origin/main`.

A downgrade with `--to` rolls back code only. Data stays migrated because
`.applied-version` is a high-water mark and older migrations do not re-run; this
is safe because of the [N/N+1 rule](#the-two-standing-rules).

A downgrade can still clobber a file that the older tag tracked and the newer one
does not. `--to v1.0.0` overwrites `identity.md`, because `v1.0.0` tracks it. Back
it up first.

## Converting an existing instance to the release channel

For an instance that was cloned before releases existed and still tracks `main`.
Run everything from the instance's own memory tree (`~/.claude-memory` by default;
`echo "$MEMORY_DIR"` if you are unsure).

```bash
cd ~/.claude-memory
```

**1. Confirm what you have.**

```bash
git branch --show-current          # probably "main"
git status --porcelain             # must be empty of TRACKED changes
git fetch --tags origin && git tag -l 'v*' | sort -V | tail -1
```

A dirty *tracked* file aborts the sync. Untracked and git-ignored files never do —
your `projects/`, `domain/`, `tasks/`, `config.local.sh`, and `identity.md` are all
ignored, so they are safe and are **not** touched by any checkout.

**2. Set the channel.** `release` is the default, so an instance with no
`AI_MEMORY_CHANNEL` is already a release-channel consumer — doing nothing is a
choice, not a no-op. To be explicit, add to the gitignored `config.local.sh` that
`install.sh` created:

```bash
echo 'export AI_MEMORY_CHANNEL="release"' >> config.local.sh
```

Remember the precedence rule above: a value in `config.local.sh` beats an
environment prefix. Editing the file is the only way to change an instance's channel.

**3. Preview, then sync.**

```bash
bash scripts/sync-system.sh --dry-run     # fetches tags, then reports channel + target tag; no checkout, no migrations
bash scripts/sync-system.sh
```

The sync checks out the latest stable tag, runs any pending migrations, and re-runs
`install.sh` to rebuild the harness wiring from that version.

**4. Verify.**

```bash
git describe --tags        # -> v1.1.0
cat .applied-version       # -> highest migration version applied, if any ran
```

**Afterwards the instance is on a detached HEAD** at the tag. That is intended.
Consumer instances never commit, and `git pull` will fail there — use
`sync-system.sh` to move between versions, not raw git. To return the instance to
tracking a branch, set `AI_MEMORY_CHANNEL=dev` in `config.local.sh` and sync again;
the dev path recovers the tracking branch from a detached HEAD automatically.

## The two standing rules

1. Migrations are **forward-only and idempotent**. There are no down-migrations.
2. **N/N+1 compatibility**: a migration must not break the previous release's code.
   Old code plus new data must still work. Ship the compatibility fallback in
   release N, then flip in N+1. A breaking (major) release may ship the new
   reader and its migration together; its upgrade notes say so (3.0.0 does).

Rule 2 exists because a downgrade with `--to` moves code back but leaves data
migrated: `.applied-version` is a high-water mark, and the runner never re-runs an
older migration. N/N+1 compatibility is what makes that safe.

If `.applied-version` is absent, the runner treats the instance as `0.0.0`, so
the first upgrade runs the full migration history. That is safe because
migrations are idempotent; see [migrations/README.md](migrations/README.md) for
the migration contract.

The `.agents/memory-project` marker migration is the worked example: first ship the
new reader with the legacy `.claude/memory-project` fallback, then bulk-migrate the
marker after old readers can tolerate the new state.

## The semver rule of thumb

MAJOR: breaks an instance without a migration, or incompatibly changes the
`MEMORY_DIR`, marker, or manifest contracts.

MINOR: new features, a new harness, additive manifest keys, or any N-1-compatible
migration.

PATCH: fixes.

## What a migration may touch

A migration may touch instance data and harness config, not engine code. See
[migrations/README.md](migrations/README.md) for the full migration contract.

## Distribution

Releases are git tags; no downloadable archive is provided. A zip distribution for
external users is deliberately deferred.

## Per-version upgrade notes

Released versions that need manual steps or carry a migration get one section:

```markdown
## <version>
```

`scripts/tests/test_upgrading_doc.sh` enforces that every
`migrations/<version>-<slug>.sh` file has a matching `## <version>` section here.
The reverse does not hold: a version may need a manual step without shipping a
migration — as the next section does.

## 3.0.0

**Initiatives move to a one-line status, a `scope:` line, Closed rows and a
progress log. Breaking: the old format no longer parses.**

What changes in an initiative file:

- A Target status is one line,
  `- status: <open|blocked|done|closed> · next: <session — action> · blocked_by: <…|none>`
  (`done` / `closed` may stand alone). The Target's description moves to its own
  `- scope:` line. `- next_actor:` is gone.
- Finished (`done`) Targets are rows of a `### Closed` table at the end of
  `## Targets`: `| <id> | <closed date> | <jira> | <outcome> |`. A row counts as
  `done`: `depends_on` edges to it resolve and are satisfied. An abandoned
  Target is never a row: it keeps its heading with `- status: closed`, and a
  dependency on it is never satisfied.
- Progress history lives in `initiatives/logs/<slug>.md`, append-only, with
  dated entries tagged by Target id.
- `initiative-render.sh <slug> --write` keeps three generated blocks in the file:
  `## Now`, `## Environment matrix` (with `envs:`) and `## Current rules`
  (grouped by the `topics:` enum).
- `lint-memory.sh` reports the old shape (`next_actor:`, `<state> — prose`) as an
  ERROR, and `initiative-status.sh` refuses such a file and names this migration.

Migration `3.0.0-initiative-format.sh` runs automatically via `/sync-system`
(`sync-system.sh`). It rewrites each `initiatives/*.md` of `kind: initiative`,
active and closed (not `_template.md`, symlinks, `archive/`, `logs/` or
`.state/`), that still has an old-format Target:

- **Backup first.** Before its first write it saves a byte-identical copy to
  `initiatives/.state/<slug>.pre-3.0.0.md`. An existing backup is never
  overwritten.
- An open or blocked `<state> — <prose>` status (also `<state> <date> — …` and
  `<state> (…) — …`) becomes `- status: <state> · next: <old next_actor value,
  or none> · blocked_by: none`. The prose moves verbatim to `- scope:` (a date
  or `(…)` before the ` — ` leads it, joined by a space:
  `- scope: 2026-11-16 <prose>`), except
  `Progress: …` and `Was: …` segments, which go to the log. A segment starts at
  `Progress:` or `Was:` (at the start of the prose or after a space) and ends
  before the next `Progress:` / `Was:`, before a sentence that opens with a
  label, or at the end. A label is `. ` followed by a capitalised word, up to
  three more lower-case words (each optionally after a comma) and a colon,
  `[A-Z][a-z]+(,? [a-z]+){0,3}:`: `Remaining:`, `Next, in repo:`, `Seed:`,
  `Earlier:` end a segment; `P2 done 2026-11-16:` and a lower-case `next:` do
  not. Text after a label stays in `scope:` (the remaining pieces are joined
  with one space). Every `next_actor:` line is removed; the first one's value
  becomes `next:`, and when a Target has more than one, all of them go to the
  log. Every other Target line stays as written.
- In a Target with a `next_actor:` line, a status with no ` — ` and no ` · `
  whose first word is `open`, `blocked` or `closed` (`- status: open`,
  `- status: blocked waiting on vendor`) is converted too: the first word is the
  state and the remaining words move verbatim to `- scope:` (no words, no scope
  line). `closed` follows the abandoned rule below. A status whose first word is
  outside `open|blocked|done|closed` (`in progress — …`) is reported, not
  converted.
- A `done` Target, including a bare `done` or `done <words>`, collapses into a
  Closed row (the date when the word after `done` is a `YYYY-MM-DD` date, else
  `-`; the `jira:` value; outcome `see log`), under the header
  `| id | closed | jira | outcome |` when the migration creates the table. Its whole original block goes to the log verbatim. This includes a
  new-format `done` Target that still has a `next_actor:` line.
- A `closed` (abandoned) Target is not collapsed, because a Closed row counts
  as done and would unblock its dependents. An old `closed[ <date>] — <prose>`
  status (or `closed <words>`) is converted like an open one but keeps its
  state: the prose (minus `Progress:` / `Was:` segments) moves to `- scope:`
  (`- scope: 2026-11-01 abandoned …` for a dated one), the status becomes
  `- status: closed`, and every `next_actor:` line moves to the log. A
  new-format `closed` Target only loses its `next_actor:` line(s) to the log.
  Its dependents stay unsatisfied, as before the migration.
- A Target without a status (allowed for `software_adw`) keeps none; its
  `next_actor:` line moves to the log.
- Log entries read `## <date> — <target-id> (migrated by 3.0.0)` in
  `initiatives/logs/<slug>.md`, created with a short header when absent. The
  log is written before the initiative; an entry already in the log (same text
  after the date) is not appended again, so a rerun after an interrupted sync
  does not duplicate it. New backup and log files take the initiative's mode.
- A `SUPERSEDES D<n>` line under entry `D<m>` adds the forward pointer `→ D<m>`
  to `D<n>`'s head. No other decision text is edited.
- Frontmatter gains `topics: []` when absent. `envs:` is not added.
- When the result parses, it runs `initiative-render.sh <slug> --write` to
  insert the generated blocks.

Text is moved, never deleted: compare the file plus its log against the backup.
The staleness snapshot (`.state/<slug>.snapshot`) is left alone; a collapsed
`software_adw` Target raises no stale alert. A second run changes nothing.

**Read the report printed during the sync.** Per file it gives the counts
(Targets converted, collapsed, log entries, pointers added) and:

- `candidate: D<m> amends D<n> — add an AMENDS line by hand` for every prose
  "amends D<n>" / "amended by D<n>" it found. It never writes `AMENDS` itself.
- `unmatched line left unchanged (fix by hand): <file>:<line>: …` for a status
  it could not convert, such as a state outside `open|blocked|done|closed` or a
  second `- status:` line, and for a status elsewhere in a migrated file that
  breaks the new grammar (`done (no dash)`). Line numbers are those of the
  rewritten file. The whole Target is left as written, so lint ERRORs and `initiative-status.sh`
  refuses the file until you fix it. See *Recovering a refused file* below.
- `fences skipped` when the rewritten file still does not parse.
- `<file>:<line>: status does not match the 3.0.0 grammar; fix by hand (lint ERRORs it)`
  for a file it does not rewrite (no `next_actor:` line, no old-shape status)
  whose statuses break the new grammar, such as `- status: blocked on vendor
  reply`. That file is left byte-identical, with no backup and no log; the line
  number is the file's own. `lint-memory.sh` ERRORs the line and
  `initiative-status.sh` refuses the file until you fix it.
- `note: … SUPERSEDES D<n>, which names a malformed head (left unedited)` when
  the superseded entry's head does not parse, so no pointer was added.

**Recovering a refused file.** `/sync-system` runs the migration once; it does
not run it again after you fix a line. Fix each reported line by hand, usually
by changing the state word to `open`, `blocked`, `done` or `closed`
(`in progress — half done` becomes `open — half done`) and leaving the
Target's `next_actor:` line in place, then re-run the script against your
memory directory:

```bash
MEMORY_DIR=<memory dir> REPO_ROOT=<engine checkout> \
  bash <engine checkout>/migrations/3.0.0-initiative-format.sh
```

It is idempotent: converted Targets, logs and backups are left alone, and the
lines that now match are converted. Once the file parses, the migration runs
`initiative-render.sh <slug> --write` itself. If you rewrote the Target fully
into the new format instead, the re-run has nothing to convert; run
`bash scripts/initiative-render.sh <slug> --write` yourself.
`initiative-status.sh` gives the same advice when it refuses an old-format file.

**Then do the hand pass.** A migrated initiative is valid but thin; lint WARNs
mark each Target that still needs it:

1. Add a `topics:` enum to frontmatter and a `topic:` continuation line on each
   live decision.
2. Add `AMENDS D<n>` lines for the reported candidates you agree with, plus the
   `→ D<m>` pointer on each amended entry.
3. Split a Target that spans environments into `@env` Targets
   (`<project>/<name>@<env>`) and list the environments in frontmatter `envs:`.
4. Replace each bare `next: <actor>` with a real `<session — action>`.
5. Trim each `scope:` to what the Target delivers; history belongs in the log.
6. Fill in the Closed rows' outcomes (and dates where the migration wrote `-`).
7. Run `bash scripts/initiative-render.sh <slug> --write`, then
   `bash scripts/lint-memory.sh`.

To retry from scratch, copy the backup over the file and run the migration again
(`MEMORY_DIR=… REPO_ROOT=… bash migrations/3.0.0-initiative-format.sh`); remove
the `migrated by 3.0.0` entries from the log first.

**N/N+1 exemption.** This is a breaking release: the new reader and the
migration ship together in 3.0.0, and the old format is dropped in the same
release. Rule 2 of [The two standing rules](#the-two-standing-rules) does not
hold here. Downgrading to 2.x after the migration leaves initiatives the 2.x
reader does not understand; restore from the `.pre-3.0.0.md` backups if you
must go back.

## 1.7.0

**Initiative decision status is a dated field, not an id suffix.**

Entries in `## Decision stream` now read
`- D<n> <proposed|confirmed|rejected|superseded|retired> <YYYY-MM-DD> — <text>`.
The id never changes; `D<n>-proposed` references elsewhere still read as `D<n>`.

Migration `1.7.0-decision-status-field.sh` runs automatically via
`sync-system.sh`. In each `initiatives/*.md` of `kind: initiative` (not
`_template.md`, `.state/` or `archive/`) it rewrites suffix-shape heads
(`D<n>:`, `D<n>-proposed:`, `D<n>-rejected:`, `D<n>-proposed (<date>):`,
`D<n>-proposed *(<qualifier>)*:`, `D<n> (<qualifier>):`, `D<n>a:`) to the field
shape, normalises `[<date>]` to `<date>` and `shipped` to `confirmed`, and, when
it rewrote at least one head, sets `legacy_through: D<max id>` in frontmatter.
Code-fenced examples (``` or ~~~) are never rewritten. A qualifier moves to the start of the text as `(<qualifier>)`. Decision text,
continuation lines and every other line are untouched; a second run changes nothing.

**Hand-resolve what it reports.**

- Heads it does not fully recognise (mixed values such as `D15 confirmed/proposed`)
  are left as is and printed during the sync; fix them by hand.
- A `-proposed` with a same-number bare `D<n>:` twin becomes `superseded`.
- A migrated lettered id (`D12a`) has no date and is never legacy: add the date
  and its `evidence:` / `unconfirmed:` line.
- A `-proposed` whose confirmation sits under a lettered id (`D23` / `D23a`)
  stays `proposed` (legacy, no WARN): resolve it by hand, usually `superseded`.
- A `-proposed` with an already-field-shaped `D<n> confirmed …` twin raises the
  duplicate-id WARN: set the original to `superseded`.
- An initiative where nothing was rewritten (already field-shaped, or only reported
  lines) gets no `legacy_through:`; if lint
  flags its older entries, add `legacy_through: D<max id>` to its frontmatter.
- Accepted risk: if the applied-version marker is lost and the migration replays, a
  newer initiative holding a stray old-format head gets `legacy_through:` and its
  entries skip the date/evidence/unconfirmed checks; remove that line by hand.

Entries at or below `legacy_through:` are exempt from the date, `evidence:` and
`unconfirmed:` checks. Check with:

```bash
bash scripts/lint-memory.sh
```

It should report no `decision-stream` WARN once those are fixed.

## 1.6.0

**Orchestrator doctrine split into a tracked core plus a local overlay.**

`orchestrator.md` — the per-instance file seeded once from
`templates/orchestrator.template.md` and never updated again — is retired.
Workflow doctrine now ships as a tracked core, `doctrine/orchestrator.md`,
updated on every sync like the rest of the engine. Personal additions go in a
new gitignored overlay, `orchestrator.local.md` — additive, never overwritten,
precedence `identity.md` > `orchestrator.local.md` > `doctrine/orchestrator.md`
> project memory.

Migration `1.6.0-orchestrator-core-overlay.sh` runs automatically via
`sync-system.sh`. If you have an existing root `orchestrator.md`, it is backed
up (renamed, not deleted) to `orchestrator.md.pre-1.6.0`, and an empty
`orchestrator.local.md` is seeded if you don't already have one. **You must
port any personal rules from the backup into `orchestrator.local.md` by
hand** — the migration does not diff or merge the old file, since it is both
ahead of and behind the current template in ways a script cannot judge.

Until you migrate (or on an instance that only `git pull`s without running
`sync-system.sh`), a legacy root `orchestrator.md` keeps being injected as
before, with a one-line deprecation notice in the breadcrumb telling you to move
its personal rules into `orchestrator.local.md` and delete it. Once
`orchestrator.md.pre-1.6.0` exists the instance counts as migrated: a root
`orchestrator.md` found alongside it (for example re-seeded by a rollback to
1.5.x) is **not** injected. Neither is a root file shadowed by a non-blank
`orchestrator.local.md`. In both cases harnesses with a per-prompt breadcrumb
(Claude, Codex, Antigravity — not Copilot) name it as `orchestrator-ignored` so
you can port or delete it. This fallback is temporary — it exists for one
release only.

`harnesses/claude/CLAUDE.md` is now a small hook-failure stub: it carries no
doctrine of its own, only an instruction to read `doctrine/orchestrator.md` and
`orchestrator.local.md` directly if the `<memory:orchestrator>` injection is
ever missing from context. No consumer action needed — it is reached via the
same `@`-import shim as before.

## 1.4.0

**Workflow doctrine moved from `identity.md` to `orchestrator.md`.**

> **Superseded in 1.6.0.** `orchestrator.md` itself is retired — see the
> [1.6.0](#160) section above. The doctrine-vs-`identity.md` split described
> below still holds; only the file names changed.

New installs seed `orchestrator.md` from tracked `orchestrator.template.md`.
Existing instances are not rewritten: move or delete your `## Orchestration`
and `## Cross-project relationships` sections from `identity.md` into
`orchestrator.md` by hand, then keep `identity.md` focused on voice, hard rules,
and defaults. Until you trim `identity.md`, the same doctrine is injected twice;
that duplication is harmless but noisy.

**Codex's `~/.codex/AGENTS.md` becomes a hand-owned static base.**

The memory system no longer generates `~/.codex/AGENTS.md`. The dynamic memory
tree (identity, orchestrator, project, index, domain, working) now injects live through Codex's
`SessionStart` hook — the same model Antigravity and Claude already use — so a
plain `codex` (no alias, no wrapper) gets full memory. `~/.codex/AGENTS.md` is left
as a hand-owned static base for permanent Codex-specific workflow rules or personal
instructions.

Migration `1.4.0-codex-agents-handoff.sh` converts an existing machine-built
`AGENTS.md` in place. It is **header-keyed**: only a memory-generated file carries
the `Generated by codex-mem` header, so a file you wrote by hand is left
byte-identical. When it finds a generated file it seeds the hand-owned base from
your `~/.codex/AGENTS.local.md` overlay (or a stub if you had none) and retires the
now-redundant overlay to `AGENTS.local.md.retired` (renamed, not deleted).

Interactive Codex re-prompts `/hooks` trust once when a hook command changes — the
`SessionStart` command does change here, so trust the ai-memory hooks again after
upgrading. Headless executor runs bypass trust automatically
(`--dangerously-bypass-hook-trust`) and are unaffected.

`arm_recompact.sh` survived this release as a compatibility shim (it delegated to
the shared session-start script) so a stale `~/.codex/hooks.json` from a manual
`git pull` that hadn't re-run `install.sh` kept working. It has since been deleted.
Re-running `install.sh` (or `sync-system.sh`, which calls it) sweeps the stale
entry — that sweep is what makes the deletion safe, and it is still in place.

**The canonical slash-command store moved: `harnesses/claude/commands/` → repo-level
`commands/`.**

The store is harness-neutral (Claude symlinks it natively; Codex/Antigravity wrap
the same bodies as skills; `doc`-surface harnesses render a reference), so it now
lives beside the other neutral stores (`skills/`, `agents/`). Upgrading through
`sync-system.sh` self-heals: `install.sh` re-links `~/.claude/commands/*` at the
new paths. A raw `git pull` that skips `install.sh` leaves those symlinks dangling
(slash commands vanish) until `install.sh`/`sync-system.sh` runs.

**Claude's `SessionStart` hook script moved — a manual `git pull` breaks session
start until `install.sh` re-runs.**

The same relocation moved Claude's session-start script from
`harnesses/claude/hooks/session_start_memory.sh` to the shared
`scripts/hooks/session_start_memory.sh`. A live `~/.claude/settings.json` that
still points at the old path fails every session start with
`no such file or directory` (the memory base silently stops loading).

Upgrading through `sync-system.sh` fixes this automatically: it re-runs
`install.sh`, whose settings merge sweeps ai-memory hook entries by script name
regardless of path and re-registers them at the current location — including the
`env MEMORY_DIR=... AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=SessionStart`
prefix the shared script expects. No manual step.

Only an instance updated with a raw `git pull` that skips `install.sh` hits the
error. Recovery is the same either way: run `install.sh` (or `sync-system.sh`).

## 1.1.0

**`identity.md` is no longer tracked. Back it up before upgrading.**

It is now per-instance and git-ignored, like `config.local.sh` and `skills.toml`.
`install.sh` seeds it from the tracked `identity.template.md` whenever it is missing.

Tracking it was a trap: `install.sh` tells you to edit `identity.md`, and
`sync-system.sh`'s dirty-tracked-file guard then aborts every subsequent sync. An
instance was bricked the moment it was personalised.

This is not only a `sync-system.sh` concern. `identity.md` is removed by **any
checkout that crosses this commit** — `git pull`, `git reset --hard`, or switching
branches — because at that moment the file is still tracked in your old `HEAD`. A
dev or dogfood checkout that never runs `sync-system.sh` is affected too.

What happens when you cross `1.1.0`:

| Your `identity.md` | Result |
|---|---|
| Edited (differs from the last tracked version) | `sync-system.sh` **aborts** on the dirty guard; a plain `git pull` refuses to overwrite. Save your copy, then `git checkout -- identity.md`, pull, and restore it. |
| Unedited | Git deletes it during checkout; `install.sh` reseeds the generic template. Your previous content is recoverable — see below. |
| Absent (fresh install) | Seeded from the template. Nothing to do. |

The unedited row is the dangerous one: it is **silent**. Nothing warns you, and
`install.sh` cheerfully replaces your file with the stock template.

**A migration cannot do this for you.** The runner executes *after* checkout, by
which point git has already removed the file — so this is a manual note, not a
`migrations/1.1.0-*.sh`. Any future removal of a tracked file has the same
constraint.

Recover the old content at any time — the blob is still in history, and `identity.md`
is now git-ignored, so writing it back leaves the tree clean:

```bash
git show v1.0.0:identity.md > identity.md
```

Verify it landed intact:

```bash
cmp <(git show v1.0.0:identity.md) identity.md && echo restored
```
