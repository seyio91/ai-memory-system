Run a content-quality lint pass on the memory tree.

Step 1 — mechanical checks. Run `bash ~/.claude-memory/scripts/lint-memory.sh` and capture stdout. Each line is `ERROR: <file> <reason>` or `WARN: <file> <reason>`. Relay them grouped by severity.

Step 2 — LLM-judgment checks. The script can't reason about content. You must:

a. **Contradictions across files.** Read every `domain/*.md` (full file) and every `projects/*/memory.md` (full file, skip `_template`). Look for pairs of statements that conflict — e.g. one file says "X is the convention" while another says "X is deprecated; use Y", or two files disagree on a path, naming rule, or hard rule. For each contradiction, output:
   - `CONTRADICTION: <file A>:<line> ↔ <file B>:<line> — <one-line description>`

b. **Stale path claims.** Grep across the same files for any absolute path literal (starts with `/` and looks like a real path, not a placeholder like `<active>` or `<name>`). For each one, run `test -e <path>` via Bash. If it does not exist, output:
   - `STALE: <file>:<line> references non-existent path <path>`

c. **Cross-reference gaps.** Look for prose that points at a memory file that doesn't exist (e.g. text saying "see domain/postgres.md" when `domain/postgres.md` is absent). Output:
   - `BROKEN-REF: <file>:<line> points at missing <referenced-path>`

Step 3 — report. Produce a single consolidated report in this shape:

```
## Mechanical findings
<lines from lint-memory.sh, grouped ERROR then WARN>

## Content findings
<CONTRADICTION / STALE / BROKEN-REF lines>

## Suggested mechanical fixes
- regenerate index (run `bash scripts/regenerate-index.sh`) — only if orphans were flagged
- add missing template sections as empty stubs to <file> — only if section gaps were flagged
- add missing frontmatter scaffold to <file> — only if frontmatter gaps were flagged

If nothing was flagged, say "lint-memory: clean" and stop.
```

Step 4 — if any mechanical fixes are listed in step 3, ask the user: "Apply the suggested mechanical fixes?" If yes, apply ONLY those — never silently rewrite content-quality findings (contradictions / stale claims / broken refs / changelog drift). Those stay for the user to resolve.

Cap the entire report at roughly 60 lines. If there are more findings than that, summarize counts and surface the top 10 of each category.
