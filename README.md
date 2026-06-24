<!-- ===== HERO (custom SVG — assets/banner.svg) — a code line and its comment drifting apart at dusk ===== -->
<img width="100%" src="https://raw.githubusercontent.com/Jan-ARN/drift/main/assets/banner.svg" alt="drift — comment & doc rot detection for Claude Code"/>

<div align="center">

### Catch the comments that lie.

A Claude Code plugin that flags **comments and docstrings that no longer match the code beside them** — contradicted return contracts, renamed params still named in prose, JSDoc that drifted from the signature, examples that won't compile, resolved TODOs, comments orphaned by a refactor. It hands back a short, ranked, low-noise list, each finding pairing the stale prose with the exact code it misdescribes and a concrete fix. It learns your repo's patterns as you use it.

<br/>

![version](https://img.shields.io/badge/version-0.1.0-243F52?labelColor=162936&style=flat-square)
![license](https://img.shields.io/badge/license-MIT-456A82?labelColor=162936&style=flat-square)
![for Claude Code](https://img.shields.io/badge/for-Claude%20Code-F0C880?labelColor=162936&style=flat-square)

</div>

```
/drift
```

```
drift — feature/retry-policy (author-time)
Rot: 2 · Suspect: 1 · Candidates judged: 14

ROT
 1. Return contract changed — comment fetch.ts:18, code fetch.ts:27 · contradiction
    Claim: "returns null on failure". Reality: throws FetchError (fetch.ts:27).
    Fix: "Throws FetchError on a non-2xx response."
 2. @param renamed — comment retry.ts:9, code retry.ts:14 · signature-mismatch
    Claim: "@param tries — number of attempts". Reality: param is `maxAttempts`.
    Fix: rename the @param to `maxAttempts`.

SUSPECT
 1. Resolved TODO — comment queue.ts:40 · resolved-marker
    "// TODO: handle empty batch" — queue.ts:42 already early-returns on empty.
    Fix: Delete it.

Learned: don't flag the "// debounced — upstream rate-limits" intent comment (you kept it last run).
```

## Why

A comment is a promise about the code beside it. When the code changes and the prose doesn't, the comment doesn't just go stale — it actively misleads, because readers trust comments. A general review pass optimizes for *bugs*; it isn't looking for prose that quietly went false. drift judges only whether comments are still *true*, and learns your "that one's fine" over time. It's the sibling of [occam](https://github.com/Jan-ARN/occam): same loop, same discipline — occam cuts slop in code, drift catches rot in prose about code.

## How it works

drift isn't one prompt — it's a pipeline tuned for **high recall, low noise**:

1. **Pre-filter.** Cheap heuristics surface only the comments worth judging — near changed code, JSDoc on a changed signature, prose naming an identifier or number, TODO markers. The LLM never scans whole files; headers and commented-out code are skipped.
2. **Fan out.** One focused pass per rot category, run as parallel subagents — each catches what a broad pass skims past.
3. **Adversarially verify.** Every candidate gets a skeptic proving the comment is *still accurate*. A finding survives only if it can cite the line that makes the comment false. Intent comments and claims this repo can't verify are dropped.
4. **Rank & learn.** Survivors become a short list with a concrete fix, written to `.tasks/drift-*.md`. Your fix/reject decisions are recorded so the next run is quieter.

### The rot lenses

| Lens | Catches |
|---|---|
| `contradiction` | The comment asserts behavior the code no longer has — wrong return contract, stale default, a threshold in prose that disagrees with the literal. |
| `stale-reference` | A param, variable, function, type, or config key the comment names that was renamed or removed. |
| `signature-mismatch` | JSDoc/TSDoc `@param`/`@returns`/`@throws`/generics that don't match the signature. |
| `outdated-example` | A usage example or snippet that no longer reflects the current API. |
| `resolved-marker` | A `TODO`/`FIXME`/`HACK`/`@deprecated`/"remove once X" whose condition is already met. |
| `orphaned-comment` | Prose describing logic that moved or was deleted, now sitting above unrelated code. |

## Modes

- **`/drift`** — *author-time.* Comments touched by your uncommitted diff. Can apply approved fixes (reword or delete the comment, never the code). The common case.
- **`/drift pr`** *(or `/drift <base-ref>`)* — *review-time.* Comments in the branch vs. its base. Read-only; can post PR comments on request.
- **`/drift <path>`** — scope to a file/folder; with no diff, scans it wholesale.

A `Stop` hook nudges you to run `/drift` when your uncommitted diff changes code near comments (tune with `DRIFT_DIFF_THRESHOLD`, default 80). It never blocks. Per-repo conventions live in `.claude/drift-house-style.md` (copy [`house-style/EXAMPLE.md`](house-style/EXAMPLE.md)); drift's own calibration is kept automatically in `.claude/drift-learnings.md`.

## Install

```sh
claude plugin marketplace add Jan-ARN/drift
claude plugin install drift@drift
```

Then `/drift` is available in every project.

## License

MIT — see [LICENSE](LICENSE).

<!-- ===== FOOTER (custom SVG — assets/footer.svg) — the two lines drifted apart, the creed ===== -->
<img width="100%" src="https://raw.githubusercontent.com/Jan-ARN/drift/main/assets/footer.svg" alt="A comment is a promise about the code — keep it true."/>
