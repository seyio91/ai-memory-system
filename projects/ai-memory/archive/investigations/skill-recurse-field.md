---
doc: skill-recurse-field
kind: investigation
status: open — review + design (2026-07-14)
created: 2026-07-14
owner: claude (orchestrator)
task_ref: 39df6850-c619-8156-827e-ef548175f277
---

# Investigation — `recurse` field: pull many skills from one repo subpath

Trigger: `skills.toml` declares remote skills one `[[skills]]` entry at a time (`name` + `url` + `ref` +
optional `path` → a single `SKILL.md` dir). Repos that ship a *tree* of skills force one entry per skill with
`url`/`ref` restated each time — `grafana/skills` needs **4** entries, the first-party `agent-skills` repo
**5**. Goal: declare the repo once and pull every skill under a subpath. Chosen mechanism (user-specified): a
**`recurse` field** on the entry, not a separate source kind.

## A. Current model (why it can't do this)

One `[[skills]]` = one skill. `scripts/resolve-skills.sh:resolve_one`:
- sparse-checkouts `path` (`--no-cone`, line 130),
- **hard-requires `SKILL.md` at exactly `$tmp/$path`** (line 135) — no walk,
- copies that one dir to `.skill-cache/<name>`, strips `.git`,
- locks **one row**: `name<TAB>sha<TAB>url<TAB>ref<TAB>path` (`lock_set`, line 80).

Identity is the **cache dir basename** — `_lib.sh:list_skill_dirs` globs `<root>/*/` requiring `SKILL.md`,
`link-skills.sh` does `basename "$d"` and symlinks it into `~/.claude/skills/<name>`. So every materialized
skill only needs a **unique cache dir name**; the namespace is **flat** across all roots.

Parser (`_manifest_tsv`, line 49) emits TSV `name\turl\tref\tpath` per `[[skills]]`; downstream loops guard
`[ -n "$name" ] || continue`, so a nameless row is silently skipped today.

## B. Proposed schema

```toml
[[skills]]
url     = "https://github.com/grafana/skills.git"
ref     = "v1.4.0"      # pin — see reproducibility
path    = "skills"      # container (omit / "" = repo root)
recurse = true          # every SKILL.md under path is its own skill
# prefix  = "grafana-"  # optional — collision escape hatch, prepended to each name
# exclude = ["**/experimental/*"]   # optional follow-on (deferred)
```

Collapses the 5 `agent-skills` entries into one (`path=""`, `recurse=true`) and grafana's 4 into one.
A non-recurse entry is unchanged (backward compatible).

## C. Resolver behavior — the `recurse` branch in `resolve_one`

1. Fetch + sparse-checkout `path` as today.
2. Instead of requiring one `SKILL.md`: `find "$src" -name SKILL.md`, **pruning descent once a dir matches**
   (a skill dir is a leaf boundary — stops a skill's own `references/SKILL.md`, if any, from registering as a
   second skill). **Recursive, not maxdepth-1** — grafana nests two levels
   (`skills/grafana-core/grafana-oss`, `skills/grafana-lgtm/tempo`).
3. Each match's parent dir = one skill. Identity = frontmatter `name:` if present, else parent basename,
   then `+ prefix`. Validate charset with the existing `resolve_one` name guard
   (`*[!A-Za-z0-9._-]*|.|..`).
4. `cp -R` each into `.skill-cache/<name>`, strip `.git`, lock **one row per discovered skill**.

## D. Five decisions the field forces

1. **Identity / collision.** Flat namespace (all dirs symlinked into one `~/.claude/skills/`). Two recurse
   sources — or recurse + an explicit entry — yielding the same name must be a **hard error at resolve**, not
   last-writer-wins (silent shadowing is the drift class this repo keeps getting bitten by). `prefix` is the
   escape hatch. Prefer frontmatter `name:` over basename for identity, since basenames collide more
   (`grafana-core/tempo` vs `grafana-lgtm/tempo`).

2. **Reproducibility (the load-bearing one).** `recurse` + a moving `ref` (`main`) makes the **set**
   non-deterministic — upstream adds a subdir, you silently gain a skill. Fix: the **lockfile records the
   concrete expanded list** (one row per discovered skill; the repo sha is shared across them). Expansion (the
   `find`) runs **only on first-resolve / `--update`**; a **plain resolve replays lock rows as per-skill
   cache-hits**, never re-globs. Net: a recurse entry is *exactly* as reproducible as explicit entries once
   locked. Doctrine: a recurse entry **should pin `ref`** to a tag/sha.

3. **Pruning.** A real gap even today (remove a `[[skills]]` entry → stale `.skill-cache/<name>` lingers).
   Recurse widens it (upstream drops a skill; you narrow a `path`). Needs a prune pass: after a full
   `--update`, delete cache dirs no longer in the resolved set. To prune a **source's** children when the
   source entry is removed, track origin — **add a 6th lock column `origin` (= `url#path`)** rather than
   inferring. Decide: is prune `--update`-only, or a new `--prune` flag? (Lean `--update`-only + `--dry-run`
   preview; a silent delete on every resolve is surprising.)

4. **Parser / validation edits.** `_manifest_tsv` emits a 5th `recurse` column ("1"/""). `name` becomes
   **optional when `recurse=true`** (today required) — and the `[ -n "$name" ] || continue` guards in the
   resolve/list loops must **not** skip a nameless recurse row (special-case: a recurse row is keyed by
   url+path, not name). `path` may be empty (repo root as container). `prefix` optional.

5. **`--list` / `--dry-run`.** Pre-resolution a recurse row can't be enumerated without fetching:
   `--dry-run` shows `would-expand <url>@<ref> [path]`; `--list` reads the **expanded children from the lock**
   (post-resolution). Keep the existing one-line-per-skill output for the materialized set.

## E. Scope recommendation

- **Core:** `recurse` + `prefix`; lockfile captures the expanded set (D2); collision hard-error (D1);
  origin-tracked stale-prune (D3). The must-haves are **D2 + D1** — skip either and this silently becomes
  non-deterministic.
- **Defer:** `exclude` globs (only needed for a repo with skills you *don't* want — no current consumer);
  recursive-vs-immediate as a knob (always recurse-with-prune is correct for the known layouts).
- **Test surface:** a fixture repo (via `file://` url, as the resolver already supports) with a nested skill
  tree + a collision case + a name-optional recurse row; assert (a) N skills materialize from 1 entry,
  (b) plain re-resolve is a pure cache-hit with an unchanged set, (c) collision → non-zero exit,
  (d) removing the source prunes its children.

## Open questions for the brainstorm gate

- Prune trigger: `--update`-only vs a dedicated `--prune`? (Data-loss-adjacent — mirror the release-channel
  caution about silent deletes.)
- Identity precedence: frontmatter `name:` vs basename — is frontmatter always present in third-party repos
  (grafana)? If not, basename + `prefix` is the fallback, and a missing-`name` skill in a recurse set is not
  an error.
- Does `--no-cone` sparse-checkout of a container `path` actually materialize the full subtree for the walk,
  or does it need a broader pattern? Verify against grafana's two-level layout before locking the design.
