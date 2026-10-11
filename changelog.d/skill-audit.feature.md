- New bundled skill **`skill-audit`** (`/skill-audit <path>`) audits a skill, or a folder of skills,
  against 13 skill-writing rules from Anthropic's skill guides. A stdlib-only Python script
  (`skills/skill-audit/scripts/lint_skill.py`, JSON output) checks the mechanical rules — body size,
  one-level-deep links and orphans, contents lists, third-person descriptions, machine-specific or
  backslash paths, linked docs or symlinked folders reaching outside the skill, eval count — and flags hook and
  reasoning-echo candidates; the model judges the rest. The skill reports first and edits only the
  fixes you approve by number, then re-checks. It works on any skill folder, not only this system's,
  and is on-demand only: `validate-skills.sh` stays the CI gate.
