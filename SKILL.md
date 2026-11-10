---
name: bytecheck
description: Byte-exact self-verification of your own edits. Snapshot a directory before you touch it, verify it after against the policy the task implies (allowed, expected, denied paths), end with a verdict line anyone can recompute. Also copies fenced code blocks out of markdown byte-for-byte (blocks), renders changes as a git-applyable patch or a markdown review book (--format), keeps full reports out of the context window (--report) and runs content-hygiene rules on any file (scan). Use when asked to "verify my changes", "prove you only edited X", "snapshot before editing", "check nothing else changed", "show exactly what changed", "byte-exact", "no placeholders", or whenever you edit files and want to show the work is exactly what you say it is. Linux, macOS, Windows.
---

# bytecheck

Documents bytecheck 0.2.x — if `--version` disagrees, the tool and its `--help` are right.

Your report is a claim. The filesystem is the evidence. bytecheck is how you produce that evidence yourself: record the tree before you edit, compare after, end with a verdict and a hash anyone can recompute. It is a discipline of showing your work, not a gate held over you; its mechanisms only keep the check you run on yourself from loosening by accident.

## Running it

`bytecheck.py` sits beside this file: one file, standard library only, Python 3.8+. It never modifies the tree it checks and writes only where you name a path: manifest (`-o`), store (`--store`), report (`--report`), extracted block (`--to`).

Interpreter order on every platform: `py -3`, then `python3`, then `python` — the first that prints a 3.x `--version` is yours for the session (on Windows a bare `python3` may be the Store stub). Commands below read `python3 bytecheck.py`; substitute your interpreter and this file's directory.

Windows: set `PYTHONIOENCODING=utf-8` and `PYTHONUTF8=1`, or run `bytecheck.cmd` beside this file — it sets both, picks the interpreter in that order and forwards every argument; it is untested on the authoring host, so run `bytecheck.cmd --version` once first. Never capture output with `>` in PowerShell (it re-encodes and rewrites line endings); `--report FILE` and `--to PATH` write exact bytes. Globs: single quotes in sh and PowerShell, double quotes in cmd.exe.

## Protocol

1. From the project root, before touching any file:

       python3 bytecheck.py snapshot . -o .bytecheck/before.json --store

   The summary line gives file count and byte total; a surprising total means missing excludes (Recipes). Use the manifest path or policy file you were given, if any. If `.bytecheck/before.json` already exists, do not overwrite it: ask, or pick a new name.

2. Do the work.

3. Verify with a policy derived from the task — full result to a file, verdict to stdout:

       python3 bytecheck.py verify .bytecheck/before.json --json --report .bytecheck/verify.json \
         --allow 'src/payments/**' \
         --expect 'src/payments/refund.py' \
         --deny '**/*.lock' --deny '.github/**'

   Or `--policy FILE` when one was supplied; flags add to a policy file and cannot loosen it. Only the verdict line enters your context; the report sits under `.bytecheck/`, which is excluded, so it never dirties the next verify.

4. Act on the verdict.

   - `PASS` (exit 0): done.
   - `FAIL` (exit 1): read `.bytecheck/verify.json`. Check `baseline` first — a manifest left over from an earlier task gives a false FAIL; say so instead of re-snapshotting. Then fix the tree and rerun, or report `violations` and `findings` verbatim.
   - `ERROR` (exit 2): the check could not complete. Report that. Do not claim success.

5. End your completion message with the verdict line and `tree_hash_after`, e.g. `PASS 2 changes, 0 violations a1b2c3d4e5f6 -> 0f9e8d7c6b5a`. Anyone can recompute the second hash with `python3 bytecheck.py hash .` (same excludes) and compare. Without `--json`, verify's text opens with `baseline FILE created ISO bytecheck VERSION root ROOT` and ends with the verdict line; with `--report`, stdout is the verdict alone.

## Deriving a policy from the task

- `--allow`: the paths the task names. Narrow beats wide: `src/payments/**`, not `src/**`.
- `--expect`: the files the task says must change; implies `--allow` for them and catches the edit you meant to make and did not.
- `--deny`: lockfiles, CI config, tests, migrations, generated files, unless the task is about them. Deny wins over everything.
- `--allow-delete`: only when the task says to delete. `--allow` never covers deletions.
- `--within PATH:RANGES`: when told to change specific lines; old-file numbering, 1-based inclusive. Needs `--store` at snapshot time or `--baseline`.
- No policy flags means nothing may change. Use it for read-only tasks.
- `--allow '**'` permits everything except deletions: a report, not a check. Only when the user asked for a report.

