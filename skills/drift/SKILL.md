---
name: drift
description: Flag comments and docstrings that no longer match the code beside them — contradictions, stale references, signature/JSDoc mismatches, outdated examples, resolved TODOs, orphaned comments — then produce a short, ranked, low-noise list, each finding pairing the stale prose with the code it misdescribes and a concrete fix (corrected comment or delete). Runs in two modes: author-time on the uncommitted working-tree diff (default, before you commit) and review-time on a branch/PR diff; can also scan a file or folder wholesale. Use this whenever the user says "/drift", "check for comment rot", "are these comments still accurate?", "do the docs match the code?", "find stale docstrings", or wants outdated comments caught before review. TypeScript/JavaScript first. Prefer this over an ad-hoc eyeball pass for any comment/doc accuracy review.
---

# Drift

Drift reviews code with one job: **catch comments that lie.** A comment is a promise about the code beside it; when the code changes and the prose doesn't, the comment rots — and a wrong comment is worse than no comment, because readers trust it. Drift hunts that failure mode and returns a short, trustworthy list, not a wall of nitpicks.

It is occam's sibling: same loop (ingest diff → reason about code → ranked report), same discipline (fan out for recall, adversarially verify for precision, learn your repo over time). occam fights slop *in code*; drift fights rot *in prose about code*.

## Why this shape (read before running)

The naive version — "ask an LLM to read every comment" — is both expensive and noisy: it re-judges comments nothing changed near, and it flags stylistic prose as "wrong." Drift fixes that four ways, and you must not collapse them:

1. **A cheap static pre-filter, then LLM for the verdict.** Heuristics find *candidate* comments worth judging (adjacent to changed code, JSDoc on a changed signature, prose naming an identifier, TODO/FIXME markers). The LLM only judges accuracy — it never has to scan the whole file. This is the core cost/precision decision; honor it.
2. **One focused pass per rot category** (fanned out as parallel subagents) — high recall, because each pass has one narrow definition of "rot" and concrete examples.
3. **An adversarial verify pass** — every candidate gets a skeptic that argues the comment is *still accurate*. Anything defensible — describes intent not mechanics, refers to code outside the diff, is aspirational-by-design — gets dropped. This is what keeps the output trustworthy. A reviewer that cries wolf gets ignored.
4. **A learning loop** — every accept/reject is calibration, recorded so the next run is quieter and more on-target.

This is correctness-quality work, so do not guess. Every finding must name **the specific code the comment misdescribes**. If you can't point to the contradicting code, you don't have a finding — you have a hunch. Drop it.

## Step 0 — Identify the repo, load its house style and learnings

This skill ships as a plugin and runs across repos, so first figure out where you are and load the matching house style — plus what Drift has already learned here.

1. Identify the repo: `git remote get-url origin` and `basename "$(git rev-parse --show-toplevel)"`.
2. Resolve the plugin root: if `$CLAUDE_PLUGIN_ROOT` is set, use it; otherwise find it with `find "$HOME/.claude" -type f -path '*/drift/house-style/*.md' 2>/dev/null | head -1` and take its parent's parent.
3. Read the matching house-style file `house-style/<key>.md` where `<key>` is the repo-root basename. It carries the repo's doc conventions, paths to ignore (generated/vendored), and **operational notes** (base branch). The plugin ships only a generic `house-style/EXAMPLE.md` template; real bundled styles exist only in a fork.
4. If no bundled house-style matches, check for a repo-local `.claude/drift-house-style.md` and use it — the usual place a repo keeps its house style. If neither exists, proceed with the built-in lenses below and state in the output that no repo house style was loaded. The house style enriches the lenses; it is not required to run.
5. Read the **learnings ledger** if present: `.claude/drift-learnings.md` in the repo under review. This is Drift's own accumulated calibration — patterns the user **rejected** (never re-flag), patterns the user **confirmed** (high-signal), recorded automatically at the end of each run (Step 6). For *this* repo it is authoritative, second only to the user's words in the current run. If it doesn't exist yet, that's fine — you'll create it in Step 6.

The repo's own conventions (`CLAUDE.md`, `.cursor/rules/*.mdc`, JSDoc/TSDoc config) are authoritative for doc *style*. Drift judges *accuracy*, not style — read those so you don't flag a house JSDoc convention as rot.

