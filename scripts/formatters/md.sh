#!/usr/bin/env bash
# formatters/md.sh — serialize content-core section records into the markdown
# `# === X ===` sections used for file-materialize harnesses (Codex AGENTS.md).
# Records arrive on stdin as `kind<TAB>path<TAB>name` (see content-core.sh).
# Output goes to stdout with a trailing blank line after each section, matching
# the pre-refactor codex-mem.sh build byte-for-byte.
#
# The `domain` section renders a frontmatter-driven index table rather than a raw
# file cat; it depends on extract_fm_field (from _lib.sh), which the Codex adapter
# already sources. The overlay/header framing is NOT here — it is codex-specific
# and stays in codex-mem.sh.

# md_render — read records on stdin, print the markdown sections.
md_render() {
    local kind path name
    while IFS=$'\t' read -r kind path name; do
        case "$kind" in
            identity)
                echo "# === IDENTITY ==="; echo; cat "$path"; echo ;;
            project)
                echo "# === PROJECT: $name ==="; echo; cat "$path"; echo ;;
            index)
                echo "# === MEMORY INDEX ==="; echo; cat "$path"; echo ;;
            domain)
                _md_render_domain "$path" ;;
            working)
                echo "# === WORKING MEMORY ==="; echo; cat "$path"; echo ;;
        esac
    done
}

# _md_render_domain <domain-dir> — the frontmatter-driven Domain Index table.
# Stable (sorted) file ordering so the generated output is reproducible.
_md_render_domain() {
    local dir="$1" f topic triggers summary
    echo "# === DOMAIN INDEX ==="
    echo
    echo "Domain knowledge files live under \`$dir/\`. When the user's"
    echo "request matches a topic's triggers below, read the absolute path with your"
    echo "file-read tool BEFORE answering. Treat the file as authoritative over"
    echo "training defaults."
    echo
    echo "| File | Triggers | Summary |"
    echo "|------|----------|---------|"
    for f in $(find "$dir" -maxdepth 1 -type f -name '*.md' | sort); do
        topic=$(extract_fm_field "$f" "topic")
        triggers=$(extract_fm_field "$f" "triggers")
        summary=$(extract_fm_field "$f" "summary")
        # Normalize triggers for display: strip [ ] if present.
        triggers="${triggers#[}"
        triggers="${triggers%]}"
        # If a file lacks frontmatter, fall back to its basename + empty fields.
        [ -z "$topic" ] && topic=$(basename "$f" .md)
        [ -z "$summary" ] && summary="(no summary; add frontmatter)"
        echo "| $f | ${triggers:-—} | $summary |"
    done
    echo
}
