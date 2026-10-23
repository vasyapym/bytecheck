#!/bin/sh
# Claude Code Stop hook. Blocks completion until the tree passes bytecheck against
# the policy the user committed. Exit 2 blocks; stderr is shown to the model.
# Copy to .claude/hooks/, merge settings.json into .claude/settings.json.

MANIFEST=".bytecheck/before.json"
POLICY=".bytecheck/policy.json"
BYTECHECK="${BYTECHECK:-.claude/skills/bytecheck/bytecheck.py}"

[ -f "$MANIFEST" ] || exit 0      # no snapshot taken, nothing to enforce
[ -f "$POLICY" ]   || exit 0      # no policy, nothing to enforce

# Avoid a block loop: if this hook already blocked once this turn, let the stop through.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("stop_hook_active") else 1)'; then
    exit 0
  fi
fi

out=$(python3 "$BYTECHECK" verify "$MANIFEST" --policy "$POLICY" 2>&1)
code=$?
[ "$code" -eq 0 ] && exit 0

printf 'bytecheck did not pass. Fix the tree or report these verbatim; do not touch %s or %s.\n%s\n' \
  "$MANIFEST" "$POLICY" "$out" >&2
exit 2
