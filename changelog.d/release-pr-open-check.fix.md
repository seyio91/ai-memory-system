- **`release-pr.yml` no longer stalls after a Release PR is closed.** Its "is a Release PR
  already open?" guard used `gh pr view <branch>`, which also matches a *closed* PR — so once a
  Release PR was closed (rather than merged), the next fragment change saw the stale closed PR
  and skipped opening a fresh one, silently halting auto-proposed releases. It now checks for an
  **open** PR only (`gh pr list --head <branch> --state open`).
