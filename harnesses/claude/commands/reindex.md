Regenerate the memory index from frontmatter.

Step 1 — snapshot the current `index.md` for diff:
```
cp ~/.claude-memory/index.md /tmp/index-before.md
```

Step 2 — run the regenerator:
```
bash ~/.claude-memory/scripts/regenerate-index.sh
```

Step 3 — diff. Show the user what changed inside the AUTOGEN block:
```
diff /tmp/index-before.md ~/.claude-memory/index.md
```

Step 4 — report:
- If diff is empty: say "index unchanged — already in sync with frontmatter".
- Otherwise: summarize what changed in two or three lines (new project added / domain entry's summary updated / file removed / etc.). Do NOT paste the raw diff back unless the user asks.

Step 5 — clean up `/tmp/index-before.md`.
