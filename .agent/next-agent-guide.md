# Next Agent Guide

## Start here

1. Confirm runtime:
   - `kujo --help` must include `run`
2. Run verification:
   - `KUJO=/path/to/kujo ./tests/run.sh`
3. Spot-check CLI:
   - `KUJO=/path/to/kujo ./bin/runledger help`

## Current status

- Core receipt workflow is working: start, finish, list, show/json, note,
  followup, usage, cost, compare, report.
- Writes are atomic for records and reports.
- Receipt mutations serialize through per-record ownership locks; concurrent
  writers are covered by the CLI integration suite.
- CLI input validation now maps bad numeric values to usage errors.
- Run-id loading is path-safe and rejects mismatched JSON record IDs.
- The current evidence-backed hardening receipt lives under `docs/audits/`.

## Files likely to touch next

- `src/cli.kujo` for command semantics and UX.
- `src/storage.kujo` for persistence guarantees.
- `tests/cli_integration.sh` for CLI behavior coverage.
- `README.md` for operator-facing behavior.
- `docs/audits/repository-hardening.md` for the latest verified audit state.

## Known constraints

- Tool depends on Kujo language runtime, not Python Kujo.
- Cost and token data remain manual by design.
- `commands` and `tests` fields in run records are still reserved and not
  populated by current CLI commands.
- Interrupted writers can leave an owned sidecar lock; follow the deliberate
  stale-lock recovery procedure documented in the README.
