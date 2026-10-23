# examples

One small before/after tree that triggers every rule once. `before/` is the snapshot
source, `after/` is the agent's output, `policy.json` is what the orchestrator handed down.

    python3 ../bytecheck.py verify --baseline before --root after --policy policy.json

Expected: FAIL, with one violation or finding per rule, in a stable order. The testing
agent populates this directory alongside `tests/fixtures/`.
