- **Release pipeline — Phase B: fully automated publish via GitHub Actions.** When
  `changelog.d/` fragments land on `main`, `release-pr.yml` opens a "Release vX.Y.Z" PR carrying
  the assembled CHANGELOG for review; merging it triggers `release-publish.yml`, which tags,
  pushes, and creates the GitHub Release. The human merge is the sole authorization gate.
  - `release.sh` gains `--prepare` (assemble + delete fragments + commit on a `release/*` branch;
    no tag, no push; refuses on `main`) and `--publish` (tag the merged release commit + push +
    GitHub Release). It stays the single release implementation — the Actions are thin triggers.
  - `--publish` is keyed on the CHANGELOG carrying the `## [version]` section, not on a commit
    subject, so it works whatever merge strategy the Release PR uses (merge commit, squash, or
    rebase), and is idempotent on re-run.
  - The auto-opened Release PR uses the `RELEASE_PAT` secret (not the default `GITHUB_TOKEN`) so
    it actually gets CI — PRs opened with `GITHUB_TOKEN` don't trigger workflow runs.
