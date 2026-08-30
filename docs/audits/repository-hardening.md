# RunLedger Repository Hardening Audit

## Repository

- Repository: `runledger`
- Branch: `main`
- Starting SHA: `12bbf2b3723325913eb75ececaba0ce3fdc68b87`
- Implementation ending SHA: `d764ba9865bd2ee2850e02e111e82e3aac77c38c`
- Purpose: record local, inspectable JSON receipts for AI-agent runs and render human- or machine-readable comparisons and reports.
- Dependencies and integrations: Kujo runtime 1.0.0, the local filesystem, and read-only Git subprocesses. The package declares no third-party dependencies and makes no network calls.

The implementation ending SHA identifies the audited code state before this report-only commit.

## Baseline

The repository started clean on `main`. The baseline used Kujo 1.0.0 and passed all 59 module-level assertions plus the CLI integration suite. `./tests/run.sh` completed in 22.62 seconds of wall-clock time on the audit host. The public help output was captured as the CLI contract, and the implementation source/launcher footprint was 60,932 bytes.

The audit inspected the entrypoints, CLI parsing and dispatch, record schema, storage normalization and writes, read-only Git metadata collection, text/Markdown rendering, shell launcher, tests, examples, documentation, package metadata, ignore policy, and GitHub artifact guard. Generated `.runledger/` data and temporary test ledgers were excluded from broad source sweeps.

## Findings

| ID | Priority | Area | Finding | Evidence | Action | Status |
| -- | -------- | ---- | ------- | -------- | ------ | ------ |
| RL-HARD-001 | P1 | Persistence / concurrency | Temporary atomic-write names used millisecond time only, so same-target writes in one tick could collide. `save_new` also checked existence separately from replacement, leaving a receipt-clobber race. | Starting `src/storage.kujo` lines 89–96 and 136–146. | Replaced the custom temporary-file path with Kujo's UUID-backed, synced atomic primitive; new receipts use its atomic no-overwrite mode. | Fixed and tested |
| RL-HARD-002 | P1 | Error handling | `report --output` announced success after a write call whose failure was not converted into the documented operational-error contract. | Starting `src/cli.kujo` lines 667–670. | Return a concise `error:` message and exit 1 for output-write failures. | Fixed and tested |
| RL-HARD-003 | P2 | Error handling / state | Run-file reads and JSON parsing were fallible outside an explicit error boundary, including a check/read race. | Kujo lint warnings on starting `src/storage.kujo` lines 177–178. | Convert read and parse failures into existing unreadable/corrupt record errors. | Fixed and tested |
| RL-HARD-004 | P2 | Coordination | Read-modify-write commands can still lose one update when multiple processes mutate the same existing receipt concurrently. | Storage has atomic replacement but no per-record compare-and-swap or lock; README already identifies multi-writer coordination as the next robustness frontier. | Preserve current single-writer-compatible behavior; design an explicit lock/conflict contract before implementation. | Needs more evidence |

## Changes Implemented

### Durable, collision-resistant writes

- Problem: custom sibling temporary names were not unique enough, and new-run creation could overwrite a concurrently created receipt.
- Root cause: `now()` was the only temporary-name discriminator, while `save_new` used a non-atomic existence check followed by replacement.
- Implementation: `write_atomic_text` now delegates to Kujo's native atomic write, which creates a unique sibling, flushes and syncs it, and atomically promotes it. `save_new` uses no-overwrite finalization so a competing create becomes an error rather than data loss.
- Files: `src/storage.kujo`.
- Tests: existing duplicate-create coverage still passes; the full storage and CLI suites pass.
- Compatibility: record names, JSON shape, output text on success, and ledger layout are unchanged.

### Actionable write failures

- Problem: report output failures could surface as an unhandled runtime failure instead of a stable CLI receipt.
- Root cause: the CLI ignored the write helper's outcome.
- Implementation: the helper returns a structured result; `report` prints an actionable error and returns operational exit code 1.
- Files: `src/storage.kujo`, `src/cli.kujo`, `tests/cli_integration.sh`, `CHANGELOG.md`.
- Tests: integration coverage writes to a directory path and verifies exit 1 plus the concise error prefix.
- Compatibility: successful output and report contents are unchanged; failure behavior is now aligned with the documented exit-code contract.

