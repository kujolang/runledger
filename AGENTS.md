# RunLedger Agent Notes

This repo is a small local CLI in Kujo for recording AI-agent run receipts.

## Fast orientation

- Entry point: `runledger.kujo`
- Launcher: `bin/runledger`
- Core modules:
  - `src/cli.kujo` command parsing, UX, exit codes
  - `src/storage.kujo` local JSON persistence
  - `src/gitmeta.kujo` read-only git metadata collection
  - `src/render.kujo` table/report rendering
  - `src/record.kujo` record schema defaults/status validation
- Tests:
  - `tests/runledger_test.kujo` module-level harness
  - `tests/cli_integration.sh` CLI integration checks
  - `tests/run.sh` runs both

## Runtime requirement

RunLedger needs the Kujo language runtime (`kujo --help` should list `run`).
Python Kujo (linter) is not compatible.

Set runtime explicitly if needed:

```bash
export KUJO=/path/to/kujo/target/release/kujo
```

## Verification

```bash
KUJO=/path/to/kujo ./tests/run.sh
KUJO=/path/to/kujo ./bin/runledger help
```
