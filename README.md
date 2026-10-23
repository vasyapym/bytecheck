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

Exit `0` PASS, `1` FAIL, `2` could not check. `--json` for the full verdict. It never writes to the tree it checks.

## Why

LLM agents fail in a small number of repeatable ways, and none of them show up in the agent's own summary.

| Failure | What bytecheck does |
|---|---|
| Over-reach: drive-by refactors, reformatting, touched lockfiles or CI | Every path outside `--allow` is a violation |
| Under-delivery: claims an edit that never happened | `--expect` requires the change to exist |
| Deleted tests, deleted files | Deletions need `--allow-delete`, always |
| Placeholders: elision comments, bracketed snips | `placeholder`, error severity |
| Truncated output: a file lost more than half its bytes, the trailing newline is gone | `shrunk`, `trailing-newline-lost` |
| CRLF to LF, BOM added, tabs to spaces, straight quotes to smart quotes | `eol-changed`, `bom-changed`, `indent-flipped`, `smart-quote` |
| Zero-width, NBSP, bidi control characters, NUL bytes | `zero-width`, `nbsp`, `bidi-control`, `nul-in-text` |
| Merge-conflict residue | `conflict-marker` |
| Right edit, wrong file; a copy that is not byte-identical | `same`, `hash --expect` |

Whitespace-only and EOL-only changes are classified in the output. They are never ignored.

## Install

Copy one file. Check it.

```sh
curl -fsSLO https://raw.githubusercontent.com/vasyapym/bytecheck/v0.1.0/bytecheck.py
python3 bytecheck.py hash bytecheck.py --expect d8966c6f8e48890035d76e5c58c7ae5c845c06fc87bd4095066581cacbb7bab6
```

Not on PyPI yet. When it is, the distribution will be `bytecheck-cli`; the module and the command stay `bytecheck`.

