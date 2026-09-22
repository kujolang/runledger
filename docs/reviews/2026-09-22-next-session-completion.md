# RunLedger next-session work — implementation and verification

This follows [the prioritized review](2026-09-22-readiness.md). The target is
the local, single-operator POSIX CLI, not an unverified multi-tenant service.

| Review item | Result and evidence |
| --- | --- |
| P1: trust/deployment | `docs/SECURITY_MODEL.md` defines the operator-owned ledger, privacy, threat assumptions, backup/recovery, and non-goals. `bin/runledger` uses `umask 077` for new POSIX artifacts; integration starts under `umask 000` and checks permissions. Existing files and direct Kujo invocation remain operator responsibilities. |
| P1: Git filenames | `src/gitmeta.kujo` reads `-z` Git output without trimming paths. Module tests round-trip newlines, tabs, quotes, Unicode, leading/trailing spaces, rename targets, and deleted paths across untracked, staged, and committed views. |
| P2: scaling | Removed a shell subprocess for every receipt read and preallocated large result/report row arrays. `--limit` and `--offset` read bounded pages from sorted filenames without parsing earlier receipts. Paired baseline and last-page benchmarks at 100, 1,000, and 10,000 receipts are recorded below. |
| P2: malformed receipts | `runledger verify [--json]` reports every invalid file; `--strict` on list/compare/report fails instead of returning incomplete data. Default skip-invalid behavior remains compatible. Integration covers malformed JSON, invalid shape, unreadable paths, and a ledger root that is a file. |
| P2: Markdown | Table cells, headings, notes, follow-ups, costs, and manual test descriptions escape Markdown/HTML controls. Module and CLI tests cover links, remote images, multiline heading injection, and HTML. Raw JSON retains the original text. |
| P2: commands/tests | `runledger command` and `runledger test` record bounded manual evidence under receipt locks, never execute user text, and surface it in show/JSON/report. Integration covers validation, round-trip, and no-execution behavior. The run verdict remains a human decision. |
| P3: failures/portability | Integration covers permission-denied output, unreadable runs directory, invalid ledger root, SHA-256 commits, explicit finish repository override, and stale locks. Disk-full injection was not available on this host; storage write failures are caught at the atomic-write boundary. Native Windows is not a declared target: Bash and POSIX filesystem semantics are documented explicitly. |

## Measured scaling

The benchmark uses one Kujo runtime, identical generated JSON fixtures, two
measured samples per small size after one warmup, alternating revision order,
and discards stdout so terminal rendering is not charged to either version.
The baseline is `3cee875`; the current code is the implementation after that
commit. Medians below are seconds (lower is faster):

| Receipts | Command | Baseline | Current |
| ---: | --- | ---: | ---: |
| 100 | `list --json` | 3.151 | 0.636 |
| 100 | `report` | 3.794 | 1.454 |
| 1,000 | `list --json` | 35.600 | 5.918 |
| 1,000 | `report` | 59.632 | 24.747 |

The 10,000-receipt runs had a 120-second bound per command. Baseline full
list/report both timed out; the current full list finished in 61.46–61.79
seconds, while the full report still timed out. Grouped-section rendering
improved the 1,000-receipt full report from 47.258 to 16.275 seconds in a
separate one-sample revision comparison, but that sample is too small to claim
a stable latency ratio. A 100-record **last page of a 10,000-record ledger**
completed in 0.711 seconds for `list --json` and 1.468 seconds for `report`;
page creation includes enumeration/sorting of all filenames but reads only
the selected files. Use pages for this scale; full 10,000-run Markdown report
remains expensive, and timeouts are censored observations, not throughput.
The workload used deterministic synthetic receipts, not production telemetry.

Raw results are in `evaluation/results/readiness-scale-small.json`,
`evaluation/results/readiness-scale-large.json`,
`evaluation/results/readiness-scale-large-optimized.json`,
`evaluation/results/readiness-render-optimized.json`, and
`evaluation/results/readiness-scale-page.json`.

## Formal security scan availability

The Codex Security plugin still cannot start its scan on this host. After the
earlier missing-`tomllib`/`tomli` failure, a retry reached a Python 3.9 runtime
error in its own `workbench_scan_history.py` (`type | None` is unsupported).
This is outside the RunLedger repository; the scanner needs Python 3.10+ in
its MCP launch environment. Source review and targeted security regression
tests are recorded above, but this document does not claim a formal scan or
enterprise certification.
