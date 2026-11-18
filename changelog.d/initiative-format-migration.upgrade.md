- **Migration `3.0.0-initiative-format.sh` converts existing initiatives.** It runs on
  `/sync-system`. Before its first write it saves a byte-identical copy of each initiative to
  `initiatives/.state/<slug>.pre-3.0.0.md`. Open statuses become
  `<state> · next: <old next_actor> · blocked_by: none`, and their prose moves verbatim to a
  `- scope:` line. `Progress:` / `Was:` segments go to `initiatives/logs/<slug>.md`. Done and
  closed Targets collapse into `### Closed` rows, and their full blocks go to the log.
  `SUPERSEDES` lines gain `→ Dn` pointers, frontmatter gains `topics: []`, and the generated
  fences are written. It reports each prose "amends Dn" candidate and every line it could not
  convert, and leaves those lines byte-identical. A second run changes nothing. The hand pass
  that follows is in UPGRADING.md `## 3.0.0`.
