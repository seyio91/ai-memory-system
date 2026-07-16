Codex memory base moves from a generated `~/.codex/AGENTS.md` to live `SessionStart`
hook injection — a plain `codex` (no alias, no wrapper) now gets full memory.
`AGENTS.md` becomes a hand-owned static base (migration converts a generated one,
seeding from `AGENTS.local.md`); `codex-mem.sh --executor-bare` suppresses all
injection via `AI_MEMORY_SKIP_INJECT=1`.