A policy file (`--policy .bytecheck/policy.json`) holds the same decisions — lists of globs or rule names, `strict` a boolean:

    {"allow": ["src/payments/**"], "expect": ["src/payments/refund.py"], "deny": ["**/*.lock", ".github/**", "tests/**"], "allow_delete": [], "disable": [], "exclude": ["node_modules/"], "strict": true}

## Showing the change

    python3 bytecheck.py verify .bytecheck/before.json --format unified --report .bytecheck/changes.patch
    python3 bytecheck.py verify .bytecheck/before.json --format md --report .bytecheck/CHANGES.md

Both need before-content (`--store` at snapshot time or `--baseline DIR`; exit 2 otherwise), refuse `--json`, and still apply the policy: same verdict, different rendering. Write them with `--report`, never `>`. `unified` is a git-style patch and nothing else — byte-faithful, CRLF kept — for `git apply .bytecheck/changes.patch` or `patch -p1`; binary sections read `Binary files ... differ` and are not applyable; without `--report` the patch is the whole stdout and only the exit code carries the verdict. `md` is a review book: title (the verdict) and baseline line, one `##` per changed file with its fenced diff and findings, then Violations, Findings, verdict line last. `delta OLD NEW --format unified|md` does the same for two files.

## Harvest: received material comes from files

A specialist's reply, a pasted document, user data: work from the file it landed in, never from chat context. Retyping or regenerating received content yields a paraphrase with placeholders. The transcript is a claim; the file is the evidence.

1. `python3 bytecheck.py scan CAPTURE` — rules on the received text; findings here are facts about the paste, not about you.
2. `python3 bytecheck.py hash CAPTURE --expect HEX` — HEX from the `.sha256` sidecar or the sender (`$(cat CAPTURE.sha256)` in sh, `(Get-Content CAPTURE.sha256)` in PowerShell): intact since it landed.
3. `python3 bytecheck.py blocks CAPTURE` — each fenced block with index, lines, bytes, sha256, info string and label. The label is the nearest preceding ATX heading, so a well-formed capture heads each block with its target path (`## src/app.py`, backticks allowed). Read the file; it is the source of truth for placement.
4. Place it. A whole-file capture (the file is the deliverable): copy it with your shell, then `python3 bytecheck.py same CAPTURE TARGET` must report identical. A document with fenced blocks: per block `python3 bytecheck.py blocks CAPTURE --extract LABEL --to TARGET` — body bytes copied exactly, EOLs included; LABEL is the heading text (an index works too but shifts when the document is edited, so record labels). Then the proof: `python3 bytecheck.py blocks CAPTURE --same` (FILE before `--same`, optional ROOT after). Every block whose label is a path must read identical; a label that is not a path ("Notes") shows `no file` and does not fail, so a PASS with 0 identical proves nothing — check the count against what you placed.
5. Verify as usual: blocks proves placement, verify proves scope.
6. When the harvest is verified and recorded, delete the inbox files; under `.bytecheck/` they are excluded and need no policy flag (an inbox elsewhere in the tree needs `--allow-delete`).

## Capture (opencode, optional): pastes land on disk

Optional and opencode-only; Harvest applies to any file you were handed regardless. `opencode-capture.ts` ships beside this file. Installed, every message the human types or pastes is written to `.bytecheck/inbox/` in the project opencode runs in, one UTF-8 file per text part plus a `.sha256` sidecar, named `<timestamp>-<msgID>-pN.txt`. Assistant messages, synthetic parts and subagent prompts are not captured; `BYTECHECK_INBOX` moves the inbox.

Install once: copy the file into `~/.config/opencode/plugins/` and restart opencode — plugins load at startup only.

## Recipes

- Exactly these files changed: `verify M --expect a --expect b` and no `--allow`.
- Rounds: one manifest per round (`-o .bytecheck/round-03.json`), one shared store (`--store .bytecheck/objects`) — content-addressed, so repeats cost nothing and every round keeps its hunks.
- Junk: `snapshot . --exclude-from .bytecheck/excludes.txt` with lines such as `node_modules/`, `**/Thumbs.db`, `**/.DS_Store`, `**/~$*`, `**/*.tmp`; verify inherits the manifest's excludes. Excludes change the tree hash, so record them beside it. A file bytecheck cannot read keeps the verdict at ERROR: exclude it.
- Review book for the user: `verify M --format md --report .bytecheck/CHANGES.md`.
- Deploy probe: `curl -fsSL -o .bytecheck/probe.bin URL` (`curl.exe` in PowerShell), then `hash .bytecheck/probe.bin --expect HEX`, HEX from `hash` of the local artifact.
- Deploy manifest: `snapshot DEPLOYDIR -o .bytecheck/deploy.json` right after deploying; later `verify .bytecheck/deploy.json --root DEPLOYDIR` with no policy flags asserts it is untouched.

