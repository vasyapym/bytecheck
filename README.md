# bytecheck

An agent's report is a claim. The filesystem is the evidence.

bytecheck snapshots a directory before an agent works and verifies it after. It fails on
anything the policy did not allow: edits outside scope, edits that never happened,
deletions, placeholders, conflict markers, invisible characters, line-ending flips.
Byte-exact. No normalisation. One file, standard library only, Python 3.8+.

```sh
python3 bytecheck.py snapshot . -o .bytecheck/before.json --store
# ... agent works ...
python3 bytecheck.py verify .bytecheck/before.json \
  --allow 'src/payments/**' --expect 'src/payments/refund.py' --deny '**/*.lock'
```

```text
M src/payments/refund.py +12 -3 allowed
A src/payments/refund_test.py allowed
D tests/test_ledger.py VIOLATION deletion not allowed (needs --allow-delete)
! src/payments/refund.py:41 placeholder elision phrase: # ... rest of the function unchanged
FAIL 3 changes, 1 violation, 1 error finding  a1b2c3d4e5f6 -> 0f9e8d7c6b5a
```

Exit `0` pass, `1` fail, `2` could not check. `--json` for the full verdict. It never writes to the tree it checks.

## Why

LLM agents fail in a small number of repeatable ways, and none of them show up in the agent's own summary:

|Failure|What bytecheck does|
|---|---|
|Over-reach: drive-by refactors, reformatting, touched lockfiles or CI|Every path outside `--allow` is a violation|
|Under-delivery: claims an edit that never happened|`--expect` requires the change to exist|
|Deleted tests, deleted files|Deletions need `--allow-delete`, always|
|Placeholders: "rest of the file unchanged", "existing code", bracketed snips|`placeholder` rule, error severity|
|Truncated output, lost trailing newline, file shrank 80%|`shrunk`, `trailing-newline-lost`|
|CRLF to LF, BOM added, tabs to spaces, straight quotes to smart quotes|`eol-changed`, `bom-changed`, `indent-flipped`, `smart-quote`|
|Zero-width, NBSP, bidi control characters, NUL bytes|`zero-width`, `nbsp`, `bidi-control`, `nul-in-text`|
|Merge-conflict residue|`conflict-marker`|
|Right edit, wrong file; copy that is not byte-identical|`same`, `hash --expect`|

Whitespace-only and EOL-only changes are classified in the output. They are never ignored.

## Install

Copy one file. Check it.

```sh
curl -fsSLO https://raw.githubusercontent.com/vasyapym/bytecheck/v0.1.0/bytecheck.py
python3 bytecheck.py hash bytecheck.py --expect d8966c6f8e48890035d76e5c58c7ae5c845c06fc87bd4095066581cacbb7bab6
```

Or, for humans, once the PyPI publish lands: `pipx install bytecheck-cli` (the PyPI name
`bytecheck` is taken, so the distribution publishes as `bytecheck-cli`; the module and
command stay `bytecheck`).

