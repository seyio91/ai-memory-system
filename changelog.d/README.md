# changelog.d — news fragments

Every PR that changes user-visible behavior drops a **fragment** here. At release time
`scripts/assemble-changelog.sh` turns the fragments into a `CHANGELOG.md` section and
computes the next version — deterministically, with nothing left to infer from `git log`.

## Why fragments

- **No merge conflicts.** Concurrent PRs all editing `## [Unreleased]` collide; separate
  fragment files never do.
- **Written while the reasoning is live** — in the PR that made the change, reviewed with
  full context, not reconstructed from commit subjects at release time.
- **Deterministic assembly** — release notes become `cat` + sort, not model inference.

## Format

One file per note:

```
changelog.d/<id>.<kind>.md
```

- `<id>` — the PR number, or a short slug if you don't have one yet (`42`, `pg-tunneller`).
  It may contain dots; the **kind is the last dot-segment before `.md`**.
- `<kind>` — one of:

  | kind | CHANGELOG heading | version bump |
  |------|-------------------|--------------|
  | `breaking` | `### Breaking` | major |
  | `feature`  | `### Added`    | minor |
  | `fix`      | `### Fixed`    | patch |
  | `upgrade`  | `### Upgrade`  | patch |

The **body is the note** — one or more markdown bullets, exactly as it should read in the
CHANGELOG. Write it the way you'd write a good CHANGELOG entry:

```markdown
- **`release.sh` now consumes fragments.** When `changelog.d/` is non-empty it assembles the
  release section from fragments instead of drafting from `git log`.
```

## Versioning

The release version is **computed** from the fragment kinds present: the highest-ranked kind
wins (`breaking` → major, else `feature` → minor, else `fix`/`upgrade` → patch), applied to
the latest stable `v*` tag. An explicit version passed to `release.sh` overrides it.

## The upgrade rule

An `upgrade` fragment may only **describe a migration that already exists**
(`migrations/<semver>-<slug>.sh`) — never invent upgrade steps from a diff. A human runs the
upgrade guide against a real tree, so a subtly-wrong step is worse than none. The suite
enforces "every migration has an `UPGRADING.md` section" (`test_upgrading_doc.sh`); the
fragment narrates, the script + test guarantee.

## Usage

```bash
scripts/assemble-changelog.sh --check      # validate fragment filenames/bodies
scripts/assemble-changelog.sh assemble     # print the assembled CHANGELOG section
scripts/assemble-changelog.sh --bump       # print the computed next version
```

`release.sh` calls these; you rarely run them by hand. Fragments are **deleted** by the
release commit once assembled.
