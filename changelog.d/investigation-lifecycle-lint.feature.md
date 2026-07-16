Investigations are tied to the task lifecycle: a live `investigations/<slug>.md`
must carry a frontmatter `task_ref` (`lint-memory` warns on orphans), and moves to
`archive/investigations/` when its task closes and the consuming plan ships.
