# Changelog

Semantic versioning for the tool. The manifest `format` integer bumps only on breaking
schema changes; `verify` refuses manifests newer than it understands.

## 0.1.0 - unreleased

First release.

- Commands: snapshot, verify, hash, same, delta, scan.
- Policy: allow, deny, expect, allow-delete, within, policy file, strict.
- Change kinds: added, deleted, modified, renamed, attr.
- Sixteen content rules across error, warn, info.
- Manifest format 1, result schema 1.
- Content-addressed object store for hunks and --within without git.
- Exit codes 0/1/2, --json, --quiet, stdout/stderr separation.
