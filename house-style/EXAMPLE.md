# Drift house style — EXAMPLE (template)

> Copy this file, delete these quoted instructions, and fill in your repo's real
> conventions. Everything below is a placeholder.

**Where to put it.** Save it as `.claude/drift-house-style.md` in the repo it
describes — the recommended home: it lives with the code, stays private if the repo
is private, and Drift picks it up automatically. (If you maintain your own fork of
the Drift plugin, you can instead bundle it as `house-style/<your-repo-basename>.md`
and Drift matches it by repo-root basename.)

**What belongs here vs. not.** This file is the *accuracy-judgment* layer — what
counts as a checkable claim in this repo, which prose is intentionally aspirational,
and what to never read. Drift judges whether comments are *true*, not whether they
match a style guide; do **not** restate doc-style rules your tooling already enforces
(ESLint `jsdoc/*`, TSDoc config, `CLAUDE.md`). Capture only what they miss.

**You don't write the learnings file.** Drift keeps a separate
`.claude/drift-learnings.md` that *it* maintains automatically from your accept/reject
decisions each run. When a learning there proves durable, Drift offers to promote it
*into this file*.

---

## Operational notes

> Facts Drift needs to operate. Fill in the real values.

- **Base branch:** `main` — the ref review-time mode diffs against (`<base>...HEAD`).
- **Generated / vendored paths to never read:** e.g. `src/generated/`, `*.pb.ts`,
  `src/api/schema.ts` (codegen). Comments there aren't authored, so rot in them is
  noise.
- **Doc comment style in use:** e.g. TSDoc, JSDoc with `@param {Type} name`, or
  plain `//` — so signature-mismatch knows the shape to parse.

## Aspirational by design (not rot — don't flag)

> Comments that look like factual claims but are intentionally forward-looking or
> illustrative. List them so the verify pass doesn't waste effort.

- TODOs tracked in an external system (linked `TODO(JIRA-123)`) — open by design;
  only flag if the linked work is closed.
- Pseudo-code examples in module headers that illustrate shape, not a literal call.
- `@example` blocks deliberately simplified (omit error handling for brevity).

## High-rot surfaces (confirmed)

> Where comments in this repo most often drift. List real paths/patterns so the
> lenses lean in.

- e.g. `@param` blocks on `src/api/*` handlers — params change often, docs lag.
- e.g. threshold/timeout comments in `src/config/*` — the number in prose
  desyncs from the literal.

## Leave alone (intent comments)

> Patterns that describe *why*, not *what* — valid even when nearby mechanics change.

- e.g. "// debounced because the upstream API rate-limits at 10/s" — rationale,
  stays true unless the rate-limit reason is gone.
