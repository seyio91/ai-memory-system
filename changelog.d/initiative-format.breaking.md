- **Initiatives use a new one-line-status format with generated views.** A Target
  status is now `<open|blocked|done|closed> · next: <session — action> · blocked_by: <…|none>`
  (terminal states alone), with a `- scope:` line; `next_actor:` is gone. Per-env work is
  split into `<project>/<name>@<env>` Targets driven by frontmatter `envs:`, finished Targets
  move to a `### Closed` table, and decisions gain `topics:`/`topic:`, `AMENDS` and `→ Dn`
  forward pointers (an amendment is now a new entry). `## Now`, `## Environment matrix` and
  `## Current rules` are generated into fences by `initiative-render.sh --write`, and the
  progress log lives at `initiatives/logs/<slug>.md`, moving to `initiatives/archive/logs/`
  on close. The old format is no longer parsed: `lint-memory.sh` reports an ERROR and
  `initiative-status.sh` refuses the file. The 3.0.0 migration rewrites existing
  initiatives; see UPGRADING.md.
