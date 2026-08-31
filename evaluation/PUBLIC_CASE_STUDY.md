# Hardening RunLedger: reliability first, with measured costs

RunLedger stores local JSON receipts for AI-agent runs. Between v1.0.0 and
v1.1.0, its storage and CLI paths were hardened against malformed commands,
corrupt records, concurrent creation, and lost read-modify-write updates.

This case study compares released tag `v1.0.0` (`5cf186c`) with released tag
`v1.1.0` (`ca60031`). Both revisions ran identical fixtures with the same Kujo
1.0.0 runtime. Latency workloads used three warmups and twelve measurements;
concurrency workloads used ten trials with twenty writers. Revision order was
paired and alternated to reduce shared-host drift.

## What changed

- New receipts use Kujo's durable atomic no-overwrite write.
- Concurrent ID collisions retry instead of overwriting or failing silently.
- Receipt mutations hold a token-owned lock across load, update, and save.
- Invalid flags, duplicate/ambiguous input, empty updates, and terminal rewrites
  fail with explicit exit codes.
- File/JSON failures become normal CLI errors.
- Invalid stored values are normalized, and costs remain separated by currency.

## Before versus after

| Result | v1.0.0 | v1.1.0 |
| --- | ---: | ---: |
| Kujo Eval capability score | 5/10 | 10/10 |
| 20 concurrent starts, fully preserved | 0/10 trials; 2.4/20 average | 10/10 trials; 20/20 |
| 20 same-record notes, fully preserved | 0/10 trials; 5.9/20 average | 10/10 trials; 20/20 |
| Terminal receipt preserved | 0% | 100% |
| Unknown flag | silently accepted, exit 0 | rejected, exit 2 |
| Typical lifecycle median | 1,102.5 ms | 1,287.6 ms |
| Typical lifecycle p95 | 1,381.2 ms | 1,466.9 ms |
| 100-record list median | 2,816.4 ms | 2,880.1 ms |
| 100-record report median | 4,340.0 ms | 4,721.2 ms |
| 100-record report peak RSS | 21.82 MB | 23.81 MB |
| Implementation LOC | 1,847 | 2,212 |
| Lint warnings | 13 | 0 |
| Dependencies | 0 | 0 |

## The biggest improvement

The baseline often reported successful note commands while discarding updates.
Across 200 simultaneous note attempts, it retained 59. Current retained all
200, produced valid JSON in every trial, and left no locks behind.

Concurrent starts show the same pattern: baseline retained 24 of 200 attempted
receipts; current retained 200 of 200.

That change comes from moving the ownership boundary around the complete
read-modify-write transaction, then using an atomic durable save. Atomic file
replacement by itself was not enough.

## What did not improve

v1.1.0 is not generally faster or smaller. A normal six-command lifecycle is
185.2 ms slower at the median (+16.8%); its p95 is also 85.7 ms slower, though
variance is lower. Same-record writers take longer because they now wait
their turn instead of losing work. Peak memory for a 100-record report is 1.18
MB higher. Implementation source grew 19.8% by LOC.

Read-only list/report changes are within observed variance. The 100-record JSON
output is byte-for-byte the same size; report output grows four bytes because
currency is explicit. RunLedger has no model invocation or agent-context path,
so this work makes no token- or model-cost claim.

## What surprised us

Correctness and latency moved in different directions. Current is slower at the
median and p95 for a typical lifecycle, although its standard deviation
improves. The lock path imposes steady overhead while removing both lost work
and some variability. That is a useful tradeoff for an evidence ledger, but it
would be misleading to call it a pure performance win.

## What remains

The next justified measurements are allocation profiling for report RSS and
mutation-path profiling for serial lock/write overhead. Larger ledgers should
be tested on an idle dedicated host before adding pagination or indexes. Any
optimization must preserve the 20/20 concurrency result.

## Reproduce the results

The repository includes the benchmark harness, Kujo Eval suites, raw structured
results, and exact commands under `evaluation/`. Start with
`evaluation/README.md`.

The empirical answer is **PARTIALLY**: v1.1.0 is demonstrably a more reliable
and deterministic receipt system, but it is not faster, smaller, or more
memory-efficient across every measured workload.
