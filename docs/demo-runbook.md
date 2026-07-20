# Demo runbook — the 60-minute live tour

> Presenter script for the live demo. Runs against **your real system and your real projects** —
> the demo's whole point is that nothing is staged. Each beat: **commands** (copy-paste), **say**
> (the point to make), **reveal** (what to show on screen), **time**. Concepts and the "why" live
> in the companion **[showcase.md](showcase.md)** — this is the operational script.
>
> Audience: technical adopters. Format: live, interactive. Budget: ~60 min.

> **Substitute your own names before presenting.** The repos below are placeholders; the commands
> only work against repos you have actually pinned.
>
> | Placeholder | Means |
> |---|---|
> | `<you>` | your macOS username |
> | `<org>` | the parent directory your repos live under (e.g. `~/Projects/<org>/…`) |
> | `payments-svc` | a **cold** repo — never pinned, no `.agents/memory-project`. Beat 3 onboards it live. |
> | `web-app`, `billing-svc` | warm repos: already pinned, with real `memory.md` and history |
> | `platform-eks` | a second warm repo, used to show the breadcrumb switching projects |
> | `platform`, `web-app`, `billing-svc` | the project **categories** the grouping beats rely on |

## Before the audience arrives (pre-flight)

Run these once; they set up real state without spoiling any live beat.

```bash
# 1. Confirm categories are set (grouping beats depend on this)
cd ~/.claude-memory && for f in projects/*/memory.md; do
  c=$(awk -F': ' '/^category:/{print $2;exit}' "$f"); [ -n "$c" ] && echo "$(basename $(dirname $f)): $c"; done
# expect: platform (platform-eks, k8s-addons, services) · web-app (…) · billing-svc (billing-svc, billing-stacks, billing-kubernetes)

# 2. Confirm payments-svc is still COLD (the onboarding beat depends on this)
ls /Users/<you>/Projects/<org>/payments-svc/.agents/memory-project 2>/dev/null \
  && echo "ALREADY PINNED — pick another cold repo" || echo "payments-svc is cold ✔"
test -d ~/.claude-memory/projects/payments-svc && echo "projects/payments-svc exists — remove before demo" || echo "no projects/payments-svc ✔"

# 3. Two terminals ready: T1 = ~/.claude-memory (or any pinned repo), T2 = a second pinned repo
# 4. Do NOT pre-generate state.md / activity.md — generating them live is a beat
```

Terminals used: **T-present** (where you run shell commands + open files) and
**T-claude** (where you start fresh Claude sessions for the SessionStart reveals).

---

## Beat 0 — Problem & thesis · 5 min

- **Say:** agents forget at session end; RAG fixes it with a vector DB + embeddings +
  retrieval service. This system's bet: memory is *markdown delivered by a hook* — no DB,
  no daemon.
- **Reveal:** open `docs/diagrams/three-layer-model.png` (or the `.excalidraw`). Walk the
  two arrows: authority ↓, maturation ↑.
- **Commands:**
```bash
cd ~/.claude-memory && ls          # "this whole thing is a git repo of markdown + scripts"
```

## Beat 1 — It's just files, injected not retrieved · 12 min

- **Say:** three layers on disk; context *arrives* in the prompt, it isn't fetched.
- **Reveal (files):**
```bash
sed -n '1,30p' identity.md                          # schema — hard rules
sed -n '1,25p' projects/web-app-terraform/memory.md   # wiki — a real project
sed -n '1,20p' projects/web-app-terraform/working.md  # scratchpad (may be short/empty)
```
- **Reveal (injection, via SessionStart):** in **T-claude**, start a fresh session inside a
  pinned repo and point at the injected block at the top of the transcript:
```bash
cd ~/Projects/<org>/web-app/web-app && claude
```
  Point out the full payload: `identity` → `project` → `index` → `working`. Then note that
  the *next* prompts only carry the lightweight `<memory:active>` breadcrumb.
- **Reveal (diagram):** `docs/diagrams/injection-flow.png` (source:
  `injection-flow.excalidraw`) — the full-vs-breadcrumb fork and the domain exception.

## Beat 2 — Project detection, no collision · 8 min

- **Say:** the hook resolves the project by walking up from `cwd` to a marker; no global
  "current project", so concurrent repos never collide.
- **Commands:**
```bash
cat ~/Projects/<org>/web-app/web-app/.agents/memory-project   # the marker (one line)
```
- **Reveal:** in **T-present**, note the `<memory:active project="…">` breadcrumb this very
  session is showing. Then in **T-claude** open a session in a *different* pinned repo and
  show the breadcrumb names a different project:
```bash
cd ~/Projects/<org>/platform-eks && claude     # breadcrumb now says project="platform-eks"
```
- **Reveal (diagram):** Mermaid 1 in showcase §2 (walk-up resolution).

## Beat 3 — Onboard `payments-svc` cold · 7 min

- **Say:** watch a brand-new repo get wired in from scratch — both directions of the map at
  once.
- **Commands (guided, from inside the repo):**
```bash
cd /Users/<you>/Projects/<org>/payments-svc
# In a Claude session here, run:  /new-project payments-svc
#   → scaffolds projects/payments-svc/memory.md, asks for the repo path (writes the marker),
#     asks for a category (suggest: platform)
```
  One-shot equivalent (marker + reverse map + category in one call), run from inside the repo:
