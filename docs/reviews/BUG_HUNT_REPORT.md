# Bug Hunt Report

Date/time (UTC): 2026-05-31T13:17:53Z

## Project Structure Summary

- Entrypoint: `runledger.kujo`
- Launcher: `bin/runledger`
- CLI and command dispatch: `src/cli.kujo`
- Persistence: `src/storage.kujo`
- Record schema/defaults: `src/record.kujo`
- Git metadata (read-only): `src/gitmeta.kujo`
- Rendering/report output: `src/render.kujo`
- Shared helpers: `src/util.kujo`
- Test harness: `tests/runledger_test.kujo`
- CLI integration tests: `tests/cli_integration.sh`
- Combined test runner: `tests/run.sh`

## Commands Discovered

- Runtime verification: `KUJO=kujo ./bin/runledger help`
- Module test harness: `KUJO=kujo /path/to/kujo run tests/runledger_test.kujo`
- Full project tests: `KUJO=kujo ./tests/run.sh`

## Initial Risk Areas

- CLI flag parsing (`parse_args`) for missing or malformed flag values.
- Exit-code contract consistency (`1` operational vs `2` usage).
- Required argument handling for commands requiring `<run-id>`.
- Gaps between module-level test coverage and CLI boundary behavior.

## Testing/Verification Commands Available

- `KUJO=kujo ./tests/run.sh`
- Direct CLI probes through `./bin/runledger ...` with controlled temp ledgers.

## Limitations / Assumptions

- System `kujo` on PATH is Python Kujo (no `run` subcommand); verification uses Kujo runtime binary at `kujo`.
- Existing unrelated working-tree changes were preserved and not reverted.

## Bug: Missing Flag Value Can Be Misparsed As Another Flag

Status: Fixed  
Severity: High  
Area: `src/cli.kujo` (`parse_args`, `cmd_start`)  
Type: Logic

### Evidence

- Reproduction command before fix:
  - `runledger start --model --provider openai --task T --provider other --ledger <dir>`
- Observed behavior before fix:
  - Command succeeded and created a run where `model` became `--provider`.
  - This showed that parser consumed the next flag token as a value.

### Impact

- Required fields can be silently corrupted.
- Commands may succeed with semantically invalid input, producing incorrect records.

### Root Cause

- `parse_args` consumed any next token as a value for non-boolean flags, even when that token started with `--`.
- `cmd_start` only checked required fields for `null`, not empty string values.

### Fix Plan

- In `parse_args`, only consume the next token as a flag value when it exists and does not start with `--`.
- In `cmd_start`, treat empty required values as usage errors.

### Verification

- Added CLI integration regression:
  - `expect_exit 2 ... runledger start --provider openai --model --task "missing model value" ...`
- Re-ran full test suite with Kujo runtime.

### Result

Fixed.

## Bug: Missing `<run-id>` Returned Operational Exit Code Instead Of Usage Exit Code

Status: Fixed  
Severity: Medium  
Area: `src/cli.kujo` (`finish`, `show`, `note`, `followup`, `usage`, `cost`)  
Type: DX

### Evidence

- Reproduction commands before fix:
  - `runledger show --ledger <dir>` returned exit `1` with `error: show requires a <run-id>`.
  - `runledger finish --status pass --verdict ok --ledger <dir>` returned exit `1` with `error: finish requires a <run-id>`.
- This conflicted with documented exit-code policy where missing arguments are usage errors (`2`).

### Impact

- Inconsistent automation behavior for callers relying on stable exit code semantics.
- User-facing behavior contradicted project documentation.

### Root Cause

- Commands delegated missing-id handling to `require_record`, which returned `null` and led callers to return `1`.

### Fix Plan

- Add explicit missing-id usage checks in each affected command before calling `require_record`.
- Return exit code `2` and print command-specific usage messages.

### Verification

- Added CLI integration regressions:
  - `expect_exit 2 ... runledger show --ledger ...`
  - `expect_exit 2 ... runledger finish --status pass --verdict "missing id" --ledger ...`
- Re-ran full test suite with Kujo runtime.

### Result

Fixed.

## Re-Review Pass

- Re-read changed CLI logic for parser and command guards.
- Confirmed no broad architectural changes were introduced.
- Confirmed public command surface and storage format remain unchanged.

## Verification Log (Post-Fix)

- `KUJO=kujo ./tests/run.sh` -> pass
  - `RunLedger tests: 46 passed, 0 failed`
  - `CLI integration: ok`

## Remaining Risks / Open Items

- No additional reproducible bugs found in this pass.
- Remaining risk is primarily future regression at the CLI parsing boundary; integration tests were expanded to mitigate this.
