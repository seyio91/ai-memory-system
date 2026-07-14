# Frozen pre-P3 Claude hook scripts (test fixtures)

Byte-for-byte copies of `harnesses/claude/hooks/{inject_memory,session_start_memory,memory_common}.sh`
as they existed immediately BEFORE the P3 migration (shared `scripts/hooks/` set + settings.json
auto-merge). `test_shared_hooks.sh` runs these as the parity oracle: the migrated hooks must produce
byte-identical output. Frozen on purpose — do not "update" them; they are the historical baseline.
