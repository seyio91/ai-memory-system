---
plan: skill-recurse-field
status: active
created: 2026-07-14
owner: claude (orchestrator)
task_provider: notion
task_ref: 39df6850-c619-8156-827e-ef548175f277
---

# Plan — `recurse` field: pull many skills from one repo subpath

## Goal

Add `recurse = true` to a `skills.toml` `[[skills]]` entry so one declaration (`url` + `ref` + `path`)
materializes every `SKILL.md` under `path` as its own skill, replacing one-entry-per-skill (grafana ships
**46**, first-party `agent-skills` **5**). Stay exactly as reproducible and prunable as explicit entries.

## Success criteria

1. A single `recurse = true` entry pointing at grafana `skills/` materializes all N skills under it
   (verified: 46, at `skills/<cat>/<skill>/SKILL.md`), each as a flat `.skill-cache/<name>` dir linkable
   by `link-skills.sh` unchanged.
2. **Reproducibility:** after first resolve, the lockfile holds one row per discovered skill (shared repo
   sha). A plain `resolve-skills.sh` (no `--update`) is a pure per-skill cache-hit — no network, no re-glob —
   and yields a byte-identical set. Expansion (`find`) runs only on first-resolve / `--update`.
3. **Collision:** two sources — or a recurse child + an existing authored/explicit skill — resolving to the
   same final name is a **hard error (non-zero exit)** at resolve, naming both origins. `prefix` resolves it.
   (Real case: grafana ships `grafana-oss` + `prometheus`, which already exist as authored skills.)
4. **Prune:** `--update` reconciles the cache to the resolved set and deletes cache dirs whose origin source
   no longer yields them (source entry removed, or upstream/`exclude` narrowed). `--dry-run` previews the
   deletions. A plain resolve never deletes.
5. **exclude:** `exclude = [globs]` on a recurse entry omits matching skills from the expanded set (matched
   against each skill's container-relative dir path). Excluded skills are absent from lock, cache, and are
   pruned if previously present.
6. A non-recurse `[[skills]]` entry behaves exactly as today (backward compatible).
7. Fixture-repo test suite (below) passes.

## Design

**Schema** — new optional keys on `[[skills]]`; `name` becomes optional when `recurse = true`:
```toml
[[skills]]
url     = "https://github.com/grafana/skills.git"
ref     = "v1.4.0"                 # doctrine: recurse SHOULD pin a tag/sha (moving ref => non-deterministic set)
path    = "skills"                 # container; "" / omitted = repo root
recurse = true
prefix  = "grafana-"               # optional; prepended to each discovered name (collision escape hatch)
exclude = ["**/experimental/*"]    # optional; omit matching skills (container-relative dir-path globs)
```

**Resolver — the `recurse` branch in `resolve_one`** (`scripts/resolve-skills.sh`):
1. Fetch + `sparse-checkout set --no-cone "$path"` as today. **Verified:** this materializes the full
   subtree (grafana → all 46 `SKILL.md`), so no broader pattern is needed.
2. `find "$src" -name SKILL.md`, **pruning descent once a dir matches** (a skill dir is a leaf boundary —
   stops a skill's own `references/SKILL.md` from registering as a second skill). Recursive, not
   `-maxdepth 1` (grafana nests one category level: `skills/<cat>/<skill>/`).
3. Apply `exclude` globs against each match's **container-relative dir path** (e.g. `grafana-cloud/testing`)
   — drop matches.
4. Identity per surviving match = frontmatter `name:` if present, else parent basename, then `+ prefix`.
   Validate charset with the existing `resolve_one` name guard. (Verified: grafana always carries `name:`,
   equal to basename — basename fallback is safe.)
5. `cp -R` each into `.skill-cache/<name>`, strip `.git`, and lock **one row per discovered skill**.

**Lockfile — record the expanded set + origin** (`lock_set`): add a **6th `origin` column = `url#path`** so a
removed source's children can be pruned by origin rather than inferred. On plain resolve, lock rows replay as
per-skill cache-hits (never re-glob); `find`/expansion runs only on first-resolve / `--update`.

**Prune (`--update`-only + `--dry-run`):** after a full `--update` resolve, delete `.skill-cache/<name>` dirs
not in the freshly-resolved set, keyed by `origin` for recurse sources. Plain resolve never deletes.
`--dry-run` prints the would-delete set. (Chosen over a dedicated `--prune` flag / prune-on-every-resolve to
avoid a surprising silent delete on a routine re-link.)

**Parser / validation edits** (`_manifest_tsv` + resolve/list loops): emit `recurse` ("1"/"") and `prefix`,
`exclude` columns; make `name` optional when `recurse=1`; the `[ -n "$name" ] || continue` guards must NOT
skip a nameless recurse row (a recurse row is keyed by `url`+`path`, not `name`). `path` may be empty.

**`--list` / `--dry-run`:** pre-resolution a recurse row can't enumerate without fetching — `--dry-run` shows
`would-expand <url>@<ref> [path]`; `--list` reads the expanded children from the lock (post-resolution),
keeping the existing one-line-per-skill output.

*Alternatives rejected:* separate source `kind` instead of a `recurse` flag (user specified a field —
smaller schema delta, backward compatible); last-writer-wins on collision (silent shadowing is the exact
drift class this repo keeps getting bitten by); infer prune scope from url alone (breaks when two entries
share a repo at different `path`s — hence the `origin = url#path` column).

## Decisions (locked)

- **Prune trigger:** `--update`-only + `--dry-run` preview. Plain resolve never deletes.
- **Collision:** hard error (non-zero exit) naming both origins; explicit `prefix` is the escape hatch. No
  auto-prefix, no last-writer-wins.
- **Scope:** core (`recurse` + `prefix` + lockfile-captured expanded set + collision hard-error +
  origin-tracked `--update`-prune) **plus `exclude` globs** (extended past the investigation's defer).
- **Reproducibility (non-negotiable):** lockfile records the concrete expanded list; a recurse entry should
  pin `ref` to a tag/sha.

## Phases

_(decomposition — fill during execution)_

## Risks / open questions

- **`exclude` match target** — specced as container-relative **dir-path** globs (e.g. `**/experimental/*`),
  not skill-name globs. Confirm during Phase 1 that this is the intuitive surface; adjust the fixture if not.
- **Moving `ref` + recurse** = non-deterministic set by construction. Mitigated by lock-captured expansion +
  the pin-your-ref doctrine, not enforced. Consider a soft warning when a recurse entry's `ref` is a branch.
- **Prune blast radius** — `--update` deleting cache dirs is data-loss-adjacent; `--dry-run` is the guard.
  Ensure prune only ever touches `.skill-cache/` (never authored `skills/`).

## Test surface

Fixture repo via `file://` url (resolver already supports) with a nested skill tree. Assert:
(a) N skills materialize from 1 recurse entry; (b) plain re-resolve is a pure cache-hit, set unchanged;
(c) a name collision → non-zero exit; (d) removing the source `--update`-prunes its children;
(e) a nameless recurse row resolves via frontmatter/basename; (f) `exclude` omits matching skills (absent
from lock + cache, pruned if previously present).
