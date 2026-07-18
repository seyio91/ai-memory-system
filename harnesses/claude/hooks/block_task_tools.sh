#!/usr/bin/env bash
# PreToolUse hook — blocks the harness TaskCreate/TaskUpdate tools.
# The memory-system workflow tracks executable work in projects/<active>/todo.md
# as markdown checkboxes. Exit code 2 blocks the tool call; stderr is fed to Claude.
set -euo pipefail

cat >/dev/null  # consume the hook's stdin JSON

cat >&2 <<'EOF'
TaskCreate / TaskUpdate are disabled by the memory-system workflow.

Classify the task into one of three tiers instead:
  - Research / explore / Q&A      -> just answer. No tracking.
  - Quick actionable item         -> just do it. No plan, no todo.
  - Large / non-trivial task      -> file a plan in projects/<active>/plans/<name>.md
                                     and track its steps in projects/<active>/todo.md
                                     as markdown checkboxes ( - [ ] item ).

todo.md tracks plan execution only — no plan means no todo entry.
See the injected <memory:orchestrator> block, or ~/.claude-memory/orchestrator.md.
EOF

exit 2
