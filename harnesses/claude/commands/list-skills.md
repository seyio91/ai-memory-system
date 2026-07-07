List every installed skill with its provenance — the single answer to "what skills do I have and where did they come from."

Provenance is **derived**, nothing extra to maintain: a skill in `skills/` is generic authored (tracked, synced), one in `skills-local/` is local authored (gitignored, per-instance), and one in `.skill-cache/` is remote referenced (its scope comes from whichever manifest declared it — `skills/skills.toml` or `skills-local/skills.toml` — and its commit pin from `skills.lock`).

Argument: `$ARGUMENTS` — optional filters forwarded to the script:
- `--remote` — only remote (referenced) skills.
- `--local` — only local-scope skills.

Step 1 — run:
```
bash ~/.claude-memory/scripts/list-skills.sh $ARGUMENTS
```

Step 2 — present the table as-is (columns: `SKILL  SCOPE  SOURCE  SYNCED  PIN`). Keep it terse. If the user is deciding what to add, remind them:
- **remote** (referenced, synced via the manifest) — add with `install-skill.sh --remote <url> --ref <ref> [--path <p>] [--local]`.
- **local authored** (owned/edited here) — create with `new-skill.sh --local`, or seed from an existing dir with `install-skill.sh --from <dir> --tier <tier> --local`.

Read/verify only — do not modify skills, manifests, or the cache from this command.
