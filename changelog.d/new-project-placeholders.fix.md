- **`new-project.sh` now fills in the project name, and `/new-project` sets the index summary.**
  A new project used to keep `topic: <name>`, `# Project: <name>` and the placeholder `summary`
  from the template, which then showed up in `index.md`. The script now substitutes the name in
  every copied file and rejects names outside `[A-Za-z0-9._-]` (or with a leading `.`);
  `/new-project` writes the What It Is one-liner into `summary` and regenerates the index.
