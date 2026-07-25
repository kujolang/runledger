# RunLedger Enterprise Review - 2026-06-19

## Executive summary

RunLedger is useful and coherent today as a local receipt ledger for AI-agent
runs. It is not yet "universally enterprise grade" in the sense of covering
multi-user coordination, audit export policies, signed receipts, or richer
workflow capture. The product is on a strong path because it is small, local,
readable, tested, and built around a crisp promise: record what happened during
an agent run without pretending to be an evaluator.

This pass focused on production polish: safer storage boundaries, better
malformed-data behavior, less repeated git work, cleaner markdown output, root
documentation cleanup, and more regression coverage.

## Completed in this pass

- Moved historical review artifacts from the repository root into
  `docs/reviews/`.
- Updated `README.md`, `AGENTS.md`, and `.agent/` handoff notes to match the
  current `src/` layout and docs structure.
- Added path-safe run-id validation so CLI-supplied IDs cannot traverse outside
  `<ledger>/runs`.
- Rejected JSON run files whose internal `id` does not match the filename.
- Preserved list/report tolerance by skipping malformed, unreadable, invalid,
  or mismatched records instead of crashing the whole command.
- Made nested ledger paths work by recursively creating ledger directories.
- Checked git repository state once per start/finish metadata bundle instead of
  repeating that probe for every git field.
- Escaped markdown table cells so task names, verdicts, providers, or model
  names containing `|` or newlines do not break generated reports.
- Treated `runledger report --output` with no value as a usage error.
- Added module and CLI regressions for unsafe IDs, mismatched run files, nested
  ledgers, missing report output values, and markdown escaping.

## Production-readiness assessment

Score: 84/100

- Scope clarity: 15/15
- Local-first safety: 14/15
- CLI usability: 12/15
- Storage robustness: 13/15
- Git metadata performance/safety: 10/10
- Test coverage: 12/15
- Documentation/presentation: 10/12
- Enterprise workflow features: 3/8
- Extensibility as a Kujo showcase: 5/5

Verdict: strong local tool, good public showcase candidate after one more
feature/documentation pass.

## Recommended next-session work queue

### P1 - Add command/test capture

The record schema already has `commands` and `tests`, but the CLI does not
populate them yet. Add commands such as:

- `runledger command <run-id> --name "npm test" --status pass --exit-code 0`
- `runledger test <run-id> --name "unit" --status pass --command "./tests/run.sh"`

Why it matters: this makes each receipt much more useful for comparisons and
handoffs without turning RunLedger into a full evaluator.

### P1 - Add machine-readable report export

`list`, `show`, and `compare` already support `--json`; `report` is markdown
only. Add one of:

- `runledger report --json`
- `runledger export --format json`

Why it matters: enterprise users often need stable artifacts for dashboards,
CI summaries, or downstream analysis.

### P2 - Add lock-file coordination

Atomic writes protect individual files, but concurrent writers can still race
around ID generation. Add a simple ledger-level lock around `start` and any
future multi-file operations.

Why it matters: local agent orchestration can easily run multiple attempts in
parallel.

### P2 - Add per-command help

Support `runledger help start` or `runledger start --help` with focused examples.

Why it matters: it improves discoverability without bloating global help.

### P2 - Strengthen storage diagnostics

List/report intentionally skip bad records. Consider adding:

- `runledger doctor`
- `runledger list --strict`
- warning counts for skipped files

Why it matters: silent tolerance is friendly, but operators also need a way to
find and repair damaged ledgers.

### P3 - Improve report presentation

The markdown report is stable, but it could be more polished:

- include task filter metadata,
- include ledger path/repo summary when relevant,
- group runs by task before the flat table for large ledgers,
- include total token usage where known.

Why it matters: RunLedger should feel like a polished Kujo-built artifact, not
only a raw CLI utility.

### P3 - Add release packaging guidance

Document the recommended way to install or package RunLedger once Kujo runtime
distribution conventions settle.

Why it matters: the README is clear for local development, but public adoption
will need a less bespoke install path.

## Residual risks

- No concurrent-writer protection yet.
- No cryptographic signing or tamper-evidence for receipts.
- No first-class command/test capture despite reserved schema fields.
- No `report --json` path for automation-heavy consumers.
- No formal schema version field or migration command.

## Suggested verification after next pass

```bash
KUJO=kujo ./tests/run.sh
KUJO=kujo ./bin/runledger help
KUJO=kujo ./bin/runledger report --ledger /tmp/runledger-demo
```
