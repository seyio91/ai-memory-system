- **Orchestrator doctrine is now a tracked core plus a local overlay.** The per-instance
  `orchestrator.md` (seeded once from a template and never updated again) is replaced by
  `doctrine/orchestrator.md` (tracked, updated on every sync) and `orchestrator.local.md`
  (gitignored, personal additions only). Migration `1.6.0-orchestrator-core-overlay.sh` backs
  up an existing `orchestrator.md` to `orchestrator.md.pre-1.6.0` and seeds an empty overlay;
  port personal rules from the backup by hand. See [UPGRADING.md](UPGRADING.md#160).
