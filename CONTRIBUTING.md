# Contributing

Keep it one file. Keep it stdlib. Keep Python 3.8.

That is `bytecheck.py`. The opencode capture plugin (`opencode-capture.ts`) ships
beside the skill, not inside the package: TypeScript, node builtins only, no runtime
dependencies, no bytecheck.py changes just to capture.

A change to `bytecheck.py` needs a test in `tests/`. A new rule needs one positive and one
negative fixture, and a line in README and SKILL.md. A new flag needs a reason the existing
six commands and fifteen-odd rules cannot cover.

Things that will not be merged: colour output, a config-file search path, default excludes
beyond `.git/` and `.bytecheck/`, any normalisation of bytes before comparison, any network
call, any dependency.

## Release checklist

1. Bump `__version__` in `bytecheck.py` (pyproject reads it from there).
2. Move the CHANGELOG `unreleased` section under the version and date.
3. `python3 bytecheck.py scan . --strict` and the test suite on all three OSes (CI does this).
4. Tag `vX.Y.Z`. The release workflow attaches `bytecheck.py` and `SHA256SUMS`.
5. Paste the digest into the README install block.
6. Publish to PyPI if the version is a release, not a pre-release.
