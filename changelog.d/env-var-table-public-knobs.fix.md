- **Three user-facing environment overrides are now documented.** `MEMORY_RELOAD_TRIGGER` (the prompt
  token that forces a full re-injection, default `@memory`), `AI_MEMORY_SKILL_DATA` (per-skill local data
  root, default `$MEMORY_DIR/.skill-data`), and `MEMORY_ROOT` were all readable knobs — each consumed as a
  plain `${VAR:-default}` and settable by any user — but absent from the `docs/scripts.md` table, so
  `check-docs.sh` could not see them. The gate only checks documented vars *forward* into code; a knob that
  was never documented is invisible to it in both directions. The table now carries 30 rows, up from 27.
- **`MEMORY_ROOT` is documented as a legacy alias, not a general knob.** It is read by
  `sync-project-skills.sh` alone, filling the role `MEMORY_DIR` plays in every other script. The row says so
  explicitly and warns against new consumers, so documenting it records the inconsistency rather than
  blessing it.
