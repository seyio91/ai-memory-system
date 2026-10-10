- **`/lint-memory --audit <project>` audits a project's memory claim by claim.** A read-only agent
  on the validate role checks every claim in `memory.md` against the repo and read-only
  Terraform Cloud / GitHub APIs, records the command and output behind each verdict (Wrong / Stale /
  Derivable / Move / Keep / Unverified), and writes `projects/<project>/audits/audit-YYYY-MM-DD.md`.
  It edits nothing. The brief lives in `agents/auditor.md` and is linked into Claude on the next
  `/sync-system`.
- **`lint-memory` WARNs on cross-file duplicate lines (rule 17) and unresolved `NEEDS REVIEW` /
  `TODO` markers (rule 18)** in project `memory.md` and `domain/*.md` files.
- **`executor.sh --role validate --run --brief <name>`** prepends `agents/<name>.md` instead of
  `agents/validator.md`, so a read-only brief such as the auditor runs on a CLI validate plane too.
  The name is validated (`[a-z0-9-]`) and the role must be `validate`.
