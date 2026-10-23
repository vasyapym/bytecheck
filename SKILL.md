---
name: bytecheck
description: Byte-exact verification of what you changed on disk. Use when asked to "verify my changes", "prove you only edited X", "snapshot before editing", "check nothing else changed", "did the agent actually change it", "byte-exact", "no placeholders", or whenever you edit files for a user who wants evidence rather than a report. Snapshot before, verify after, quote the verdict.
---

# bytecheck

Your report is a claim. The filesystem is the evidence. This skill produces the evidence.

`bytecheck.py` sits beside this file. Run it as `python3 <this directory>/bytecheck.py`
(`python` if `python3` is not on PATH). One file, standard library only, Python 3.8+.
It never modifies the tree it checks. It writes only the manifest and the optional object
store, at the path you choose.

## Protocol

1. Before touching any file:

       python3 bytecheck.py snapshot . -o .bytecheck/before.json --store

   If the user or orchestrator gave you a manifest path or a policy file, use theirs.
   If `.bytecheck/before.json` already exists, do not overwrite it; ask, or use a new name.

2. Do the work.

3. Verify with a policy derived from the task:

       python3 bytecheck.py verify .bytecheck/before.json --json \
         --allow 'src/payments/**' \
         --expect 'src/payments/refund.py' \
         --deny '**/*.lock' --deny '.github/**'

   Or `--policy FILE` when one was supplied. Flags add to a policy file; they cannot
   loosen it.

4. Read `summary.verdict`.

   - `PASS`: done.
   - `FAIL`: fix the tree and rerun, or report the `violations` and `findings` verbatim.
   - `ERROR` (exit 2): the check could not complete. Report that. Do not claim success.

5. End your completion message with the verdict line and `tree_hash_after`, e.g.
   `PASS 2 changes, 0 violations  a1b2c3d4e5f6 -> 0f9e8d7c6b5a`. The user can recompute
   the second hash with `python3 bytecheck.py hash .` and compare.

## Deriving a policy from a task

- `--allow`: the paths the task names. Narrow beats wide. `src/payments/**`, not `src/**`.
- `--expect`: the file or files the task says must change. Catches "I edited it" when you did not.
- `--deny`: lockfiles, CI config, tests, migrations, generated files, unless the task is about them.
- `--allow-delete`: only when the task says to delete. `--allow` never covers deletions.
- `--within PATH:RANGES`: when told to change specific lines. Needs `--store` at snapshot time.
- No policy flags at all means "nothing may change". Use it for read-only tasks.
- `--allow '**'` is report-only. Use it only when the user asked for a report, not a check.

## Rules of conduct

- Never edit, regenerate, move or delete the manifest or the object store.
- Never widen `--allow`, add `--allow-delete`, add `--exclude`, or `--disable` a rule unless
  the user asked for it in this conversation. Narrowing is always fine.
- Never make a FAIL disappear by re-snapshotting. A FAIL is information for the user.
- Quote bytecheck output verbatim. Do not summarise violations into "minor issues".
- If a rule fires on content you believe is correct, say so and let the user decide.

## Cheat sheet

Commands

    snapshot [ROOT] -o FILE|- [--store [DIR]] [--exclude GLOB]...
    verify   [MANIFEST|-] [--root DIR] [--baseline DIR] [--policy FILE]
             [--allow G]... [--deny G]... [--expect G]... [--allow-delete G]...
             [--within PATH:RANGES]... [--disable RULE]... [--strict] [--no-scan]
    hash     PATH... [--expect HEX]        file, stdin (-), or tree hash of a directory
    same     A B                           two files or two trees, byte-identical or not
    delta    OLD NEW [--within RANGES]     hunks, EOL/BOM before and after, delta rules
    scan     PATH... [--strict]            content rules, no baseline needed

Every command takes `--json` (one JSON document on stdout, nothing else) and `--quiet`.

Exit codes

    0  PASS
    1  FAIL   policy violation, error-severity finding, or warning under --strict
    2  ERROR  usage or environment problem; partial results still printed, incomplete: true

Result JSON (verify)

    ok, incomplete, summary.verdict, summary.changes, summary.violations
    tree_hash_before, tree_hash_after
    changes[]      path, kind (added|deleted|modified|renamed|attr), allowed, reason,
                   before, after, hunks, added, removed, whitespace_only, eol_only,
                   within_ok, findings
    violations[]   kind (change_not_allowed|outside_within|expect_missing), path, reason
    findings[]     path, rule, severity (error|warn|info), line, message
    errors[]       path, error

Glob dialect: whole root-relative POSIX path; `*` stays in one segment, `**` crosses,
`?` is one character, trailing `/` means the directory and everything below.

Rules

    error  conflict-marker placeholder nul-in-text bidi-control bom-changed eol-changed
    warn   zero-width smart-quote nbsp mixed-eol shrunk trailing-newline-lost indent-flipped
    info   bom no-trailing-newline invalid-utf8

Rules run only on files you added or modified. Pre-existing debt cannot fail you.