For agents, the repository root is an Agent Skill. Copy `SKILL.md`, `bytecheck.py` and — for opencode — `opencode-capture.ts` into a skills directory such as `.claude/skills/bytecheck/`. `SKILL.md` carries the protocol; `bytecheck.py` sits beside it. See [For agents](#for-agents).

## Paste capture (opencode)

`opencode-capture.ts` ships with the skill: an opencode plugin that writes every
message the human types or pastes into the chat to `.bytecheck/inbox/` in the
project — one UTF-8 file per text part, a `.sha256` sidecar beside it. Byte-exact:
the file is the received text and nothing else, no normalisation. Copy it into
`~/.config/opencode/plugins/` and restart opencode; plugins load at startup only.

Why: a reply that exists only in chat context cannot be verified — an agent asked
to reproduce it produces a paraphrase, placeholders included. Once the paste is a
file, the harvest protocol in `SKILL.md` applies: hash the capture, read from the
file, place it with `same`, and never re-type received content.

## Commands

```text
snapshot [ROOT] [-o FILE|-] [--store [DIR]] [--exclude GLOB]... [--exclude-from FILE] [--no-default-excludes]
verify   [MANIFEST|-] [--root DIR] [--baseline DIR] [--policy FILE] [--allow GLOB]...
         [--deny GLOB]... [--expect GLOB]... [--allow-delete GLOB]... [--within PATH:RANGES]...
         [--exclude GLOB]... [--disable RULE]... [--no-scan] [--strict]
hash     PATH... [--expect HEX] [--exclude GLOB]...
same     A B [--exclude GLOB]...
delta    OLD NEW [--within RANGES] [--disable RULE]... [--strict]
scan     PATH... [--strict] [--disable RULE]... [--exclude GLOB]...
```

`snapshot` walks the tree, hashes every regular file, records symlink targets and exec bits, and writes a manifest, `.bytecheck/before.json` unless `-o` says otherwise (`-` for stdout). `--store` also keeps the file contents, so `verify` can show hunks, run the delta rules and enforce `--within` without git.

`verify` re-walks the tree, classifies every change as added, deleted, modified, renamed or attr, applies the policy, runs the content rules on added and modified files, and prints the verdict. It takes a manifest or `--baseline DIR`, a copy of the original tree. With no policy flags it asserts the tree is untouched. A rename is exactly one deleted and one added file with the same SHA-256. `--no-scan` skips the rules.

`hash` prints the SHA-256 and size of each file, or the tree hash of a directory. `-` reads stdin. `--expect HEX` turns it into a check and takes exactly one PATH.

`same` says whether two files or two trees are byte-identical, and where they first differ.

`delta` describes how two files differ: hunks, EOL and BOM before and after, whitespace-only and EOL-only flags, the delta rules.

`scan` runs the content rules on anything, no baseline needed.

Every command takes `--json`, exactly one JSON document on stdout, and `--quiet`, nothing at all. stdout carries results, stderr carries diagnostics. No colour, ever.

## Policy

```text
--allow GLOB          permit added, modified and attr changes. Never deletions.
--allow-delete GLOB   permit deletions. Data loss gets its own word.
--deny GLOB           forbid. Wins over everything. Fence lockfiles, CI, tests.
--expect GLOB         at least one change must match. Implies allow.
--within PATH:RANGES  every hunk in PATH inside these old-file lines, 1-based inclusive,
                      e.g. src/a.py:120-180,210-215. Needs --store or --baseline.
--exclude GLOB        leave paths out, on top of the manifest's excludes.
--disable RULE        turn a rule off, by name.
--strict              warnings fail.
--policy FILE         the same keys as JSON. Flags add to it; they cannot loosen it.
```

Glob dialect, one rule: patterns match the whole root-relative POSIX path. `*` stays within a segment, `**` crosses segments, `?` is one character, a trailing `/` means the directory and everything below. No implicit any-depth matching: `src/*.py` does not match `src/pkg/a.py`; `src/**` does.

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

Rules have names, not numbers. `error` fails the run. `warn` fails under `--strict`. `info` never fails.

```text
error  conflict-marker  placeholder  nul-in-text  bidi-control  bom-changed  eol-changed
warn   zero-width  smart-quote  nbsp  mixed-eol  shrunk  trailing-newline-lost  indent-flipped
info   bom  no-trailing-newline  invalid-utf8
```

In `verify`, rules run only on added and modified files. Pre-existing debt cannot fail you; only what the agent introduced can. Delta rules compare against before-content and need `--store` or `--baseline`. `smart-quote` and `nbsp` apply to code files only. `placeholder` matches ellipsis and elision phrases on comment lines in code, and bracketed snip tokens anywhere. Binary files are skipped by every text rule. Content rules skip files above 64 MiB. `shrunk` fires when a file of at least 1024 bytes ends below half its size. `indent-flipped` needs at least three indented lines on both sides. Rules are tuned for low false positives: a rule agents learn to disable is worse than no rule.

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
     "hunks": [{"old_start": 40, "old_end": 42, "new_start": 40, "new_end": 51, "added": 12, "removed": 3}],
     "whitespace_only": false, "eol_only": false, "findings": []}
  ],
  "violations": [{"kind": "change_not_allowed", "path": "tests/test_x.py", "change": "deleted",
                  "reason": "deletion not allowed (needs --allow-delete)"}],
  "findings": [],
  "summary": {"verdict": "FAIL", "changes": 2, "allowed": 1, "violations": 1, "untouched": false}
}
```

The example is trimmed. The full document carries `schema`, `tool_version`, `command`, `ok`, `incomplete`, `root`, `tree_hash_before`, `tree_hash_after`, `policy`, `excludes`, `baseline`, `changes`, `violations`, `findings`, `summary` and `errors`. `summary` holds `verdict`, `changes`, `allowed`, `violations`, `expect_missing`, `findings{error,warn,info}` and `untouched`. The keys of a `changes[]` entry: `path`, `kind`, `allowed`, `reason`, `before`, `after`, `binary`, `hunks`, `added`, `removed`, `whitespace_only`, `eol_only`, `note`, `within_ok`, `findings`, and `old_path` on renames. `violations[].kind` is `change_not_allowed`, `outside_within` or `expect_missing`. A finding has `path`, `rule`, `severity`, `line`, `message`.

`tree_hash` is specified so any tool can reproduce it: for entries sorted by path in code-point order, concatenate `type NUL path NUL payload NUL exec LF`, where payload is the file's sha256 hex, the symlink target, or empty, and exec is `x` or `-`. Hash that with SHA-256. The same tree yields the same hash on Linux, macOS and Windows.

## For agents

The protocol in `SKILL.md`, in five lines:

1. `snapshot . -o .bytecheck/before.json --store` before touching anything.
2. Do the work.
3. `verify .bytecheck/before.json --json` with a policy derived from the task.
4. On FAIL, fix the tree or report the violations verbatim. Never edit the manifest. Never widen the policy without being asked.
5. Quote the verdict line and `tree_hash_after` in the completion message.

Trust model: the agent is unreliable, not malicious, but it will make the check pass if you let it. So the manifest lives where the agent does not work, or the orchestrator logs the tree hash right after the snapshot; the policy comes from the orchestrator or a committed file the agent may not widen; and the verdict can be rechecked by a hook, CI or a second agent, `hash .` in one call. A determined adversary with the verifier's privileges is out of scope.

Ready-made wiring in `integrations/`: a Claude Code Stop hook, a GitHub Actions step that verifies a PR against its base, a pre-commit hook, and a paragraph for `AGENTS.md`.

## Why not `git diff`

git gives you data; bytecheck gives you a verdict. It works outside repositories, on untracked and ignored paths, on build outputs and generated docs. It cannot be defeated by `git add`, `git stash` or `git commit`. It has no opinion about whitespace. And it answers the question CI actually asks: did this change stay inside the lines, yes or no, exit code.

## Design

- One file, stdlib only. Copy it anywhere. No install, no network, no config discovery, no telemetry.
- Bytes, not interpretations. No normalisation, no ignore-whitespace, no mtime shortcuts.
- Verdict first: the exit code is the API, JSON is the detail, prose is a courtesy.
- Deterministic: sorted paths, sorted keys, POSIX separators, LF output.
- Fail closed: anything it cannot check, an unreadable file, a newer manifest format, `--within` without before-content, exits 2 and never passes quietly.
- Nothing excluded by default except `.git/` and `.bytecheck/`; `--no-default-excludes` drops even those. `node_modules/` and `.venv/` are yours to exclude. Silent exclusions are the implicit trust this tool exists to remove.
- Read-only by construction. The only writes are the manifest and the store, where you said.

Non-goals: VCS, diff viewer, formatter, linter, secret scanner, test runner, `.gitignore` semantics, signing, file watching, GUI, colour.

## Known edges

- Insertion at the very top of a file (before old line 1) never satisfies `--within`. Conservative by design.
- macOS NFC/NFD path differences are reported as-is.
- A case-only path collision from a Linux manifest on a case-insensitive filesystem is an error.
- Exec bits are not recorded on Windows.
- Files above 8 MiB get a single whole-file hunk rather than a line diff.

## License

MIT.
