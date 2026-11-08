// ai-memory opencode plugin (opencode v2). Thin by design: no memory logic here.
// It is installed as a SYMLINK in ~/.config/opencode/plugins/, so MEMORY_DIR is
// $MEMORY_DIR if set, else three levels up from the realpath of this file
// (<MEMORY_DIR>/harnesses/opencode/plugin/ai-memory.ts).
//
// Protocol: bash scripts are run by absolute path, no shell, no interpolation of
// event content. stdin is JSON {directory, sessionID}; env is process.env.
//   context    -> harnesses/opencode/hooks/context.sh     stdout (if any) is pushed onto event.system.
//       opencode rebuilds event.system on every model call and pushes do not persist,
//       so the script emits the FULL payload on every call (no state, no compaction hook).
//   tool execute.before -> scripts/hooks/guard.sh with AI_MEMORY_GUARD_OUTPUT=opencode.
//       guard stdout is ONE JSON object: {"decision":"allow"|"deny","reason"?}.
//       Throws on deny, and also (fail closed) on spawn error, non-zero exit,
//       on timeout (15s), or output that is not a JSON object with a decision.
// The injection script fails open (log + no injection) and never throws from context.
import { spawnSync } from "node:child_process"
import { realpathSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

function resolveMemoryDir(): string {
  if (process.env.MEMORY_DIR) return process.env.MEMORY_DIR
  const self = realpathSync(fileURLToPath(import.meta.url))
  return dirname(dirname(dirname(dirname(self))))
}

const log = (msg: string) => process.stderr.write(`ai-memory plugin: ${msg}\n`)

// Hung scripts must not block the host: the guard fails closed (throws), context degrades to no injection.
// AI_MEMORY_PLUGIN_TIMEOUT_MS overrides both (tests only; set by whoever launches opencode).
// Accepted only as a positive integer <= 120000 (decimal digits); anything else uses the default.
const rawMs = process.env.AI_MEMORY_PLUGIN_TIMEOUT_MS ?? ""
const envMs = /^[0-9]{1,6}$/.test(rawMs) ? Number(rawMs) : 0
const TIMEOUT_MS = envMs > 0 && envMs <= 120_000 ? envMs : 15_000
if (rawMs !== "" && TIMEOUT_MS === 15_000 && rawMs !== "15000") {
  log(`ignoring invalid AI_MEMORY_PLUGIN_TIMEOUT_MS=${JSON.stringify(rawMs)} (need integer 1..120000), using 15000`)
}
const GUARD_TIMEOUT_MS = TIMEOUT_MS
const CONTEXT_TIMEOUT_MS = TIMEOUT_MS
const MAX_BUFFER = 16 * 1024 * 1024

function run(script: string, payload: unknown, timeout: number, extraEnv: Record<string, string> = {}) {
  return spawnSync(script, [], {
    input: JSON.stringify(payload),
    encoding: "utf8",
    env: { ...process.env, ...extraEnv },
    timeout,
    killSignal: "SIGKILL",
    maxBuffer: MAX_BUFFER,
  })
}

export default {
  id: "ai-memory",
  async setup(ctx: any) {
    const memoryDir = resolveMemoryDir()
    const hooks = join(memoryDir, "harnesses", "opencode", "hooks")
    const guard = join(memoryDir, "scripts", "hooks", "guard.sh")
    const env = { MEMORY_DIR: memoryDir }
    const directory = (): string => ctx?.location?.directory ?? ctx?.directory ?? process.cwd()

    // Injection hooks: any failure degrades to no injection.
    const inject = (name: string, script: string, event: any): string => {
      try {
        const r = run(script, { directory: directory(), sessionID: event?.sessionID }, CONTEXT_TIMEOUT_MS, env)
        if (r.error) throw r.error
        if (r.status !== 0) throw new Error(`exit ${r.status}: ${(r.stderr ?? "").trim()}`)
        if (r.stderr) log(`${name}: ${r.stderr.trim()}`)
        return r.stdout ?? ""
      } catch (e) {
        log(`${name} failed, no injection: ${e}`)
        return ""
      }
    }

    await ctx.session.hook("context", async (event: any) => {
      const text = inject("context", join(hooks, "context.sh"), event)
      if (text.trim() !== "") event.system.push({ type: "text", text })
    })

    // Guard: fail closed. Only a clean exit 0 with an explicit decision allows.
    await ctx.tool.hook("execute.before", async (event: any) => {
      let r
      try {
        r = run(guard, { ...event, directory: directory() }, GUARD_TIMEOUT_MS, { ...env, AI_MEMORY_GUARD_OUTPUT: "opencode" })
      } catch (e) {
        throw new Error(`ai-memory guard: could not run guard, denying (${e})`)
      }
      if (r.error) throw new Error(`ai-memory guard: spawn failed or timed out, denying (${r.error})`)
      if (r.status !== 0) {
        throw new Error(`ai-memory guard: exit ${r.status}, denying. ${(r.stderr ?? "").trim()}`.trim())
      }
      let verdict: any
      try {
        verdict = JSON.parse(r.stdout ?? "")
      } catch {
        throw new Error("ai-memory guard: unparseable guard output, denying")
      }
      if (verdict === null || typeof verdict !== "object") {
        throw new Error("ai-memory guard: unparseable guard output, denying")
      }
      if (verdict.decision === "deny") throw new Error(String(verdict.reason ?? "denied by ai-memory guard"))
      if (verdict.decision !== "allow") throw new Error("ai-memory guard: no allow decision in guard output, denying")
      if (verdict.systemMessage) log(String(verdict.systemMessage))
    })
  },
}