## Rules of conduct

- Never edit, regenerate, move or delete the manifest or the store.
- Never place received code by retyping when `blocks --extract` or a copy can place it. If no capture file exists, say so.
- Never widen `--allow`, add `--allow-delete`, add `--exclude`, or `--disable` a rule unless the user asked for it in this conversation. A check you can quietly relax is not a check. Narrowing is always fine.
- Never make a FAIL disappear by re-snapshotting. A FAIL is information for the user.
- Quote bytecheck output verbatim. Do not summarise violations into "minor issues".
- If a rule fires on content you believe is correct, say so and let the user decide.
- Keep reports, patches and books under `.bytecheck/`; put nothing there the task should see, because nothing there is checked.

## Cheat sheet

Commands

    snapshot [ROOT] [-o FILE|-] [--store [DIR]] [--exclude G]... [--exclude-from FILE] [--no-default-excludes]
    verify   [MANIFEST|-] [--root DIR] [--baseline DIR] [--policy FILE]
             [--allow G]... [--deny G]... [--expect G]... [--allow-delete G]...
             [--within PATH:RANGES]... [--exclude G]... [--disable RULE]... [--no-scan] [--strict]
             [--format text|unified|md]
    hash     PATH... [--expect HEX] [--exclude G]...   file sha256 and size; - is stdin; directory = tree hash
    same     A B [--exclude G]...                      two files or two trees, byte-identical or not
    delta    OLD NEW [--within RANGES] [--disable RULE]... [--strict] [--format text|unified|md]
    scan     PATH... [--strict] [--disable RULE]... [--exclude G]...   content rules, no baseline needed
    blocks   FILE [--extract SEL [--to PATH]] [--same [ROOT]]   fenced blocks: list, copy one, compare all

Every command takes `--json` (one JSON document on stdout, nothing else), `--quiet` (exit code only) and `--report FILE` (full output to FILE, UTF-8, atomic; stdout keeps the last text line). `snapshot -o -` refuses `--report` and `--quiet`. `blocks --extract` without `--to PATH` streams raw bytes and refuses `--json` and `--quiet` (`--report` then receives the bytes); listing never fails; `--same` fails on a difference, not on a missing file. Defaults: manifest `.bytecheck/before.json`; excludes `.git/` and `.bytecheck/`, nothing else.

Exit codes

    0  PASS
    1  FAIL   policy violation, error-severity finding, warning under --strict, difference (same, blocks --same)
    2  ERROR  usage or environment problem; partial results still printed, incomplete: true

Result JSON (verify) — v0.2 adds keys; nothing renamed or removed

    ok, incomplete, tree_hash_before, tree_hash_after
    baseline       manifest path, created, tool version, root, store (true|false)
    summary        verdict, changes, allowed, violations, expect_missing,
                   findings{error,warn,info}, untouched
    changes[]      path, kind (added|deleted|modified|renamed|attr), allowed, reason,
                   before, after, old_path (renamed only), binary,
                   hunks[{old_start,old_end,new_start,new_end,added,removed}],
                   added, removed, whitespace_only, eol_only, note, within_ok, findings
    violations[]   kind (change_not_allowed|outside_within|expect_missing), path, change, reason
    findings[]     path, rule, severity (error|warn|info), line, message
    errors[]       what could not be checked

snapshot JSON adds the file count and `bytes`; blocks JSON lists per block index, lines, bytes, full sha256, info string, label and, with `--same`, the comparison.

Glob dialect: whole root-relative POSIX path; `*` stays in one segment, `**` crosses, `?` is one character, trailing `/` means the directory and everything below. No implicit any-depth matching: `Thumbs.db` is the root file only; `**/Thumbs.db` reaches below it.

Rules

    error  conflict-marker placeholder nul-in-text bidi-control bom-changed eol-changed utf8-lost
    warn   zero-width smart-quote nbsp mixed-eol mixed-script shrunk trailing-newline-lost indent-flipped
    info   bom no-trailing-newline invalid-utf8

`error` fails, `warn` fails under `--strict`, `info` never fails. In verify, rules run only on files you added or modified, so findings are about your change, not the project's history; rules that compare before and after (`utf8-lost`, `eol-changed`, `bom-changed`, ...) need before-content (`--store` or `--baseline`).

New in 0.2: `utf8-lost` — valid UTF-8 before, not after; a cp1251 save or PowerShell 5's UTF-16 `Out-File`; fix the encoding, never disable the rule. `mixed-script` — one word mixing Latin, Cyrillic or Greek letters, the shape of a lookalike character in an identifier or config value; known false positives are Cyrillic inflections of Latin brand names in prose ("GitHubе") and Greek letters in scientific notation (μs, Δt) — report them as such.
