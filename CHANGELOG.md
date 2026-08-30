# Changelog

All notable changes to RunLedger are documented here.

## [Unreleased]

- Serialize receipt mutations with per-record ownership locks so concurrent CLI updates cannot silently overwrite one another.
- Retry run-ID allocation when concurrent `start` commands select the same candidate.
- Bound lock waits and report an actionable stale-lock recovery path through `RUNLEDGER_LOCK_TIMEOUT_MS`.
- Use the Kujo runtime's collision-resistant, durable atomic-write primitive for receipts and reports.
- Return a concise operational error when a report output cannot be written instead of surfacing an unhandled runtime failure.
- Convert run-file read and parse failures into the documented corrupt/unreadable record errors.
- Reject command-specific unknown flags instead of silently ignoring typos.
- Reject surplus positional arguments instead of silently discarding them.
- Reject ambiguous flag syntax, including duplicate flags and values attached to boolean flags.
- Honor `--` as an end-of-options marker so note and follow-up text may begin with dashes.
- Reject missing or blank values for optional value flags such as `--prompt`, `--task`, `--repo`, and `--output`.
- Reject whitespace-only notes and follow-ups.
- Reject empty `usage` and `cost` updates that would otherwise report success without changing data.
- Prevent a terminal run from being finalized again and having its receipt rewritten.
- Normalize invalid stored token, cost, currency, and changed-file value types instead of crashing render commands.
- Report cost totals separately by currency rather than adding unlike currencies together.

## [1.0.0] - 2026-08-08

- Declared local run receipts, manual usage/cost capture, read-only git metadata, comparison, and report contracts stable.
- Aligned the VERSION file, Kujo metadata, CLI output, and integration contract at 1.0.0.

## [0.1.0] - 2026-06-27

- Prepared RunLedger for public release with local agent-run receipts, read-only git metadata capture, comparison/report output, and CLI integration coverage.