**House style vs. learnings — keep the roles distinct.** The house style is curated knowledge a human wrote or approved. The learnings ledger is Drift's own running memory, maintained automatically. Read both; write only the ledger without asking.

## Modes

Drift runs against a diff by default, or a path wholesale:

- `/drift` (no arg) → **author-time**. Review comments touched by the uncommitted working-tree diff (`git diff HEAD`). The default and common case: catch rot before it becomes a PR. You may auto-apply approved fixes.
- `/drift pr` or `/drift <base-ref>` → **review-time**. Review comments in the branch diff (`git diff <base>...HEAD`; base from the house-style operational notes, default `main`). Output is read-only findings; offer to post them as PR comments via `gh` only if asked.
- `/drift <path>` → scope to a file or folder. If `<path>` has changes in the active diff, review comments near those changes; if there's no diff (clean tree) or the user asks for a full pass, **scan all comments in `<path>` wholesale** — diff scoping is the optimization, not the point.

If there is no diff and no path given (clean working tree, author-time), say so and stop — or offer a wholesale scan of the current file/dir.

## Step 1 — Get the scope and run the static pre-filter

1. Resolve the diff (or the target path) for the mode above. Exclude noise: lockfiles, `*.snap`, `dist/`/`build/`, generated files, vendored code, minified files, and anything the house style marks as generated.
2. **Static pre-filter — find candidate comments cheaply.** A candidate is a comment or doc block that *could* have rotted. Gather, with `git` + `grep`, the comments that are:
   - **adjacent to changed code** — within a few lines of a changed hunk, or inside a function whose body the diff touched;
   - **a JSDoc/TSDoc block on a changed signature** — the block's `@param`/`@returns`/`@throws`/described behavior sits above a function/method/class the diff altered;
   - **prose that names an identifier** — the comment text contains a camelCase/PascalCase token, a `functionCall()`, a file path, a flag, or a number/threshold that exists in code (these are checkable against the code);
   - **a marker** — `TODO`, `FIXME`, `HACK`, `XXX`, `@deprecated`, "temporary", "for now", "remove once".

   In wholesale (`/drift <path>` with no diff) mode there's no "changed" filter — keep the *identifier-bearing*, *JSDoc-on-signature*, and *marker* candidates so the LLM still only judges checkable prose, not every `// loop over rows`.

   **Don't judge only the comments the diff *added*.** A `+`-line comment is usually fresh and matches its code; the rot lives in **pre-existing** comments whose code just changed underneath them. A 3-line diff context hides those, so widen it (`git diff <base>...HEAD -U15`) or read each changed file at head and pair every comment in/near a changed region with its current code. On a fresh-feature PR the added comments are mostly intent (low yield); the comment that silently went false is almost always one nobody touched.
3. Skip non-rot prose so the LLM never sees it: license/copyright headers, commented-out code (that's dead weight — occam's territory, not rot), section-divider banners, and pure-style comments with no factual claim.

If the pre-filter yields nothing, say so and stop — there are no checkable comments in scope.

## Step 2 — Fan out the rot lenses

Spawn one review subagent per lens **in parallel** (Task / Agent tool). Give each the candidate comments **with their surrounding code**, the diff/intent, the house style, and the **learnings ledger**. Each returns findings as a list of `{ file, comment_lines, code_lines, lens, claim, reality, fix }` — `claim` is what the comment asserts, `reality` is what the code actually does (cite the line), `fix` is the corrected comment text **or** "delete it".

Hand each lens its slice of the ledger as calibration: **do not re-raise a pattern the ledger marks "don't flag here"** unless context genuinely differs. Treat "confirmed rot here" entries as high-signal.

The lenses:

