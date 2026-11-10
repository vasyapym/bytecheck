# bytecheck

bytecheck snapshots a directory before an agent works and verifies it after, byte for byte. It fails on anything the policy did not allow: edits outside scope, edits that never happened, deletions. It also fails on what no task asks for: placeholders, conflict markers, invisible characters, line-ending flips, lost UTF-8. One Python file, standard library only, 3.8+. No git required.

```sh
python3 bytecheck.py snapshot . -o .bytecheck/before.json --store
# ... agent works ...
python3 bytecheck.py verify .bytecheck/before.json \
  --allow 'src/payments/**' --expect 'src/payments/refund.py' --deny '**/*.lock'
```

```text
baseline .bytecheck/before.json  created 2026-11-10T12:36:06Z  bytecheck 0.2.0  root .
M src/payments/refund.py +12 -3 allowed
A src/payments/refund_test.py allowed
D tests/test_ledger.py VIOLATION deletion not allowed (needs --allow-delete)
! src/payments/refund.py:41 placeholder elision phrase: # ... rest of the function unchanged
FAIL 3 changes, 1 violation, 1 error finding  a1b2c3d4e5f6 -> 0f9e8d7c6b5a
```

Exit 0 PASS, 1 FAIL, 2 could not check. Every command takes `--json`, exactly one document on stdout; `--quiet`, nothing at all; and `--report FILE`, the full output to a UTF-8 file and only the verdict line on stdout. The only writes are the manifest, the store, the report and an extracted block, where you said.

## Install

Copy one file. Check it with itself.

```sh
curl -fsSLO https://raw.githubusercontent.com/vasyapym/bytecheck/v0.2.0/bytecheck.py
python3 bytecheck.py hash bytecheck.py --expect 03742ad77c6038ed6cdebc60855656df69b8245f72700171ca11854615c88606
```

Not on PyPI.

### Windows

```powershell
curl.exe -fsSLO https://raw.githubusercontent.com/vasyapym/bytecheck/v0.2.0/bytecheck.py
curl.exe -fsSLO https://raw.githubusercontent.com/vasyapym/bytecheck/v0.2.0/bytecheck.cmd
py -3 bytecheck.py hash bytecheck.py --expect 03742ad77c6038ed6cdebc60855656df69b8245f72700171ca11854615c88606
py -3 bytecheck.py hash bytecheck.cmd --expect 7f1fbf8c7be2895a3c0bb2a41ff5033b247dd896a421f83f6c5f1cee4d5ca40c
.\bytecheck.cmd --version
```

Run it as `py -3 bytecheck.py`, or through `bytecheck.cmd`, which finds `bytecheck.py` beside itself, sets `PYTHONUTF8=1` and `PYTHONIOENCODING=utf-8`, and tries `py -3`, `python3`, `python` in that order, skipping the Microsoft Store stub. The shim was written on macOS and is untested there: run `bytecheck.cmd --version` once before relying on it. Without the shim, set those two variables yourself or switch the console to UTF-8 (`chcp 65001` in cmd.exe, `[Console]::OutputEncoding = [Text.UTF8Encoding]::new()` in PowerShell), or non-ASCII paths and findings are mangled on the way out. `--report FILE` sidesteps the console: the file is UTF-8 bytes whatever the code page, and only the verdict line reaches stdout; read it with `Get-Content -Encoding UTF8`. Never capture output with `>` in PowerShell, which re-encodes and rewrites line endings; `--report` and `--to` write exact bytes. Single-quote globs in PowerShell (double quotes in cmd.exe) so `**` reaches the tool intact.

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

A policy file holds the same decisions, lists of globs or rule names plus a boolean `strict`; keys `allow`, `deny`, `expect`, `allow_delete`, `within`, `disable`, `exclude`, `strict`:

```json
{"allow": ["src/payments/**"], "expect": ["src/payments/refund.py"], "deny": ["**/*.lock"], "within": ["src/payments/refund.py:120-180,210-215"], "strict": true}
```

