# Todo — ai-memory

Plan: `plans/repo-path-mapping.md` (done)

- [x] `_lib.sh`: add `projects_root()` + `resolve_repo_path()`
- [x] tests: extend `test_lib.sh` for projects_root + resolve (hit / remote-fallback / miss)
- [x] `memory-pin.sh`: new helper writing both directions + frontmatter upsert
- [x] tests: new `test_memory_pin.sh`
- [x] `~/.claude/commands/pin.md`: slash command
- [x] `lint-memory.sh`: repo_path drift validation
- [x] tests: extend `test_lint_memory.sh` for drift
- [x] `regenerate-index.sh`: surface tags in project rows
- [x] `_template/memory.md`: add optional fields
- [x] `README.md`: document fields, env var, /pin, delegation contract
- [x] run full suite green (pre-existing test_archive_cleanup failure unrelated)

Note: `test_archive_cleanup.sh` fails on pristine HEAD too — pre-existing, out of scope.
