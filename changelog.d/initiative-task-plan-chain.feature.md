- **Initiative Targets now join work through tasks.** A Target names its task;
  readiness finds the plan by full `task_ref` in live plans, then archived
  plans, with duplicate matches failing closed. `done`/`closed` terminal
  assertions short-circuit derivation in every mode, and Target `status:` now
  begins with machine-readable `open`, `blocked`, `done`, or `closed`.
  `lint-memory.sh` adds rules 13 (status token), 14 (a live Target needs a
  task), and 15 (a task appears on at most one Target and one live plan).
  `/start` now read-only reports initiative membership and readiness.