Globs match the whole root-relative POSIX path: `*` stays within a segment, `**` crosses segments, `?` is one character, a trailing `/` is the directory and everything below. `src/*.py` does not match `src/pkg/a.py`; `src/**` does. With no policy flags, `verify` asserts the tree is untouched. Nothing is excluded by default except `.git/` and `.bytecheck/`; `node_modules/` and `.venv/` are yours to `--exclude`, and a junk list for `--exclude-from` reads `**/Thumbs.db`, `**/.DS_Store`, `**/~$*`, `**/*.tmp`. Excludes change the tree hash, so record them beside it.

## Rules

In `verify`, content rules run on added and modified files only, so pre-existing debt cannot fail you. `error` fails the run, `warn` fails under `--strict`, `info` never fails. `--disable RULE` turns one off by name.

```text
error  conflict-marker  placeholder  nul-in-text  bidi-control  bom-changed  eol-changed  utf8-lost
warn   zero-width  smart-quote  nbsp  mixed-eol  mixed-script  shrunk  trailing-newline-lost  indent-flipped
info   bom  no-trailing-newline  invalid-utf8
```

New in 0.2: `utf8-lost` fires when a file that was valid UTF-8 no longer is, the shape of a cp1251 save or of PowerShell 5's UTF-16 `Out-File`; it reads the raw bytes, so a result that now classifies as binary does not escape it. `mixed-script` warns on a word mixing Latin, Cyrillic or Greek letters, one finding per line naming the first such token: a model glitch, or a lookalike character planted in an identifier or a config value. Cyrillic inflections of Latin brand names in prose are the known false positive; it stays a warning because the config-file case is the one that matters. Rules that compare before and after (`utf8-lost`, `eol-changed`, `bom-changed`, ...) need `--store` or `--baseline`. Whitespace-only and EOL-only changes are classified in the output, never ignored. Binary files are skipped by every text rule.

## Commands

`snapshot` hashes every regular file, records symlink targets and exec bits, and writes the manifest; its summary line counts files and bytes, so a surprising total points at a missing exclude. `--store` keeps the contents too, so `verify` can show hunks, run the delta rules and enforce `--within` without git. `verify` takes that manifest, or `--baseline DIR`, a copy of the original tree; its text output opens with a `baseline` line naming the manifest, its creation time, the version that wrote it and its root, so a stale manifest shows before the verdict does. `hash` prints the SHA-256 of files or the tree hash of a directory; `--expect HEX` makes it a check. `same` says whether two files or two trees are byte-identical, and where they first differ. `delta` describes how two files differ: hunks, EOL and BOM before and after, whitespace-only and EOL-only flags. `scan` runs the rules on anything, no baseline needed.

`--report FILE`, on every command, writes the full output to FILE atomically, creating parent directories, and leaves the last text line on stdout: the verdict, the hash, `identical`. With `--json` the file holds the one document and stdout the human verdict line. Keep reports under `.bytecheck/`, excluded by default, so a report never dirties the next verify. An unwritable FILE is exit 2 with the reason on stderr and the verdict still on stdout; `snapshot -o -` refuses `--report`.

`--format unified|md`, on `verify` and `delta`, renders the same result, same policy, same verdict, as a git-style patch or a markdown review book; both need before-content (`--store` or `--baseline`, exit 2 otherwise) and refuse `--json`. `unified` is the patch and nothing else: byte-faithful, CRLF kept, the no-newline marker where it belongs, renames and binaries marked as git marks them; `git apply` and `patch -p1` take it, and the verdict rides on the exit code, or on stdout with `--report`. `md` opens with a title carrying the verdict line and the baseline line, gives each changed file a `##` with its fenced diff and findings (fences outgrow any backtick run inside, so diffs of markdown render), then Violations, Findings, and the verdict line last.

`blocks FILE` lists the fenced code blocks of a markdown or text file, `-` for stdin: index, line range, bytes, sha256, info string and label, the label being the nearest preceding ATX heading; listing never fails. `blocks FILE --extract SEL --to PATH` writes one block's body bytes exactly, original line endings included; SEL is an index if all digits, otherwise an exact label, and an unknown or ambiguous one is exit 2 with the candidates. `blocks FILE --same [ROOT]` resolves every label as a path under ROOT and reports identical, differs at byte N, or no file; a difference fails, a missing file is counted and does not. Fences are CommonMark: backticks or tildes, up to three spaces of indent, a longer outer fence may hold shorter inner ones, an unterminated fence runs to EOF and is flagged. It is the one write besides manifest, store and report, and like them it goes only where named.

