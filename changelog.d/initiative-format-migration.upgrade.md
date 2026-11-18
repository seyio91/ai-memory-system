- **Migration `3.0.0-initiative-format.sh` converts existing initiatives.** It runs on
  `/sync-system`. Before its first write it saves a byte-identical copy of each initiative to
  `initiatives/.state/<slug>.pre-3.0.0.md`. Open statuses become
  `<state> · next: <old next_actor> · blocked_by: none`, and their prose moves verbatim to a
  `- scope:` line. A status with no ` — ` (`open`, `blocked waiting on vendor`) takes its first
  word as the state and the rest as scope. `Progress:` / `Was:` segments go to
  `initiatives/logs/<slug>.md`. Only `done` Targets collapse into `### Closed` rows, and their
  full blocks go to the log. An abandoned (`closed`) Target keeps its heading with
  `- status: closed` and never satisfies a dependency. `SUPERSEDES` lines gain `→ Dn`
  pointers, frontmatter gains `topics: []`, and the generated fences are written. It reports
  each prose "amends Dn" candidate and every line it could not convert, and leaves those lines
  byte-identical. A second run changes nothing, and re-running it after fixing a reported line
  converts that line. The hand pass that follows is in UPGRADING.md `## 3.0.0`.