### Defensive run-file loading

- Problem: filesystem or parser failures could escape the storage layer despite documented corrupt/unreadable semantics.
- Root cause: `read_file` and `parse_json` were outside explicit error handling.
- Implementation: both operations now map failure to the existing concise storage errors.
- Files: `src/storage.kujo`, `CHANGELOG.md`.
- Tests: malformed, partial, mismatched, invalidly typed, directory-backed, and unreadable run-file cases continue to pass. Kujo lint is clean.
- Compatibility: normalized record schema and valid-record behavior are unchanged.

## Performance & Efficiency

No runtime-speed claim is made. The full suite measured 22.62 seconds before and 24.10 seconds after on a single host run; that variance is not a meaningful benchmark and the change intentionally adds durable syncing at write boundaries. Public help output remains 1,572 bytes. The package still has zero declared third-party dependencies and no network surface.

Agent-context and token surfaces are limited to concise CLI receipts, stable JSON, the README, examples, and `AGENTS.md`; no model prompts, MCP schemas, provider payloads, or conversation replay exist in this repository. No token-specific change was justified.

## Security

Reviewed trust boundaries included CLI flags and positionals, run IDs, ledger/report paths, environment configuration, JSON records, Markdown table content, shell quoting for Git paths, subprocess selection, symlink/rename behavior, and local filesystem writes. Existing path-traversal rejection, shell quoting, Markdown pipe/newline escaping, non-negative numeric validation, JSON shape normalization, and read-only Git commands remain covered.

The persistence change closes a concurrent create/clobber boundary and uses the runtime's unique temporary files and durable atomic promotion. No credentials, network calls, unsafe deserialization, or dependency supply-chain surface exists. The remaining same-record multi-writer issue is a local data-integrity coordination concern, not a demonstrated privilege-boundary escape.

## Compatibility

- Public APIs changed: no.
- CLI success behavior changed: no.
- CLI failure behavior changed: report write failures now deterministically return exit 1 with a concise error.
- File formats or schemas changed: no.
- Configuration or environment variables changed: no.
- External consumers affected: consumers that incorrectly depended on an unhandled report-write failure may observe the documented operational exit code instead; valid workflows are unchanged.

## Cross-Repository Follow-Ups

None required.

## Remaining Work

- **P0:** none.
- **P1:** none.
- **P2:** define and test a backward-compatible per-record conflict/locking contract if concurrent writers become a supported use case.
- **P3:** none justified.
- **Needs more evidence:** establish realistic ledger-size and multi-process workloads before adding pagination, file-size limits, or lock machinery.
- **Not worth changing:** no cosmetic rewrite, dependency substitution, or output compaction was justified; current modules and concise receipts are appropriately small.

## Verification Receipt

All listed commands passed unless a baseline lint observation is explicitly noted.

```text
kujo --version
kujo --help
./bin/runledger version
./tests/run.sh
./bin/runledger help
/usr/bin/time -p ./tests/run.sh
kujo check cli.kujo
kujo check runledger.kujo
kujo check src/cli.kujo
kujo check src/gitmeta.kujo
kujo check src/record.kujo
kujo check src/render.kujo
kujo check src/storage.kujo
kujo check src/util.kujo
kujo check tests/runledger_test.kujo
kujo lint cli.kujo
kujo lint runledger.kujo
kujo lint src/cli.kujo
kujo lint src/gitmeta.kujo
kujo lint src/record.kujo
kujo lint src/render.kujo
kujo lint src/storage.kujo
kujo lint src/util.kujo
kujo lint tests/runledger_test.kujo
bash -n bin/runledger tests/run.sh tests/cli_integration.sh .github/scripts/check-kujo-tool-artifacts.sh
bash .github/scripts/check-kujo-tool-artifacts.sh 12bbf2b3723325913eb75ececaba0ce3fdc68b87 HEAD
git diff --check
```

Baseline lint reported two `missing-error-handling-pattern` warnings in `src/storage.kujo`; the completed implementation is lint-clean.
