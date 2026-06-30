## Self-rating (first-party)

This skill participates in the self-rating loop. The rating is a signal about
**this skill's own friction** — where its instructions were unclear, slow, or
made you guess — not about the correctness of the work product (that is the
Validator's job).

**Do not rate automatically.** Append a rating **only when the user asks** for
one (e.g. "rate this run", "how did the skill do") or when you hit real friction
worth recording. Silence is the default; an empty log is a healthy log.

When you do rate, append one dated entry to this skill's own folder —
`skills/<this-skill>/self-rating.md` (the always-writable own-folder zone; never
the target repo or the system memory tree). Use this shape:

```
## YYYY-MM-DD — <one-line context>
- score: <1-5>   (1 = fought the skill, 5 = frictionless)
- friction: <what was unclear / slow / had to be guessed, or "none">
- improve: <the smallest concrete change that would raise the score, or "none">
```

Aggregate across skills with `scripts/skill-ratings.sh`.
