---
topic: <topic>
triggers: [<keyword>, <keyword>, <keyword>]
summary: <one-line description — shown in the index to decide relevance>
---

# Domain: <Topic>

> Template. Copy to `domain/<topic>.md` for cross-project knowledge — patterns,
> gotchas, and conventions that apply across more than one repo. The `triggers`
> list is what the agent matches a prompt against to decide whether to load this
> file on demand. Real `domain/*.md` files are git-ignored; this template ships
> so others see the format. Run `scripts/regenerate-index.sh` after adding one.

## Knowledge
<!-- Durable patterns and traps only. No version pins, no file:line refs (name the file), no counts, no dated status, no incident narratives — name the file or command that answers it. -->

Domain files hold **durable patterns and traps**, never volatile specifics. If a
detail will rot (a version, a line number, a count, "as of <date>", the story of
one incident), leave it out and point at the file or command that answers it
instead. Entries are undated.

<the trap or pattern> — <why it matters and when it bites>; see `<file or command>`