```bash
bash ~/.claude-memory/scripts/memory-pin.sh payments-svc --category platform
```
- **Reveal:** the two sides of the map, then regenerate the catalog:
```bash
cat /Users/<you>/Projects/<org>/payments-svc/.agents/memory-project     # forward
grep -E '^(repo|repo_path|category):' ~/.claude-memory/projects/payments-svc/memory.md  # reverse
# /reindex   (or:)
bash ~/.claude-memory/scripts/regenerate-index.sh && grep payments-svc ~/.claude-memory/index.md
```
- **Say:** the index is a *projection* — it can't lag the files. (Tie to PR #23: a stale
  hand-kept block had drifted; the fix made regeneration the only writer.)

## Beat 4 — Cross-project: state · activity · Related Projects · 12 min  ← centerpiece

- **Say:** the system reasons across projects without loading them all.
- **Commands (generate live):**
```bash
# /state   (or:)
bash ~/.claude-memory/scripts/regenerate-state.sh && sed -n '1,40p' ~/.claude-memory/state.md
# /activity   (or, note the required scope arg — <category> or --all:)
bash ~/.claude-memory/scripts/regenerate-activity.sh --all && sed -n '1,40p' ~/.claude-memory/activity.md
```
  **Reveal:** category grouping — platform / web-app / billing-svc, uncategorized last. `payments-svc` now
  appears (you just onboarded it).
- **Related Projects (the payoff):**
```bash
awk '/## Related Projects/,/^## /' ~/.claude-memory/projects/billing-svc/memory.md
```
  **Say:** the billing cluster (`billing-svc` / `billing-stacks` / `billing-kubernetes`) — the link lives in the
  project where work *starts*, not an umbrella. When a task touches a sibling, it's
  **delegated to a subagent**; the sibling's `memory.md` is never loaded into the main
  thread. Only a summary returns.
- **Reveal (diagram):** Mermaid 2 in showcase §4 (delegate-don't-load).

## Beat 5 — Workflow engine + the killer beat · 10 min

- **Say:** non-trivial work runs Orchestrator → Executor → Validator; the executor is
  config-driven, the validator is a fresh pass against the plan's success criteria.
- **Commands:**
```bash
bash ~/.claude-memory/scripts/executor.sh --which   # shows the configured executor
```
- **Killer beat (capture → recall):**
  1. In a Claude session inside `payments-svc`, run `/checkpoint` (jot a decision first, e.g. a
     naming choice). It writes `working.md`:
```bash
cat ~/.claude-memory/projects/payments-svc/working.md      # the checkpoint, as plain markdown
```
  2. **Exit that session. Start a NEW one in `payments-svc`** (T-claude). On SessionStart the
     checkpoint is injected — point at it: *"fresh session, it already knows."*
  3. Graduate it: run `/promote-memory` → move the line into a `domain/<topic>.md` file or
     `payments-svc`'s Decisions Log. Show the destination file.
- **Reveal (diagram):** Mermaid 3 in showcase §5 (O/E/V + promotion).

## Beat 6 — Harness-agnostic + rigor · 6 min

- **Say:** one tree, many harnesses; and it's tested, not a hack.
- **Commands:**
```bash
bash install.sh --list                               # registered harnesses + archetypes
sed -n '1,25p' harnesses/claude/manifest             # a real manifest (declarative data)
bash scripts/run-tests.sh --no-lint                  # hermetic suite → 27/27 green
```
- **Say:** Claude reads in-band via the hook; Codex reads the *same files* via a generated
  `~/.codex/AGENTS.md`; only delivery differs. A green hermetic suite means a rebuild is
  verifiable.
- **Reveal (diagram):** Mermaid 4 in showcase §6 (manifest → drivers → targets).

## Wrap · ~2 min (built into the tail)

- Point to **[showcase.md](showcase.md)** as the durable reference and its §7 "Try it
  yourself" for the self-serve path.

---

## What this demo leaves behind (kept, by decision)

`payments-svc` is **kept** as a real project — no teardown:

- `/Users/<you>/Projects/<org>/payments-svc/.agents/memory-project` (forward marker)
- `~/.claude-memory/projects/payments-svc/` (scaffolded project; `repo`/`repo_path`/`category` set)
- any `/promote-memory` destination edited in Beat 5 (domain file or `payments-svc` Decisions Log)
- regenerated `~/.claude-memory/index.md`, `state.md`, `activity.md` (all gitignored)

Nothing above enters git (all under `.gitignore`), and nothing touched the tracked
`ai-memory` project. If you ever *do* want to undo the onboarding:
`rm ~/Projects/<org>/payments-svc/.agents/memory-project && rm -rf ~/.claude-memory/projects/payments-svc`.

## Timing sheet

| Beat | Target | Running total |
|------|--------|---------------|
| 0 Problem & thesis | 5m | 5m |
| 1 Files, injected not retrieved | 12m | 17m |
| 2 Project detection | 8m | 25m |
| 3 Onboard payments-svc | 7m | 32m |
| 4 State · activity · Related Projects | 12m | 44m |
| 5 Workflow + killer beat | 10m | 54m |
| 6 Harness-agnostic + rigor | 6m | 60m |

If running long, Beat 6 compresses to `install.sh --list` + the diagram (drop the live test
run), and Beat 2's second-repo session can be described rather than shown.