For agents: the repository root is a skill. Copy it to `.claude/skills/bytecheck/` or any Agent Skills compatible directory. `SKILL.md` carries the protocol; `bytecheck.py` sits beside it. See [For agents](#for-agents).

## Commands

```text
snapshot [ROOT] -o FILE|- [--store [DIR]] [--exclude GLOB]... [--exclude-from FILE]
verify   [MANIFEST|-] [--root DIR] [--baseline DIR] [--policy FILE] [policy flags]
hash     PATH... [--expect HEX]
same     A B
delta    OLD NEW [--within RANGES]
scan     PATH... [--strict]
```

`snapshot` walks the tree, hashes every regular file, records symlink targets and exec bits, writes a manifest. `--store` also keeps the bytes in a content-addressed directory so `verify` can show line hunks and enforce `--within` without git.

`verify` re-walks the tree, classifies every change as added, deleted, modified, renamed or attr, applies the policy, runs content rules on changed files, prints the verdict. With no policy flags it asserts the tree is untouched. `--baseline DIR` uses a copy of the original tree instead of a manifest.

`hash` gives SHA-256 and size per file, or a tree hash for a directory. `same` says whether two files or two trees are byte-identical, and where they first differ. `delta` describes how two files differ: hunks, EOL and BOM before and after, whitespace-only and EOL-only flags. `scan` runs the content rules on anything, no baseline needed.

Every command: `--json` prints exactly one JSON document on stdout; `--quiet` prints nothing. stdout carries results. stderr carries diagnostics. No colour, ever.

## Policy

```text
--allow GLOB          permit added, modified, attr changes. Never deletions.
--allow-delete GLOB   permit deletions. Data loss gets its own word.
--deny GLOB           forbid. Wins over every allow. Fence lockfiles, CI, tests.
--expect GLOB         at least one change must match. Implies allow.
--within PATH:RANGES  every hunk in PATH inside these old-file lines, e.g. src/a.py:120-180,210-215
--policy FILE         the same keys as JSON. Flags add to it; they cannot remove from it.
--strict              warnings fail
--disable RULE        turn a rule off, by name
```

Glob dialect, one rule: patterns match the whole root-relative POSIX path. `*` stays within a segment, `**` crosses segments, `?` is one character, a trailing `/` means the directory and everything below. No implicit any-depth matching.

A policy file an orchestrator hands to an agent:

```json
{
  "allow": ["src/payments/**"],
  "expect": ["src/payments/refund.py"],
  "deny": ["**/*.lock", ".github/**", "tests/**"],
  "strict": true
}
```

## Rules

Rules have names, not numbers. `error` fails the run. `warn` fails under `--strict`. `info` never fails. Delta rules need before-content (`--store` or `--baseline`).

```text
error  conflict-marker  placeholder  nul-in-text  bidi-control  bom-changed  eol-changed
warn   zero-width  smart-quote  nbsp  mixed-eol  shrunk  trailing-newline-lost  indent-flipped
info   bom  no-trailing-newline  invalid-utf8
```

In `verify`, rules run only on added and modified files. Pre-existing debt cannot fail you; only what the agent introduced can. `smart-quote` and `nbsp` apply to code files only. `placeholder` matches ellipsis-only comments and elision phrases on comment lines in code, and bracketed snip tokens anywhere. Binary files are skipped by every text rule. Rules are tuned for low false positives; a rule agents learn to disable is worse than no rule.

## Output

```sh
python3 bytecheck.py verify .bytecheck/before.json --json --allow 'src/**'
```

```json
{
  "ok": false,
  "incomplete": false,
  "tree_hash_before": "a1b2…",
  "tree_hash_after": "0f9e…",
  "changes": [
    {"path": "src/a.py", "kind": "modified", "allowed": true, "added": 12, "removed": 3,
     "hunks": [{"old_start": 40, "old_end": 42, "new_start": 40, "new_end": 51}],
     "whitespace_only": false, "eol_only": false, "findings": []}
  ],
  "violations": [{"kind": "change_not_allowed", "path": "tests/test_x.py", "change": "deleted",
                  "reason": "deletion not allowed (needs --allow-delete)"}],
  "findings": [],
  "summary": {"verdict": "FAIL", "changes": 2, "violations": 1, "untouched": false}
}
```

`tree_hash` is specified so any tool can reproduce it: for entries sorted by path in code-point order, concatenate `type NUL path NUL payload NUL exec LF` where payload is the file's sha256 hex, the symlink target, or empty; exec is `x` or `-`. Hash that with SHA-256. The same tree yields the same hash on Linux, macOS and Windows.

## For agents

The protocol in `SKILL.md`, in five lines:

1. `snapshot . -o .bytecheck/before.json --store` before touching anything.
2. Do the work.
3. `verify .bytecheck/before.json --json` with a policy derived from the task.
4. On FAIL, fix the tree or report the violations verbatim. Never edit the manifest. Never widen the policy without being asked.
5. Quote the verdict line and `tree_hash_after` in the completion message.

Trust model: the agent is unreliable, not malicious, but it will make the check pass if you let it. So the manifest lives where the agent does not work, or its `tree_hash` is logged by the orchestrator; the policy comes from the orchestrator or a committed file the agent may not widen; and verification can be rerun by a hook, CI, or a second agent with `hash .` in one call. A determined adversary with the verifier's privileges is out of scope.

Ready-made wiring in `integrations/`: a Claude Code Stop hook, a GitHub Actions step that verifies a PR against its base, a pre-commit hook, and a paragraph for `AGENTS.md`.

## Why not `git diff`

git gives you data; bytecheck gives you a verdict. It works outside repositories, on untracked and ignored paths, on build outputs and generated docs. It cannot be defeated by `git add`, `git stash` or `git commit`. It has no opinion about whitespace. And it answers the question CI actually asks: did this change stay inside the lines, yes or no, exit code.

## Design

- One file, stdlib only. Copy it anywhere. No install, no network, no config discovery, no telemetry.
- Bytes, not interpretations. No normalisation, no ignore-whitespace, no mtime shortcuts.
- Verdict first: exit code is the API, JSON is the detail, prose is a courtesy.
- Deterministic: sorted paths, sorted keys, POSIX separators, LF output.
- Fail closed: unreadable file, newer manifest format, `--within` without a baseline, all exit 2.
- Nothing excluded by default except `.git/` and `.bytecheck/`. `node_modules/` and `.venv/` are yours to exclude. Silent exclusions are the implicit trust this tool exists to remove.
- Read-only by construction. The only writes are the manifest and the store, where you said.

Non-goals: VCS, diff viewer, formatter, linter, secret scanner, test runner, `.gitignore` semantics, signing, file watching, GUI, colour.

## Known edges

- Insertion at the very top of a file (before old line 1) never satisfies `--within`. Conservative by design.
- macOS NFC/NFD path differences are reported as-is.
- A case-only path collision from a Linux manifest on a case-insensitive filesystem is an error.
- Exec bits are not recorded on Windows.
- Files above 8 MiB get a single whole-file hunk rather than a quadratic diff.

## License

MIT.
