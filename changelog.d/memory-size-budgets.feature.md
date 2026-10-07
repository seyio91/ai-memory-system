- **Memory now carries size budgets, enforced by `lint-memory.sh` and the write guard.**
  `check-memory-size.sh` flags a project `memory.md` over 16 KB or with lines over 400 B
  (WARN — style, trim when convenient), and a rendered session payload that would need more
  delivery chunks than a harness's `session_chunks` cap (ERROR — the harness truncates it
  silently otherwise). `lint-memory.sh` runs both checks across every project; the write guard
  runs them at the moment of the edit — a `memory.md` write is checked against its own budget
  plus the payload for every working file the project has, a `working.md`/`working.<key>.md`
  write is checked against the payload only (no drift check there — that tier is allowed to be
  dated). `check-changelog-drift.sh` also now catches a bracketed or bulleted dated entry
  (`**[YYYY-MM-DD]**`, `- **YYYY-MM-DD`) in project `memory.md`; domain files are unchanged.
