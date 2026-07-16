List every installed skill with its provenance — the single answer to "what skills do I have and where did they come from."

Provenance is **derived**, nothing extra to maintain: a skill in `skills/` is authored on this instance (gitignored except `.gitkeep`), and one in `.skill-cache/` is remote referenced (declared in root `skills.toml`, with its commit pin from `skills.lock`).

Argument: `$ARGUMENTS` — optional filters forwarded to the script:
- `--remote` — only remote (referenced) skills.

Step 1 — run:
```
bash ~/.claude-memory/scripts/list-skills.sh $ARGUMENTS
```

Step 2 — present the table as-is (columns: `SKILL  SOURCE  SYNCED  PIN`). Keep it terse. If the user is deciding what to add, remind them:
- **remote** (referenced via root `skills.toml`) — add with `install-skill.sh --remote <url> --ref <ref> [--path <p>]`.
- **authored** (owned/edited on this instance) — create with `new-skill.sh`, or seed from an existing dir with `install-skill.sh --from <dir>`.

Read/verify only — do not modify skills, manifests, or the cache from this command.
