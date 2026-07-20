- **The five seed templates moved from the repo root into `templates/`.**
  `config.local.sh.example`, `identity.template.md`, `index.template.md`, `orchestrator.template.md`,
  and `skills.toml.example` are engine inputs that `install.sh` copies when a target is missing — not
  files a user opens — and they crowded the root alongside the actual front door (`README.md`,
  `install.sh`, `UPGRADING.md`). Basenames are unchanged; this is a path move only, so every mention
  in older `CHANGELOG.md` / `UPGRADING.md` sections still greps.
  **No migration is needed and none is shipped:** `install.sh` seeds only when the target is absent,
  an existing instance already has all five live files, and the new `install.sh` ships in the same tag
  as the moved templates. Nothing on a consumer instance resolves a template path at runtime.
- **`skill_manifest_template()` now returns `templates/skills.toml.example`.** The `.gitignore`
  negation that kept the old root path tracked is dropped rather than repointed — the `/skills.toml`
  rule is root-anchored, so the `templates/` copy was never in its scope. Both directions are now
  asserted: the five templates are tracked, and their five live counterparts stay ignored.
