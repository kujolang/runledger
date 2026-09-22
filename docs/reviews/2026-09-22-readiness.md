# RunLedger readiness review — 2026-09-22

## Decision and scope

RunLedger is useful today as a local, single-operator receipt CLI. It is **not
certified enterprise-grade or universally useful**: it does not enforce users,
tenants, retention, access control, or provider-independent automatic capture.
Those would be separate product commitments, not properties implied by passing
the current test suite. Reviewed the CLI, parser, persistence, Git metadata,
schema, rendering, launcher, tests, README, previous hardening audit, and the
committed evaluation. This is a source review, not an independent formal
security certification.

## Completed in this pass

| Area | Evidence and result |
| --- | --- |
| Git accuracy | Previously `src/gitmeta.kujo` only listed working-tree files at finish; a run that committed its work appeared to change zero files. The finish path now unions the start-to-end commit diff with staged, unstaged, and untracked files. Added a clean-commit CLI regression. |
| Root layout | `cli.kujo` was an implementation parser imported from the repository root. Moved it into `src/args.kujo`; the root `runledger.kujo` must remain as the public interpreter entrypoint. `kujo.toml`, `VERSION`, README, license, contributor docs, and changelog are project metadata, not misplaced implementation. The historical benchmark supports both parser layouts. |
| Input handling | Run IDs now accept only printable portable filename characters; invalid IDs cannot echo control characters in storage diagnostics. |
| Test isolation | The module harness now allocates a unique temporary workspace instead of recursively removing a predictable shared temp path. |

## Next-session work, ordered by evidence and impact

| Priority | Work item | Evidence / acceptance criteria |
| --- | --- | --- |
| P1 | Define the intended deployment/trust model before claiming enterprise readiness. | `src/storage.kujo` accepts caller-specified ledger paths and local JSON files without identity/ACL management; decide supported single-user vs shared use, operator backups, permissions, and threat assumptions. Document and test chosen guarantees. Do not imply multi-tenant protection from file locks. |
| P1 | Make Git filename capture unambiguous. | `src/gitmeta.kujo` splits `git diff --name-only` and `git ls-files` on newlines; Git may quote special pathnames. Exercise tabs, unicode, quotes, and embedded newline filenames with round-trip tests; adopt a safe machine-readable delimiter/decoder supported by Kujo. Verify renamed and deleted paths. |
| P2 | Benchmark and improve large-ledger reads and reports. | The prior committed [evaluation](../../evaluation/HARDENING_EVALUATION.md) found a 100-record report median of 4,721.2 ms vs 4,340.0 ms baseline and roughly 9% higher peak RSS. Re-run controlled current-vs-prior benchmarks at 100, 1,000, and 10,000 runs; profile listing, JSON parsing, repeated string concatenation, and read-amplification. Introduce streaming/pagination only if measurements justify a compatible interface. |
| P2 | Clarify malformed-receipt handling for automation. | `src/storage.kujo` intentionally skips invalid JSON in `list_records`, so `list --json`, `compare`, and `report` can silently omit runs. Define a warning/strict mode or a validation command, preserve existing default output, and test corrupt/missing/invalid-type records. |
| P2 | Make report prose safe for untrusted free text. | `src/render.kujo` escapes table cells, but follow-up and note prose is rendered outside tables. Inspect Markdown control characters, embedded links/images, and multiline values in every output context; add end-to-end tests for safe, legible reports without losing source text in JSON. |
| P2 | Decide whether to populate reserved `commands` and `tests` fields. | `src/record.kujo` initializes both, but no CLI writes them. Specify bounded command/result schema and manual capture UX (avoid shell execution), update examples and reports, and test compatibility with older receipts. |
| P3 | Test bounded failure and portability paths. | Cover unreadable ledger directories, disk-full/permission failures, alternate Git hash format, start/end from different repositories, interrupted locks, and Windows compatibility if that platform is a target. Existing tests mainly exercise success and a few file errors on macOS. |

## Verification and limits

Baseline on the starting checkout: 68 module assertions and CLI integration
passed. After the implementation commit `9c15a68`, `KUJO=/Users/robertdevore/.local/bin/kujo ./tests/run.sh`
passed 70 module assertions plus CLI integration (including clean committed
work, concurrent starts and notes, and corrupt-record cases). Kujo `check` and
`lint` passed for the entrypoint, all seven `src/*.kujo` modules, and the
module test. Shell syntax, the Python benchmark parser, `git diff --check`,
and the repository artifact guard also passed. This does not constitute a
new performance benchmark; the prior timing measurements are cited above.
The Codex Security formal scan could not be started because the plugin's Python
environment failed to import `tomllib` or `tomli`; no formal scan report or
security clearance is claimed. This infrastructure issue is outside the
RunLedger repository and should be repaired before a formal follow-up scan.

The previous [hardening audit](../audits/repository-hardening.md) describes
the 1.1.0 state. Its "no remaining work" conclusion was scoped to that pass;
it does not supersede the newly identified work here.
