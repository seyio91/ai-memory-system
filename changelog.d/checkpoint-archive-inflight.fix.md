- **`/checkpoint-archive` no longer warns on every entry.** It treated any checkpoint whose
  heading lacked `CLOSED` or `DONE` as in-flight, but nothing writes those markers and
  `/checkpoint` forbids editing a prior entry, so the warning fired on every roll. It now
  classifies each entry from its content (superseded / closed / in-flight) and asks only when an
  open item is tracked nowhere but the checkpoints — not in `todo.md`, a backlog task, an
  initiative Target, or another `working.md` section.
