- **`lint-memory` rule 8 now checks the plan `status:` vocabulary instead of one typo.** It previously
  flagged only the hyphenated `in-progress` — a spelling nothing in the tree had ever used — while real
  drift passed clean: synonyms like `active`, and plans carrying no `status:` at all. The rule now accepts
  exactly `draft`, `in_progress`, `done` (what the tooling itself produces: `/new-plan` scaffolds `draft`,
  `/plan-done` writes `done`) and warns on anything else, naming the offending value, with a dedicated hint
  for the `in-progress` near-miss and for a missing field. This matters because `/state` and `/activity`
  render `status:` verbatim — a synonym splits one report column into two, and an absent status renders
  blank.
- **The plan frontmatter contract is now documented.** `docs/file-formats.md` gains a *Plan frontmatter*
  section giving the full field list and the status vocabulary. Previously the only place the canonical set
  was written down was inside rule 8's own comment, so the convention was undiscoverable to anyone not
  reading the linter — which is how it drifted in the first place. The doc is the source of truth; the rule
  is the enforcement.
