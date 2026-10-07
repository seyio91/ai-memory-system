#!/usr/bin/env python3
# Shared payload slicer for hook chunk delivery (scripts/hooks/lib.sh
# emit_hook_chunk). Greedily packs lines into <=MAX-byte slices at line
# boundaries so delivery and the size checker can never disagree about how
# many chunks a payload needs.
#
# Modes:
#   (default)  reads AI_MEMORY_CHUNK_INDEX / AI_MEMORY_CHUNK_TOTAL from the
#              environment, slices stdin, and writes the framed
#              <memory:chunk> body for that index to stdout — this is the
#              code emit_hook_chunk used to run inline.
#   --count    reads stdin, prints the number of slices a delivery would
#              need. Empty input needs 0 slices.
import os
import sys

MAX = 9000
MARKER = b"[ai-memory: memory base truncated \xe2\x80\x94 raise session_chunks in the harness manifest]\n"

# Hook entries registered 1..N are NOT guaranteed to be delivered in registration
# order -- Claude ran them concurrently and concatenated by completion (observed
# 2026-07-18: chunks arrived 2,3,4,1,5). Slices are cut at arbitrary line
# boundaries, so an out-of-order chunk bisects a <memory:*> block. Frame every
# slice with its index so a reader can reassemble regardless of arrival order.
# This is a transport frame, deliberately not balanced against the content tags
# it may bisect. Inert on codex, which does deliver in order.
NOTE = (b" note=\"ordered fragments of one memory payload; hook delivery order is"
        b" not guaranteed -- concatenate by index\"")


def compute_slices(data):
    slices = []
    current = b""
    for line in data.splitlines(keepends=True):
        if not current:
            current = line
        elif len(current) + len(line) <= MAX:
            current += line
        else:
            slices.append(current)
            current = line
    if current:
        slices.append(current)
    return slices


def emit(idx, of, body):
    # No separator before the footer: whether a trailing newline was original or
    # inserted would be ambiguous on strip, breaking byte-identical reassembly.
    # Only the final slice can lack one (slices are cut keeping line ends), so at
    # most one chunk closes on the same line as its last byte.
    head = b"<memory:chunk index=\"%d\" of=\"%d\"%s>\n" % (
        idx, of, NOTE if idx == 1 else b"")
    sys.stdout.buffer.write(head + body + b"</memory:chunk>\n")


def run_emit(idx, total, data):
    if not data:
        return
    slices = compute_slices(data)
    if idx > len(slices):
        return

    overflow = len(slices) > total
    if overflow and idx == total:
        out = slices[idx - 1]
        sep = b"" if out.endswith(b"\n") or not out else b"\n"
        while out and len(out) + len(sep) + len(MARKER) > MAX:
            lines = out.splitlines(keepends=True)
            if len(lines) <= 1:
                out = b""
                sep = b""
                break
            out = b"".join(lines[:-1])
            sep = b"" if out.endswith(b"\n") or not out else b"\n"
        emit(idx, total, out + sep + MARKER)
        return
    if overflow and idx > total:
        return

    emit(idx, len(slices), slices[idx - 1])


def run_count(data):
    print(len(compute_slices(data)))


def main(argv):
    if argv[:1] == ["--count"]:
        run_count(sys.stdin.buffer.read())
        return 0

    idx = int(os.environ["AI_MEMORY_CHUNK_INDEX"])
    total = int(os.environ["AI_MEMORY_CHUNK_TOTAL"])
    run_emit(idx, total, sys.stdin.buffer.read())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
