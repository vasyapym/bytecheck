# bytecheck

bytecheck snapshots a directory before an agent works and verifies it after, byte for byte. It fails on anything the policy did not allow: edits outside scope, edits that never happened, deletions. It also fails on what no task asks for: placeholders, conflict markers, invisible characters, line-ending flips. One Python file, standard library only, 3.8+. No git required.

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

Exit 0 PASS, 1 FAIL, 2 could not check. Every command takes `--json`, exactly one document on stdout, and `--quiet`, nothing at all. The only writes are the manifest and the store, where you said.

## Install

Copy one file. Check it with itself.

```sh
curl -fsSLO https://raw.githubusercontent.com/vasyapym/bytecheck/v0.1.0/bytecheck.py
python3 bytecheck.py hash bytecheck.py --expect d8966c6f8e48890035d76e5c58c7ae5c845c06fc87bd4095066581cacbb7bab6
```

Not on PyPI yet.

## Policy

```text
--allow GLOB          permit added, modified and attr changes. Never deletions.
--allow-delete GLOB   permit deletions. Data loss gets its own word.
--deny GLOB           forbid. Wins over everything. Fence lockfiles, CI, tests.
--expect GLOB         at least one change must match. Implies allow.
--within PATH:RANGES  every hunk in PATH inside these old-file lines, 1-based inclusive,
                      e.g. src/a.py:120-180,210-215. Needs --store or --baseline.
--policy FILE         the same keys as JSON. Flags add to it; they cannot loosen it.
--strict              warnings fail.
```

Globs match the whole root-relative POSIX path: `*` stays within a segment, `**` crosses segments, `?` is one character, a trailing `/` is the directory and everything below. `src/*.py` does not match `src/pkg/a.py`; `src/**` does. With no policy flags, `verify` asserts the tree is untouched. Nothing is excluded by default except `.git/` and `.bytecheck/`; `node_modules/` and `.venv/` are yours to `--exclude`.

## Rules

In `verify`, content rules run on added and modified files only, so pre-existing debt cannot fail you. `error` fails the run, `warn` fails under `--strict`, `info` never fails. `--disable RULE` turns one off by name.

```text
error  conflict-marker  placeholder  nul-in-text  bidi-control  bom-changed  eol-changed
warn   zero-width  smart-quote  nbsp  mixed-eol  shrunk  trailing-newline-lost  indent-flipped
info   bom  no-trailing-newline  invalid-utf8
```

Whitespace-only and EOL-only changes are classified in the output, never ignored. Binary files are skipped by every text rule.

## Commands

`snapshot` hashes every regular file, records symlink targets and exec bits, and writes the manifest; `--store` keeps the contents too, so `verify` can show hunks, run the delta rules and enforce `--within` without git. `verify` takes that manifest, or `--baseline DIR`, a copy of the original tree. `hash` prints the SHA-256 of files or the tree hash of a directory; `--expect HEX` makes it a check. `same` says whether two files or two trees are byte-identical, and where they first differ. `delta` describes how two files differ: hunks, EOL and BOM before and after, whitespace-only and EOL-only flags. `scan` runs the rules on anything, no baseline needed.

The tree hash is specified so any tool can reproduce it: entries sorted by path in code-point order, each written as `type NUL path NUL payload NUL exec LF`, payload being the file's sha256 hex, the symlink target, or empty, exec `x` or `-`, the whole hashed with SHA-256. The same tree yields the same hash on Linux, macOS and Windows.

## For agents

The repository root is an Agent Skill. Copy `SKILL.md`, `bytecheck.py` and, for opencode, `opencode-capture.ts` into a skills directory such as `.claude/skills/bytecheck/`. The protocol in `SKILL.md`: snapshot with `--store` before touching anything; do the work; `verify --json` with a policy derived from the task; on FAIL, fix the tree or report the violations verbatim, never edit the manifest, never widen the policy unasked; quote the verdict line and `tree_hash_after` in the completion message.

The agent is unreliable, not malicious, but it will make the check pass if you let it. So the manifest lives where the agent does not work, or the orchestrator logs the tree hash right after the snapshot; the policy comes from the orchestrator or a committed file the agent may not widen; and the verdict is rechecked by a hook, CI or a second agent, `hash .` in one call. Ready-made in `integrations/`: a Claude Code Stop hook, a GitHub Actions step, a pre-commit hook, a paragraph for AGENTS.md.

`opencode-capture.ts` is an opencode plugin that writes every message the human types or pastes into the chat to `.bytecheck/inbox/` in the project, one byte-exact UTF-8 file per text part with a `.sha256` sidecar. Assistant messages, synthetic parts and subagent prompts are not captured. A reply that exists only in chat context cannot be verified; once it is a file, the harvest protocol in `SKILL.md` applies. Copy it into `~/.config/opencode/plugins/` and restart opencode.

## Why not git diff

git gives you data; bytecheck gives you a verdict. It works outside repositories, on untracked and ignored paths, on build outputs, and cannot be defeated by `git add`, `git stash` or `git commit`. It has no opinion about whitespace. It answers the question CI actually asks: did this change stay inside the lines, exit code.

MIT.
