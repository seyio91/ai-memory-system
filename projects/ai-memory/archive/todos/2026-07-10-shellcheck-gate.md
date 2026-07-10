# Todo snapshot — ai-memory — 2026-07-10

Rolled after the shellcheck static-analysis gate shipped (#52). Plan archived to
`archive/plans/shellcheck-gate.md`; task `397f6850-c619-812d-8677-fff1cfe873ad` closed `done`.

## Active

### Shellcheck static-analysis gate → [plan](plans/shellcheck-gate.md)
- [x] Phase 1 — `.shellcheckrc` (4 disables) + inline `SC2086` justifications; zero findings at `-S info`
- [x] Phase 2 — `run-tests.sh` `== shellcheck ==` stage; gates exit code; skips-with-notice if absent; prove it fires
- [x] Phase 3 — docs: `docs/scripts.md` gate section + CHANGELOG `### Added`

## Done
_(checked items stay above until the file is rolled)_