The tree hash is specified so any tool can reproduce it: entries sorted by path in code-point order, each written as `type NUL path NUL payload NUL exec LF`, payload being the file's sha256 hex, the symlink target, or empty, exec `x` or `-`, the whole hashed with SHA-256. The same tree yields the same hash on Linux, macOS and Windows.

## For agents

The repository root is an Agent Skill. Copy `SKILL.md` and `bytecheck.py`, plus `bytecheck.cmd` on Windows and `opencode-capture.ts` for opencode, into a skills directory such as `.claude/skills/bytecheck/`. The protocol in `SKILL.md`: snapshot with `--store` before touching anything; do the work; `verify --json --report .bytecheck/verify.json` with a policy derived from the task, so only the verdict line enters the context; on FAIL read the report, check its `baseline` first, then fix the tree or report the violations verbatim, never editing the manifest, never widening the policy unasked; end the completion message with the verdict line and `tree_hash_after`. Received material is placed from the file it landed in, never retyped: `blocks CAPTURE --extract LABEL --to TARGET` copies each fenced block byte for byte and `blocks CAPTURE --same` proves it.

The agent runs this check on itself: its report is a claim, the tree is the evidence, the verdict line is the agent showing its work. The hygiene that would stop a hostile agent is kept because it keeps an honest agent's evidence clean. The manifest lives outside the paths being edited, or the tree hash is logged right after the snapshot, so a stale or regenerated baseline cannot pass quietly; the policy comes from the task or a committed file, narrowed freely and widened only when asked; and the verdict is recomputable by anyone, a hook, CI or a second agent, with `hash .` in one call. Ready-made in `integrations/`: a Claude Code Stop hook, a GitHub Actions step, a pre-commit hook, a paragraph for AGENTS.md.

`opencode-capture.ts` is an optional opencode plugin: every message the human types or pastes is written to `.bytecheck/inbox/` in the project, one byte-exact UTF-8 file per text part with a `.sha256` sidecar holding the bare hex, so `hash CAPTURE --expect $(cat CAPTURE.sha256)` checks it. Assistant messages, synthetic parts and subagent prompts are not captured. A reply that exists only in chat context cannot be verified; once it is a file, the harvest protocol in `SKILL.md` applies. Copy it into `~/.config/opencode/plugins/` and restart opencode.

## Upgrade

Re-run the install block over every installed copy, the one beside `SKILL.md` included, and check the pin. `python3 bytecheck.py same CLONE/bytecheck.py INSTALLED/bytecheck.py` says whether a copy is current, `--version` what it is. Manifests and stores written by 0.1 keep working. `integrations/` is unchanged in this release and still fetches v0.1.0, which keeps working; point it at v0.2.0 and the pin above when CI should run 0.2.

## Compatibility

0.2 is additive. Manifests stay format 1: 0.2 reads 0.1 manifests and 0.1 reads 0.2 manifests. No flag was removed or renamed, exit codes are unchanged, and the verdict line is unchanged and still the last line of text output, with two deliberate exceptions: `--format unified` prints the patch and nothing else, `--report` prints the verdict line and nothing else. JSON gains keys only, `baseline` in verify, `bytes` in snapshot, the `blocks` document; nothing renamed or removed. The tree hash algorithm and the default excludes are unchanged, so every hash recorded under 0.1 is reproducible under 0.2. The complete list of text-output differences from 0.1: `verify` opens with the baseline line; `snapshot`'s summary line carries the byte total.

## Why not git diff

git gives you data; bytecheck gives you a verdict. It works outside repositories, on untracked and ignored paths, on build outputs, and cannot be defeated by `git add`, `git stash` or `git commit`. It has no opinion about whitespace. It answers the question CI actually asks: did this change stay inside the lines, exit code.

MIT.
