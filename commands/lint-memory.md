Run a content-quality lint pass on the memory tree.

If `$ARGUMENTS` starts with `--audit`, skip Steps 1-4 and run **Audit mode** below instead.

## Audit mode — `/lint-memory --audit <project>`

Verify one project's `memory.md` claim by claim against its repo and read-only APIs. One project per run; auditing several is a loop the user starts, never a fan-out this command does on its own.

A1 — resolve inputs. `<project>` is required; if missing, list `~/.claude-memory/projects/*/` (minus `_template`) and ask which. Check in this order and stop at the first failure, without dispatching:
1. `<project>` is `_template` → refuse: the template has no repo.
2. `~/.claude-memory/projects/<project>/memory.md` does not exist → "no such project", and list the valid names.
3. Resolve the repo:
   ```
   MEMORY_DIR=~/.claude-memory bash -c 'source ~/.claude-memory/scripts/_lib.sh; resolve_repo_path "$1"' _ <project>
   ```
   Non-zero exit or empty output → name the project's `repo_path` (or say it's absent) and tell the user to fix it or `/pin` from the checkout.

A2 — dispatch. Resolve the plane with `bash ~/.claude-memory/scripts/executor.sh --role validate --which`:
- `subagent` / `subagent:<model>` → the `Agent` tool with `subagent_type: auditor`, using the named model if given. If the `auditor` type isn't available in this session (it is linked by `install.sh`), fall back to `general-purpose` with `model: opus`. Tell it to read `~/.claude-memory/agents/auditor.md` as its full instructions, and that it must not use Write, Edit or NotebookEdit.
- `cli:<name>` → `bash ~/.claude-memory/scripts/executor.sh --role validate --run --brief auditor --clean "<prompt>"`, as a background task. `--brief auditor` prepends the auditor brief instead of the validator's. `--clean` makes the output just the agent's final message, not a transcript.

The prompt names the brief's inputs — `project`, `memory_file` (absolute), `repo` (from A1), `domain_dir` (absolute), `date` (today, from the identity injection) — and pastes the deny-list from `~/.claude-memory/scripts/deny-list.txt` (+ `deny-list.local.txt`). Nothing else: the brief is the single source of the audit rules.

A3 — write the report. If the agent returned no `| # |` table, say so and write nothing. Otherwise take its markdown and write it **byte-for-byte** — never condense, reformat or summarise evidence cells, since the evidence is the audit — to `~/.claude-memory/projects/<project>/audits/audit-<date>.md`. If that file exists, suffix `-2`, `-3`. Do not edit `memory.md` or any other file: acting on findings is a separate trim.

A4 — check evidence. List the rows whose evidence does not start with a backticked command, excluding Unverified rows (the brief lets those describe what was tried):
```
grep '^| [0-9]' <report> | grep -vE '\| (Keep|Wrong|Stale|Derivable|Move|Unverified) \| `' | grep -v '| Unverified |' | cut -d'|' -f2
```
Don't edit the report. Each listed row is weak evidence: the verdict rests on a described command. It is acceptable only if it still shows the deciding output.

A5 — report back in at most 6 lines: the report path, the `claims:` counts line, the Wrong / Stale findings by line number, and the weak-evidence row numbers from A4 (or "none").

## Lint mode (default)

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
