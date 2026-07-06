#!/usr/bin/env bash
# preinvocation.sh — Antigravity PreInvocation hook: inject project memory live,
# once per model call, the same live-refresh model as the Claude UserPromptSubmit
# hook. Registered in ~/.gemini/config/hooks.json by the install `hook` driver.
#
# Antigravity gives the hook NO workspace handle (payload workspacePaths is empty,
# and the hook's cwd is the config dir), so the active project is resolved at
# *launch* by agy.sh, which exports AI_MEMORY_PROJECT / AI_MEMORY_CWD / MEMORY_DIR
# into agy's environment; this hook inherits and reads them. An agy session is
# single-workspace for its lifetime, so launch-time resolution == per-invocation.
# The hook still re-reads content each call, so working.md edits surface live
# (no relaunch needed).
#
# stdin  : Antigravity PreInvocation JSON, e.g. {"invocationNum":0,...} (0-based).
# stdout : {"injectSteps":[{"ephemeralMessage":"<memory payload>"}]}
#          invocationNum==0 -> full payload; later invocations -> the
#          <memory:active> breadcrumb. No active project -> {"injectSteps":[]}
#          (the memory system stays dormant outside an onboarded repo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$REPO/scripts/_lib.sh"            # MEMORY_DIR default + config.local.sh
. "$REPO/scripts/content-core.sh"    # content_sections (shared selection)
. "$REPO/scripts/formatters/xml.sh"  # xml_render_full / xml_render_breadcrumb
. "$REPO/scripts/jsonutil.sh"        # json_escape / json_get

INPUT="$(cat)"
INV="$(printf '%s' "$INPUT" | json_get invocationNum)"
PROJECT="${AI_MEMORY_PROJECT:-}"
CWD="${AI_MEMORY_CWD:-}"

no_inject() { printf '{"injectSteps":[]}\n'; exit 0; }

# No active project -> stay dormant (generic agy, no memory).
[ -n "$PROJECT" ] || no_inject

# invocationNum is 0-based: the first model call of a session is 0 (verified live).
if [ "$INV" = "0" ]; then
    PAYLOAD="$(content_sections "$PROJECT" identity project index working | xml_render_full)"
else
    PAYLOAD="$(content_sections "$PROJECT" identity project index working \
        | xml_render_breadcrumb "$PROJECT" "$CWD")"
fi

[ -n "$PAYLOAD" ] || no_inject
printf '{"injectSteps":[{"ephemeralMessage":%s}]}\n' "$(json_escape "$PAYLOAD")"