1. **contradiction** — the comment asserts behavior the code no longer has: a described return value (`// returns null on failure` over code that throws), a stated default, a named algorithm, a threshold/constant in prose (`// retries 3 times`) that disagrees with the literal in code, an invariant the code no longer maintains. **Respect the comment's own scope**: a claim qualified to another system — "on the backend", "on web", "legacy", a linked `TODO(JIRA-123)` — is not contradicted by *this* repo merely lacking or retaining a symbol. `// CLOSED was removed from the backend enum` is not refuted by the frontend type still keeping `CLOSED` to parse legacy data. If the claim is about something this repo can't see, it's unverifiable, not false — drop it.
2. **stale-reference** — the comment names a parameter, variable, function, type, file, env var, or config key that was **renamed or removed**. Verify the named symbol no longer exists (or no longer means what the comment implies) before flagging.
3. **signature-mismatch** — a JSDoc/TSDoc block whose `@param` names/types, `@returns`, `@throws`, or generics don't match the actual signature: documented params that were removed, real params that are undocumented, a renamed param, a changed type, a `@returns` describing the wrong shape.
4. **outdated-example** — a usage example / code snippet in a comment or doc that no longer reflects the current API (wrong arg order, removed option, old import path, a call that wouldn't compile against the present signature).
5. **resolved-marker** — a `TODO`/`FIXME`/`HACK`/`@deprecated`/"remove once X" whose condition is **already met**: the workaround it describes is gone, the thing it waited on shipped, the bug it warns of is fixed, or it points at code/state that no longer exists. (A still-valid open TODO is not rot — leave it.)
6. **orphaned-comment** — a comment describing logic that has since **moved or been deleted**, so it now sits above unrelated code (commonly from copy-paste or a refactor that relocated the body). The prose is about code that isn't there anymore.

Tell each lens: **verify against the actual code before flagging** (the contradicting line must exist), cap at its highest-confidence findings, and bias toward precision. Describing *intent* or *why* (not mechanics) is not rot even if the mechanics changed — only flag prose that makes a now-false factual claim.

## Step 3 — Adversarially verify

Dedupe overlapping candidates (same comment, different lenses → merge), then for each finding spawn a skeptic (parallel) that argues the comment is **still accurate**: does it describe intent/rationale rather than the changed mechanics? does the named symbol still exist somewhere the comment legitimately refers to (outside the diff)? is the "contradiction" actually a correct description of a branch the reader missed? is the TODO still genuinely open? is the example illustrative pseudo-code, not a literal call? **does the learnings ledger mark this "don't flag here"** (→ drop immediately) — or "confirmed rot here" (→ keep with confidence)?

The skeptic must be able to **point to the code** that makes the comment true; "it might still be fine" is not a defense. The author must be able to point to the code that makes it false. If neither can cite a line, drop it — unverifiable.

Verdicts: **keep** (real rot, code cited), **downgrade** (likely stale but a judgment call → severity "suspect"), **drop** (still accurate / describes intent / unverifiable / pre-existing and not in scope). Bias toward dropping: a short list people trust beats a long list they learn to skip.

## Step 4 — Rank and write the findings

Rank by harm: a comment that would actively **mislead** a reader into a bug (wrong return contract, wrong threshold, wrong example they'd copy) ranks above a cosmetically stale one (a renamed variable in prose). Severity:

- **rot** — the comment is now wrong or misleading; fix or delete it.
- **suspect** — likely stale but a judgment call; reasonable to keep.

Write `.tasks/drift-<slug>-<YYYY-MM-DD>.md` in the repo under review (slug = branch name or target path, kebab-cased). Never overwrite same-day files; append `-2`, `-3`. Use markdown links **relative to `.tasks/`** — every source link starts with `../` (e.g. `[parse.ts:42](../src/parse.ts#L42)`), with GitHub line anchors `#L42` / `#L42-L51`. Link both the comment line and the code line.

```markdown
# Drift — <target> (<mode>)

**Date:** <YYYY-MM-DD>
**Scope:** <what was reviewed, e.g. working tree / main...HEAD / src/parse.ts>
**Candidates judged:** <N comments after pre-filter>

## Summary
- Rot: N   ·   Suspect: N

## Rot
- [ ] **<short title>** — comment [file.ts:42](../file.ts#L42), code [file.ts:50](../file.ts#L50) · *<lens>*
  - **Claim:** <what the comment says>
  - **Reality:** <what the code actually does — cite the line>
  - **Fix:** <the corrected comment text, or "Delete it — the code is self-explanatory.">

## Suspect
- [ ] ... (same shape)
```

Record findings the verify pass dropped in a trailing **Dropped by the verify pass** section (with the reason) so the reasoning is auditable and the tool can be calibrated. If nothing survives verification, write `No rot found — the comments still match the code.` and stop.

## Step 5 — Present, then (author-time) apply

Tell the user concisely: where the file is, the counts, and the 2–3 most misleading comments. Then:

- **Author-time:** ask "Which should I fix? ('all rot', 'all', numbers/titles, or 'none')." Wait for an explicit answer. Apply one finding per edit — rewrite the comment to match the code, or delete it when the fix is "delete it" — tick its checkbox in the same turn. Keep edits surgical: touch only the comment, never the code it describes. (If the *code* is what's wrong, that's a bug, not rot — note it in **Out of scope — possible bugs**, don't fix it.)
- **Review-time:** stop after presenting. Offer to post as inline PR comments via `gh` only if asked.

## Step 6 — Capture learnings (this is what makes Drift improve)

The user's response in Step 5 is a label on every finding: applied = real rot, rejected = false positive *here*. Record it to `.claude/drift-learnings.md` in the repo under review, **automatically and without asking** (only *promotion* asks; see Guardrails).

After the user answers (author-time only — apply decisions are explicit there; never infer them from review-time/PR mode):

- For each finding the user **rejected** (didn't fix, or pushed back as "that comment's fine"): write a **don't-flag** learning — the pattern, the lens, and the user's reason if given. Future lenses and the verify pass must honor it. (Common case: a comment describing intent that you mistook for a mechanics claim — record the distinction.)
- For each finding the user **applied**: record (or reinforce) a **confirmed** learning — this kind of comment really does rot in this repo.
- For any rot pattern the user volunteered in conversation: record it as **confirmed** too.

Rules for writing: dedupe against existing entries — never write the same rule twice; if it recurs, bump its `seen` count and date instead. One line per learning. Be specific enough to match next time ("comments restating a `@deprecated` already enforced by the type system" beats "deprecation comments"). Keep the ledger short; if it sprawls, that's a signal to promote.

Create the file with this shape if it's absent:

```markdown
# Drift learnings — <repo>

Drift's own calibration, maintained automatically: read before each review (Step 0), appended after (Step 6).
Recurring learnings get promoted into the house style — with your OK.

## Don't flag here (rejected as false positives)
- <pattern> · *<lens>* — <user's reason> · seen 1× (<YYYY-MM-DD>)

## Confirmed rot here
- <pattern> · *<lens>* · seen 1× (<YYYY-MM-DD>)
```

Then tell the user, in one line, what you recorded (e.g. "Learned: don't flag intent comments above changed mechanics here (you rejected it).").

**Promotion — the only learning step that asks first.** When a learning's `seen` count crosses ~3, or the user calls something a real rule, offer to graduate it into the house style (`.claude/drift-house-style.md`, or a bundled `house-style/<key>.md` in a fork) and remove it from the ledger.

## Guardrails

- **A finding must cite the code that makes the comment false.** No contradicting line, no finding. This is the difference between drift and a vibes-based comment review.
- **Drift edits prose, never the code it describes.** If the code is the wrong half of the mismatch, that's a bug — note it in **Out of scope — possible bugs** and stop. Don't "fix" a comment by changing the code to match it.
- **Deleting a stale comment is a valid fix** — often the best one. A comment that only restates the code, once it's also wrong, should go, not get reworded.
- **Intent is not rot.** A comment explaining *why* (rationale, trade-off, gotcha) stays valid even when the mechanics it sits above change, unless it makes a specific now-false factual claim. Don't flag the "why" for drifting from the "what".
- **Unverifiable is not false.** A claim scoped to a system this repo can't see — the backend, another service, "legacy data", an external ticket — can't be refuted by this repo's code. Drop it; never flag a comment just because the symbol it mentions is present (or absent) here. Misreading a scoped claim as a global one is the classic comment-rot false positive.
- **Commented-out code and license headers are out of scope** — the former is dead weight (occam's lens), the latter isn't a claim about code.
- Never batch findings into one edit. One finding, one edit, one checkbox — that's what keeps it reversible.
- **Honor the learnings ledger.** If the user rejected a pattern before, don't flag it again unless context genuinely differs.
- **Learnings are written automatically; the house style is not.** Capturing a learning never asks. Promoting a learning into the house style, or otherwise editing it, always asks first.
