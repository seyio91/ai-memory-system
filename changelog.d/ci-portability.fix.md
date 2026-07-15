- **Three latent portability bugs surfaced by the new CI** (first run on ubuntu + macOS).
  - `file_mtime`/lint read mtime with BSD `stat -f %m` first; on GNU/Linux `-f` is
    `--file-system` (a valid *different* mode, not a clean failure), so it polluted the value
    → `/state` last-touched ordering was wrong and stale files went unflagged on Linux. Now the
    GNU form (`stat -c %Y`) is tried first — it fails cleanly on BSD.
  - `manifest_get` returned on the first key match while reading `< <(_mf_pairs …)`, closing the
    pipe mid-write so the producer's `printf` took `SIGPIPE` ("write error: Broken pipe"). It now
    buffers the pairs before searching.
  - The Antigravity statusline built its Nerd-Font glyphs with `$'\uXXXX'`, which needs bash
    4.2+; under the repo's own bash-3.2 target they stayed literal. Now emitted with `printf`
    octal, matching the emoji fallback.
