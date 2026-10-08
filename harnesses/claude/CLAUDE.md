# Global Configuration

Memory and workflow doctrine are injected by hooks as `<memory:*>` blocks every session; this file only covers the case where that injection is missing.

If `<memory:orchestrator>` is absent from context, read `~/.claude-memory/doctrine/orchestrator.md` and (if it exists) `~/.claude-memory/orchestrator.local.md` now, before acting. If `<memory:identity>` is absent, read `~/.claude-memory/identity.md`.

Precedence: `identity.md` hard rules > `orchestrator.local.md` > `doctrine/orchestrator.md` > project memory.
