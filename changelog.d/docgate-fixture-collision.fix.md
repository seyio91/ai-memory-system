- **`check-docs.sh` no longer resolves a `Used by` cell to a test fixture.** `resolve_script()` matches by
  basename and takes `head -1` over the code roots, and `scripts/tests/fixtures/` was in scope — so
  `session_start_memory.sh` resolved to the `claude-legacy-hooks` fixture instead of the real
  `scripts/hooks/` consumer. Two failure modes, both live: a false FAIL against a legitimate row (which is
  what blocked documenting `AI_MEMORY_SKIP_INJECT`), and the fail-open mirror — a fixture that happens to
  contain the var certifies a consumer that no longer uses it, in the control built to prevent exactly that.
  `tests/fixtures/` is now pruned; `tests/` itself stays in scope, because the table legitimately names test
  scripts as consumers (`AI_MEMORY_UPGRADING_DOC` → `test_upgrading_doc.sh`). Mutation-verified in both
  directions.
- **Three more environment overrides are documented** (34 rows, up from 31). `AI_MEMORY_SKIP_INJECT` — the
  previously undiscoverable kill switch for *all* memory injection, the escape hatch when injection itself
  misbehaves. `AI_MEMORY_HARNESSES_DIR` — a test seam, labelled as one. `AI_MEMORY_ROLE` — set *by*
  `executor.sh` and read by `release.sh`, which refuses a release cut while it is set; documented so that
  refusal is diagnosable, not because anyone should set it by hand.
- **The gate's own "what it does not catch" section named a var that had since gained a row.** It cited
  `AI_MEMORY_SKILL_DATA` as the example of an unchecked var and stayed stale after that changed. It now names
  the *mechanism* — both axes iterate table rows, so an undocumented var is unreachable by construction, and
  `0 findings` describes the table's accuracy rather than the code's coverage. A prose section no axis reads
  is where citations rot silently.
