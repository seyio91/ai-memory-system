- **Release pipeline automation — Phase A** (changelog fragments + computed versioning).
  - CI now runs the full suite on every PR and `main` push (`.github/workflows/tests.yml`),
    matrix ubuntu + macOS — macOS holds the Bash 3.2 portability line; shellcheck is installed
    so the gate fires.
  - Per-PR **news fragments** land in `changelog.d/<id>.<kind>.md`
    (`breaking | feature | fix | upgrade`). `scripts/assemble-changelog.sh` turns them into a
    CHANGELOG section deterministically and computes the next version from the fragment kinds.
  - `release.sh` consumes fragments when present (assembling the section and deleting the
    fragments in the release commit), makes the version argument optional (computed from
    fragments when omitted), and gains a non-interactive `--ci` mode that also creates the
    GitHub Release. It stays the single release implementation — CI is a trigger, not a second
    code path.
