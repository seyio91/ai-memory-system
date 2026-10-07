- **`lint-memory.sh` is ~40% faster (~17 s → ~10 s on a 19-project tree).** `check-memory-size.sh
  --payload` now accepts several projects, and lint checks them all in one call instead of one
  process per project. The domain-index render and the initiative alert, which are the same for
  every project, are computed once per run; projects targeted by the same initiatives share one
  alert computation. Findings are unchanged. `--working` still pins one project's working file
  and is a usage error with more than one project. The memory write guard checks one project and
  is unaffected.
