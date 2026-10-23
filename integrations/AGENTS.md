<!-- Paste into the project's AGENTS.md, .cursor/rules, or system prompt. -->

## Verification

Before editing any file, run `python3 bytecheck.py snapshot . -o .bytecheck/before.json --store`.
After editing, run `python3 bytecheck.py verify .bytecheck/before.json --json` with
`--allow` limited to the paths the task named, `--expect` for files that must change, and
`--deny` for lockfiles, CI config and tests. Never edit the manifest, never widen the policy
without being asked, never re-snapshot to clear a FAIL. End your message with the verdict
line and `tree_hash_after`.
