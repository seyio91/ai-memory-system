Scaffold a new cross-project initiative file.

Argument: `$ARGUMENTS` — the initiative name (kebab-case slug, no `.md` extension).

Step 1 — validate `$ARGUMENTS`. It must match lowercase kebab-case (`[a-z0-9]+(-[a-z0-9]+)*`). If it does not, abort and ask for a valid slug.

Step 2 — guard against overwrite. If `$MEMORY_DIR/initiatives/$ARGUMENTS.md` already exists, abort and tell the user the path exists — they should choose another slug or edit the existing initiative.

Step 3 — copy `$MEMORY_DIR/initiatives/_template.md` to `$MEMORY_DIR/initiatives/$ARGUMENTS.md`. Replace `slug: <slug>` with `slug: $ARGUMENTS`, replace `created: YYYY-MM-DD` with today's date from the injected context, and leave `status: active`. Replace the title placeholder with a human-readable title from the user's request when one is available; otherwise leave it for the user.

Step 4 — regenerate the fences. The template ships with fences already rendered for an initiative with no Targets, and `initiative-render.sh` refuses an initiative that has none (`no Targets`). So run `bash ~/.claude-memory/scripts/initiative-render.sh $ARGUMENTS --write` only once the file has at least one Target (when the user supplied Targets in the request, add them first); otherwise skip and tell the user to run it after adding the first Target. Report any other non-zero exit verbatim; never treat a failure as success.

Step 5 — report the scaffolded path and remind the user to add a breadcrumb row for this initiative to the `## Related Projects` table in every affected project's `memory.md`. The row is a pointer only: do not duplicate status or decision-stream content there.
