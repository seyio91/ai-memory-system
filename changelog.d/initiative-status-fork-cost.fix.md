- **`initiative-status.sh` is ~10x faster (0.68 s → 0.07 s on a 25-Target initiative), which speeds up `lint-memory.sh` and the memory write guard.**
  Table-cell escaping and whitespace trimming forked a `sed` per call (~180 per run); they now
  use bash parameter expansion. Output is byte-identical. Every project targeted by an initiative
  paid this cost in the initiative alert, so lint dropped from ~32 s to ~17 s and a guarded
  `memory.md` write from ~1.4 s to ~0.7 s on a 19-project tree.
