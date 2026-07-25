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

## Canonical examples and search hygiene

- Canonical copyable examples: `README.md` and `examples/build-tool-x.md`.
- Generated-output example: `examples/RUNLEDGER_REPORT.example.md`; use it for
  report shape, not as a source-code style guide.
- Historical and follow-up review artifacts live under `docs/reviews/`.
- Exclude generated/bulk paths from broad sweeps unless the task targets them:
  `.runledger/`, temp ledgers, and generated report outputs.

## Kujo readability style

- Prefer small local helpers for repeated output structure:
  `print_lines(...)` in CLI code and `push_lines(...)` while building rendered
  text arrays.
- Keep first-run examples direct; add helpers only when repeated lines or
  table-driven field updates are easier to scan than the expanded form.
- Preserve exact CLI and report output unless you intentionally update the
  integration expectations and generated report examples after inspection.

## Runtime requirement

RunLedger needs the Kujo language runtime (`kujo --help` should list `run`).
Python Kujo (linter) is not compatible.

Set runtime explicitly if needed:

```bash
export KUJO=kujo
```

## Verification

```bash
KUJO=kujo ./tests/run.sh
KUJO=kujo ./bin/runledger help
```
