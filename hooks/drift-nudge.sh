#!/usr/bin/env bash
# drift-nudge — author-time comment-rot guard.
# When Claude stops, if the uncommitted diff has changed code that sits near
# comments or docstrings, nudge to run /drift before committing — so prose that
# drifted out of sync with the code gets caught while the change is fresh.
# Never blocks; always exits 0. No-ops outside a git work tree, below the
# changed-line threshold, or when no changed source files touch comments.

THRESHOLD="${DRIFT_DIFF_THRESHOLD:-80}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Source files (TS/JS first) that changed, excluding generated/vendored noise.
files=$(git diff HEAD --name-only 2>/dev/null \
    | grep -E '\.(ts|tsx|js|jsx|mjs|cjs)$' \
    | grep -vE '(\.d\.ts$|\.snap$|/dist/|/build/|/node_modules/|\.min\.)')
[ -z "$files" ] && exit 0

# Total changed lines across those files.
changed=$(git diff HEAD --numstat -- $files 2>/dev/null \
    | awk '{ a += $1; d += $2 } END { print a + d + 0 }')
changed="${changed:-0}"
if [ "$changed" -lt "$THRESHOLD" ] 2>/dev/null; then
    exit 0
fi

# Only nudge if the changed hunks actually sit near comments/docstrings —
# a changed line within 2 lines of a comment marker in the diff context.
near_comment=$(git diff HEAD -U2 -- $files 2>/dev/null \
    | grep -cE '^[+-].*(//|/\*|\*/|\* @|\*\*)')
near_comment="${near_comment:-0}"
[ "$near_comment" -eq 0 ] 2>/dev/null && exit 0

printf '{"systemMessage": "drift — uncommitted diff is %s changed lines in code near comments/docstrings. Consider running /drift before committing to catch comments that drifted out of sync with the code."}\n' "$changed"
exit 0
