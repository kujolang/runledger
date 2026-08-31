# RunLedger v1.0.0 → v1.1.0 hardening evaluation

Evaluation date: 2026-08-30/31  
Baseline: `5cf186c9b56b540970f75e33a06f50d3dac833a8` (`v1.0.0`)  
Current: `ca60031f8b3e5349efe9637a908fc1fde79a7764` (`v1.1.0`)

## Executive summary

**Verdict: PARTIALLY — with a strong reliability win and explicit performance
tradeoffs.** The empirical evidence independently shows that v1.1.0 is better
engineered for correctness, failure containment, and concurrent use. It does
not show a general speed, memory, size, token, or context-efficiency win.

The release-to-release hardening replaced unsafe receipt creation and
read-modify-write behavior with durable atomic writes, collision retries, and
token-owned per-record locks. It also made malformed CLI input deterministic,
prevented terminal receipts from being rewritten, normalized invalid stored
values, kept cost totals separated by currency, and converted parser/write
failures into normal CLI errors. These are observable behavior changes, not
claims inferred only from the diff.

The largest result is concurrency correctness. Across ten independent trials
of twenty simultaneous writers, the baseline preserved all concurrent starts
in **0/10 trials** and averaged **2.4/20 receipts**. Current preserved **20/20
receipts in 10/10 trials**. For same-receipt notes, baseline preserved every
update in **0/10 trials** and averaged **5.9/20 notes**; current preserved
**20/20 in 10/10 trials**, with valid JSON and no residual locks every time.
The Kujo Eval capability score consequently moved from **5/10 (50%)** to
**10/10 (100%)** under identical criteria.

That safety is not free. The twenty-writer start workload took a median
**496.6 ms → 2,310.6 ms**, and the note workload took **445.1 ms → 4,194.2
ms**. Comparing those times as pure regressions would be misleading because
the baseline finished quickly by failing or discarding most work. Current's
completed-start throughput was about **8.66 preserved receipts/s**, versus
**4.83 preserved receipts/s** for baseline; current note throughput was about
**4.77 preserved notes/s**, versus **13.26 partially preserved notes/s** for
baseline. The operational tradeoff is deliberate serialization in exchange
for complete data.

Serial workloads show smaller but real costs. Startup moved **79.3 ms → 83.4
ms** (+4.1 ms, +5.2%), which is operationally neutral. A six-command typical
lifecycle moved **1,102.5 ms → 1,287.6 ms** (+185.2 ms, +16.8%) at the median.
Its p95 also rose **1,381.2 ms → 1,466.9 ms**, while standard deviation fell
**123.6 ms → 97.7 ms**. Current is slower but somewhat less variable. A
100-receipt report's peak RSS moved **21,815,296 bytes → 23,805,952 bytes**
(+1,990,656 bytes, +9.1%). These are regressions/tradeoffs,
not hidden as “hardening overhead.”

Read-only list scaling was neutral within noisy host conditions. At 100
receipts, `list --json` median latency moved **2,816.4 ms → 2,880.1 ms**
(+2.3%). Report rendering moved **4,340.0 ms → 4,721.2 ms** (+8.8%), with CPU
time moving in the same direction, so it is classified as a likely regression
rather than a speed improvement. Output size is essentially unchanged: the
100-receipt JSON list is **105,413 bytes** in both versions; the report grew
**26,771 → 26,775 bytes** because currency is now explicit.

No token reduction or model-cost saving is demonstrated. RunLedger does not
invoke an LLM, construct prompts, replay conversation context, or make network
calls. It only records token/cost values supplied by callers. Agent-facing
improvement comes from deterministic exit codes and actionable evidence, not
from fewer tokens or tool calls.

The codebase is more capable but not leaner. Implementation source grew
**53,293 → 66,248 bytes** (+24.3%) and **1,847 → 2,212 LOC** (+19.8%); direct
and transitive dependencies remain **0 → 0**. Lint diagnostics improved from
**13 warnings → 0**. The added complexity is visible rather than relocated:
locks, ownership, retries, validation, and normalization require more control
flow. The evidence supports accepting that cost for a local receipt system
whose core promise is durable evidence.

For users, v1.1.0 is meaningfully safer under automation and parallel agents.
For maintainers, the next performance work should target serialized mutation
overhead and per-record loading only if profiles under representative ledgers
justify it. It should not weaken the newly measured correctness guarantees.

## Before/after scorecard

All latency rows use 3 warmups and 12 measured samples unless noted. Negative
time change means faster. p99 equals p95 here because nearest-rank percentiles
with `n=12` both select the maximum; it is retained in raw JSON, not repeated
below.

| Metric | Baseline | Current | Change | Classification |
| --- | ---: | ---: | ---: | --- |
| Kujo Eval capability score | 5/10 (50%) | 10/10 (100%) | +5 checks | **Clear improvement** |
| 20 concurrent starts fully preserved (10 trials) | 0/10; mean 2.4/20 | 10/10; 20/20 | +17.6 records/trial | **Clear improvement** |
| 20 concurrent notes fully preserved (10 trials) | 0/10; mean 5.9/20 | 10/10; 20/20 | +14.1 notes/trial | **Clear improvement** |
| Terminal receipt preservation (12 trials) | 0% | 100% | +100 points | **Clear improvement** |
| Unknown flag contract | exit 0, silently ignored | exit 2, error + usage | corrected | **Clear improvement** |
| Corrupt JSON contract | VM exit 4 | CLI exit 1 | normalized | **Clear improvement** |
| Lint diagnostics | 13 warnings | 0 warnings | -13 | **Clear improvement** |
| Startup median / p95 | 79.3 / 88.6 ms | 83.4 / 89.3 ms | +5.2% / +0.8% | Neutral |
| Typical lifecycle median / p95 | 1,102.5 / 1,381.2 ms | 1,287.6 / 1,466.9 ms | +16.8% / +6.2% | **Regression/tradeoff** |
| Typical lifecycle stdev | 123.6 ms | 97.7 ms | -20.9% | Likely variability improvement |
| 100-record list median / p95 | 2,816.4 / 3,021.9 ms | 2,880.1 / 3,128.2 ms | +2.3% / +3.5% | Inconclusive |
| 100-record report median / p95 | 4,340.0 / 5,463.7 ms | 4,721.2 / 5,939.9 ms | +8.8% / +8.7% | Likely regression |
| 100-record report peak RSS median | 21,815,296 B | 23,805,952 B | +1,990,656 B (+9.1%) | **Regression** |
| Kujo check median (8 implementation files) | 267.4 ms | 267.0 ms | -0.5 ms (-0.2%) | Neutral |
| 100-record JSON output | 105,413 B | 105,413 B | 0 | Neutral |
| 100-record report output | 26,771 B | 26,775 B | +4 B | Neutral |
| Implementation source | 53,293 B / 1,847 LOC | 66,248 B / 2,212 LOC | +24.3% / +19.8% | Complexity increase |
| Test source | 20,709 B / 449 LOC | 26,592 B / 534 LOC | +28.4% / +18.9% | Coverage investment |
| Direct/transitive dependencies | 0 / 0 | 0 / 0 | none | Neutral |
| Repository-built binary | none | none | n/a | Not applicable |
| Input/output tokens | not applicable | not applicable | not measured | Not demonstrated |

## Evaluation boundary

### Current

- Branch evaluated: released `main` state in a detached clean worktree.
- Commit: `ca60031f8b3e5349efe9637a908fc1fde79a7764`.
- Commit timestamp: `2026-08-30T20:47:57-04:00`.
- Exact tag: `v1.1.0`.
- Worktree: clean.

### Baseline selection

The selected baseline is `5cf186c9b56b540970f75e33a06f50d3dac833a8`,
tagged `v1.0.0`, timestamped `2026-08-08T02:59:04-04:00`. It is the release
immediately before the hardening sequence. The next commit strengthens storage
contract tests; subsequent commits add validation, normalization, atomic
writes, explicit error handling, and concurrency control. This release boundary
does not cherry-pick a favorable intermediate state.

`12bbf2b3723325913eb75ececaba0ce3fdc68b87` is a reasonable narrower
alternative because the final persistence audit began there on August 30. It
was not selected because it already includes the earlier v1.1 CLI and stored
data hardening. Using it would answer only “did the last same-day audit help?”
rather than evaluate the complete hardening release.

## Benchmark methodology

### Host and controls

- macOS 26.3.1, Darwin 25.3.0, x86_64.
- Intel Core i7-9750H, 6 physical / 12 logical cores.
- 16 GiB RAM.
- Kujo 1.0.0 at `/Users/robertdevore/.local/bin/kujo`.
- Python 3.10.5 orchestrator; Rust/Cargo 1.96.0 recorded because Kujo is a Rust
  runtime, although RunLedger itself is interpreted.
- Same filesystem; 95% occupied during the run.
- `LC_ALL=C`, `LANG=C`, `TZ=UTC`; same Kujo binary and fixtures.
- No benchmark path makes network calls; model/provider settings are not
  applicable.
- Host load average began at 15.20/17.22/19.75 and ended at
  7.84/9.48/13.75. To mitigate drift, versions ran back-to-back and sample
  order reversed on every iteration. High host load remains a limitation; small
  latency differences are treated as inconclusive.

### Workloads

| Workload | Input | Purpose |
| --- | --- | --- |
| Minimal | `runledger version` | Startup/fixed overhead |
| Typical | start → note → usage → cost → finish → report against one stable Git fixture | Normal developer lifecycle, six subprocesses |
| Scaling | identical ledgers with 1, 25, and 100 complete receipts; `list --json` and `report` | Read/parse/render scaling and output size |
| Stress: starts | 20 simultaneous starts, 10 independent trials | ID collision and durable-create behavior |
| Stress: notes | 20 simultaneous notes to one receipt, 10 trials | Lost-update behavior and lock cleanup |
| Failure: malformed CLI | unknown flag, 12 runs | Rejection, exit code, output |
| Failure: corrupt receipt | invalid JSON, 12 runs | Failure containment and diagnostic quality |
| Failure: terminal rewrite | finish an already terminal receipt, 12 runs | State integrity |
| Build proxy | `kujo check` over the same eight implementation files | Validation cost without inventing a binary build |
| Reliability | each revision's native suite, three runs | Repeated pass/fail only; timings not compared |

Every latency workload used three warmups and twelve measurements. Results
report min, max, mean, median, standard deviation, p95, p99, and sample size in
`results/evaluation-results.json`. Percentiles use nearest rank. Median is the
headline statistic. No statistical significance test is claimed because the
host was shared and only aggregate—not paired-delta—samples were retained.

### Known limitations

- High shared-host load makes small timing differences inconclusive despite
  paired alternating execution.
- The largest ledger has 100 complete receipts. This is a large local ledger,
  but it does not establish behavior at thousands or millions of records.
- Peak RSS comes from macOS `/usr/bin/time -l`; steady-state memory and
  allocation counts were not measured.
- CPU time is measured, but disk operation counts and energy are not.
- Native suites differ by revision (54 module assertions at baseline, 63 at
  current), so their 9.06 s and 16.70 s medians are reliability evidence, not
  a build/performance comparison.
- No LLM exists in the execution path, so token/context/cost evaluation cannot
  be manufactured.

## Deep technical analysis

### CLI state-machine and argument hardening

`d1f3a26` changed the parser from a permissive flag collector into an error-
reporting parser. Command handlers now declare allowed flags and positional
limits; duplicate flags, boolean assignments, missing values, empty updates,
and terminal rewrites are rejected. The `--` separator preserves dash-prefixed
note text.

The previous behavior was problematic because malformed automation could exit
success without performing the intended operation, and a completed receipt
could be silently rewritten. This primarily affects correctness, agent
interpretability, and failure amplification rather than throughput.

Measured effects:

- Unknown flag: baseline exited 0 with a 58-byte “no runs” response; current
  exited 2 with an 88-byte error and usage contract.
- Terminal rewrite: baseline rewrote the receipt in 12/12 trials; current
  preserved it in 12/12 and reduced response size 88 → 48 bytes.
- Kujo Eval credits both current behaviors and rejects both baseline behaviors.

### Defensive normalization and truthful cost reporting

`ac19661` validates stored token/cost/file types and aggregates costs by
currency. Invalid scalar types no longer escape into rendering operations, and
USD/EUR totals are not mathematically combined. The renderer gained explicit
currency output and table helpers; `12bbf2b` consolidated repeated output
construction without changing the public report shape beyond intended currency
semantics.

Measured effects:

- Valid 1/25/100-record fixtures render successfully in both revisions.
- Report output grows only 4 bytes at 100 records because current includes the
  currency label; no output-volume reduction is demonstrated.
- The capability is covered by current tests, but mixed-currency semantic
  quality is observed/tested rather than reduced to a performance score.

### Durable atomic writes and contained failures

`56af3bf` replaced timestamp-derived temporary names with Kujo's UUID-backed,
synced atomic write primitive and no-overwrite creation. Report writes now
return an operational result. `d764ba9` places file reads and JSON parsing
inside explicit error boundaries.

The old implementation had check/write races and could surface runtime-level
parse errors. Current returns the documented CLI exit 1 and the exact corrupt
path. In the corrupt-record workload, baseline produced a 101-byte VM error on
stderr with exit 4; current produced a path-specific CLI error with exit 1.
The current diagnostic was 197 bytes in the benchmark because it retained the
long temporary evidence path. That is more output, but more useful evidence;
it is not claimed as context compression.

### Transactional record locks and collision retries

`cc37e50` is the dominant behavioral change. Mutations now acquire an atomic,
token-owned per-record sidecar, perform the complete load/mutate/save sequence,
verify ownership before release, and bound waiting. Concurrent starts retry ID
allocation after atomic no-overwrite conflicts.

The baseline's atomic replacement prevented torn files but did not protect the
read-modify-write transaction. Several writers could load the same old value
and each replace the file, leaving only one writer's update. The new ownership
boundary changes the semantics from “commands may report success while data is
lost” to “all writes serialize or a bounded, actionable conflict is returned.”

Measured effects over 200 attempted operations per revision/workload:

- Starts: baseline averaged 2.7 successful processes and 2.4 persisted
  receipts per trial. Current had 20 successful processes and 20 persisted
  receipts in every trial.
- Notes: baseline averaged 16.4 successful processes but only 5.9 persisted
  notes, directly demonstrating acknowledged-but-lost updates. Current had 20
  successful processes, 20 persisted notes, valid JSON, and zero residual locks
  in every trial.
- Cost: current median completion is 1.81 s slower for starts and 3.75 s slower
  for notes. Those are serialization costs. They buy complete work and cannot
  be compared as if baseline completed all twenty operations.

## Runtime and scaling analysis

The read paths appear approximately linear across the tested 1/25/100 range.
Fixed startup dominates a one-record ledger, while per-record filesystem and
parse work dominates larger ledgers.

| Operation | Records | Baseline median | Current median | Baseline throughput | Current throughput |
| --- | ---: | ---: | ---: | ---: | ---: |
| `list --json` | 1 | 108.8 ms | 110.0 ms | 9.19 records/s | 9.09 records/s |
| `list --json` | 25 | 820.3 ms | 907.6 ms | 30.48 records/s | 27.55 records/s |
| `list --json` | 100 | 2,816.4 ms | 2,880.1 ms | 35.51 records/s | 34.72 records/s |
| `report` | 1 | 125.8 ms | 132.9 ms | 7.95 records/s | 7.52 records/s |
| `report` | 25 | 1,220.5 ms | 1,269.8 ms | 20.48 records/s | 19.69 records/s |
| `report` | 100 | 4,340.0 ms | 4,721.2 ms | 23.04 records/s | 21.18 records/s |

The throughput increase with ledger size reflects amortized fixed startup, not
super-linear speedup. Neither revision changes the scaling curve materially.
No quadratic or runaway behavior was observed at 100 receipts, but larger
scales are not demonstrated.

## Token, context, output, and agent efficiency

- **Input/output/cached tokens:** not applicable and not measured.
- **Context size/messages:** not applicable; RunLedger has no active context.
- **Agent tool calls:** identical external command counts: one for individual
  workloads and six for the typical lifecycle.
- **Tool-result bytes:** valid JSON list output is identical. Reports differ by
  4 bytes at 100 records. Failure output sometimes grows because current
  retains actionable paths and usage text.
- **Retries:** current adds internal collision retries for concurrent starts;
  agents no longer need to infer or repair missing receipts. No agent-level
  retry loop was executed or claimed.
- **Task success:** current completes the deterministic capability contract at
  10/10; baseline completes 5/10.

There is no measured token or dollar saving to model at 1, 100, 1,000, or
10,000 executions. Any such calculation would invent a provider workload that
this repository does not own.

## Build, artifact, dependency, and complexity analysis

RunLedger is interpreted by the shared Kujo runtime, so clean/incremental/
release build time and repository binary size are not applicable. The closest
repeatable proxy, checking the same eight implementation files, moved from a
267.4 ms median to 267.0 ms (-0.2%); the 0.5 ms difference is operationally
neutral.

| Structural metric | Baseline | Current | Change |
| --- | ---: | ---: | ---: |
| Implementation files | 8 | 8 | 0 |
| Implementation LOC | 1,847 | 2,212 | +365 (+19.8%) |
| Implementation bytes | 53,293 | 66,248 | +12,955 (+24.3%) |
| Functions | 105 | 120 | +15 (+14.3%) |
| Branch-keyword proxy | 251 | 319 | +68 (+27.1%) |
| Test LOC | 449 | 534 | +85 (+18.9%) |
| Direct dependencies | 0 | 0 | 0 |
| Transitive dependencies | 0 | 0 | 0 |
| TODO/FIXME | 0 | 0 | 0 |
| Lint warnings | 13 | 0 | -13 |

Complexity was not removed overall. Some duplicated formatting code was
consolidated, but coordination, validation, and recovery logic added more than
that refactor removed. The increase is justified by independently measured
capabilities, but future maintainers should not describe v1.1.0 as a smaller or
less complex implementation.

## Reliability and failure behavior

Both revisions passed their native suite three out of three times. Baseline's
module harness reports 54 assertions; current reports 63. Current's longer
native-suite median (16.70 s versus 9.06 s) is not a regression metric because
the current suite runs additional concurrency and failure workloads.

Current improves determinism in two independent ways:

1. All stress trials converge on the intended persisted count with no leftover
   locks; baseline results vary and never reach full preservation.
2. Typical-lifecycle latency variation falls from 123.6 ms to 97.7 ms even as
   median latency rises.

The failure contracts also become domain-specific: usage failures exit 2,
operational/storage failures exit 1, and terminal state is immutable through
`finish`. Baseline either silently succeeds or leaks VM exit 4 in the tested
cases.

## Kujo Eval report

The two pure JSON suites apply the same ten boolean criteria to generated
evidence. Kujo Eval itself produced these scores:

| Capability | Baseline | Current |
| --- | :---: | :---: |
| Startup succeeds | pass | pass |
| Typical lifecycle succeeds | pass | pass |
| Large list succeeds | pass | pass |
| Large report succeeds | pass | pass |
| Concurrent starts preserve every receipt | fail | pass |
| Concurrent notes preserve every update | fail | pass |
| Unknown flags are rejected | fail | pass |
| Terminal records cannot be rewritten | fail | pass |
| Native tests pass repeatedly | pass | pass |
| Implementation lint is clean | fail | pass |
| **Total** | **5/10 (50%)** | **10/10 (100%)** |

This is a capability score, not a synthetic speed score. Runtime, memory, and
output measurements remain numeric and are not hidden inside subjective Eval
weights.

## Change-to-result and commit attribution

| Commit | Change | Intended effect | Observed effect |
| --- | --- | --- | --- |
| `5fd2c71` | Tighten storage test assertions | Make contracts explicit | Test-only; no runtime result attributed |
| `d1f3a26` | Parser errors, per-command validation, terminal-state guard | Reject ambiguous/no-op transitions | Unknown flag exit 0→2; terminal preservation 0%→100%; two Eval failures become passes |
| `ac19661` | Type normalization and per-currency totals | Avoid render crashes and invalid arithmetic | Valid fixtures remain successful; mixed-currency behavior covered; report +4 bytes at 100 records |
| `12bbf2b` | Table-driven output helpers | Reduce repeated rendering code | No measurable output reduction; no speed claim |
| `56af3bf` | Native durable atomic writes/no-overwrite and write result handling | Remove temp collision/clobber race | Contributes to 20/20 concurrent starts; adds synced-write overhead |
| `d764ba9` | Explicit read/parse error boundaries | Contain malformed receipt failures | VM exit 4 becomes CLI exit 1 with evidence path; lint warnings removed |
| `cc37e50` | Owned record locks and start collision retries | Prevent lost updates and failed starts | 2.4→20 receipts, 5.9→20 notes; 0%→100% full-preservation rate; slower complete stress latency |
| `9491188`, `eddf8e9` | Audit documentation | Preserve rationale/evidence | No runtime effect attributed |
| `ca60031` | Version/release metadata | Publish v1.1.0 | No runtime effect beyond version text |

### Root-cause examples

**Measured result:** concurrent notes improve from 5.9/20 average persisted to
20/20, with 100% full-preservation rate.

- Primary cause: `update_record` holds one owned lock across load, mutate, and
  atomic save.
- Files: `src/storage.kujo`, `src/cli.kujo`.
- Commit: `cc37e50`.
- Tradeoff: workload median 445.1 ms → 4,194.2 ms.
- Consequence: slower but trustworthy receipts; agents no longer receive false
  success for discarded evidence.

**Measured result:** current rejects unknown flags and protects terminal state.

- Primary cause: parser error collection, allowed-flag validation, positional
  limits, and a terminal-state check inside the locked updater.
- Files: `cli.kujo`, `src/cli.kujo`.
- Commit: `d1f3a26`, then integrated with `cc37e50`.
- Tradeoff: malformed calls produce 30 more bytes of useful usage output.
- Consequence: automation fails closed rather than silently doing the wrong
  thing.

**Measured result:** large-report peak RSS increases 9.1%.

- Likely causes: additional normalization structures and currency aggregation;
  locking is not active on read-only report paths.
- Evidence classification: measured regression, root cause inferred rather
  than allocation-profiled.
- Recommended action: profile allocations before changing code.

## Top engineering improvements

1. **Concurrent receipt creation became complete and deterministic.** Losing
   17.6 of 20 receipts on average is eliminated.
2. **Concurrent updates no longer acknowledge discarded evidence.** Current
   preserved all 200 notes across ten trials; baseline preserved 72.
3. **Terminal and malformed state now fail closed.** The most important CLI
   contract failures move from silent success/runtime escape to stable exit
   codes.
4. **Lint cleanliness improved from 13 diagnostics to zero** while adding
   explicit failure boundaries.
5. **Latency became more predictable in the typical lifecycle** despite a
   slower median.

## Regressions and tradeoffs

| Metric | Baseline | Current | Severity | Likely cause | Assessment / action |
| --- | ---: | ---: | --- | --- | --- |
| Typical lifecycle median | 1,102.5 ms | 1,287.6 ms | Moderate | lock create/release plus durable synced writes on four mutations | Accept for correctness; profile before optimizing |
| Concurrent note wall time | 445.1 ms | 4,194.2 ms | High raw latency, intentional | serialized same-record writers | Accept semantic tradeoff; consider safe batching only with preserved atomicity |
| Concurrent start wall time | 496.6 ms | 2,310.6 ms | Moderate raw latency, intentional | collision retries and durable no-overwrite writes | Accept; current completes 20/20 |
| 100-record report latency | 4,340.0 ms | 4,721.2 ms | Low/moderate | added normalization and currency-aware rendering | Profile before changing behavior |
| 100-record report peak RSS | 21.82 MB | 23.81 MB | Low | likely added normalization/render state | Profile; do not optimize from inference alone |
| Implementation LOC | 1,847 | 2,212 | Maintainability cost | explicit validation/coordination/recovery | Accept but guard with tests and small helpers |
| Corrupt-record output | 101 B | 197 B | Low | current retains exact evidence path | Accept; evidence quality improved |

No broad speed improvement is claimed. No functionality regression was found
in the tested valid workflows. The measurable regressions are overhead and
footprint, not loss of required behavior.

## Remaining opportunities

- **P0:** none.
- **P1:** profile the typical mutation lifecycle and same-record lock path to
  determine whether lock polling, synchronized writes, or repeated process
  startup dominates the 17.4% serial overhead. Preserve full-transaction
  ownership and durability.
- **P2:** profile report allocations to explain the 1.99 MB peak-RSS increase.
- **P2:** measure 250/1,000-record ledgers on an idle dedicated host before
  considering pagination, indexing, or batched loading. The current 100-record
  evidence is approximately linear but too slow to justify complacency.
- **P3:** retain the current 4-byte currency-explicit report increase; output
  compression would remove useful meaning for negligible benefit.

These are evaluation findings, not automatically authorized implementation
tasks.

## Reproduction and evidence

See `evaluation/README.md` for exact commands. The audit package contains:

- `evaluation/benchmark.py` — deterministic paired benchmark harness.
- `evaluation/eval-baseline.json` and `evaluation/eval-current.json` — equal
  Kujo Eval criteria.
- `evaluation/run-eval.sh` — isolated Eval runner.
- `evaluation/results/evaluation-results.json` — environment, statistical
  summaries, behavior measurements, and Eval scores.
- `evaluation/results/eval-input/*.json` — generated capability facts consumed
  by Eval.
- `evaluation/results/eval/*-summary.json` — raw Eval score summaries.

## Final question

> If we erase the commit messages and ignore what the hardening work intended
> to accomplish, does the empirical evidence independently demonstrate that
> CURRENT is a better engineered version than BASELINE?

**PARTIALLY.** Current is independently and decisively better at preserving
receipts, preserving concurrent updates, enforcing terminal state, rejecting
malformed calls, containing corrupt data, and passing the shared capability
contract. It is not independently better on every engineering axis: serial
mutation latency, same-record completion time, peak report memory, source size,
and control-flow complexity increased; list speed is neutral and report speed
likely regressed;
tokens and context are not applicable. The net engineering result is positive
because RunLedger's primary responsibility is trustworthy evidence, but the
benchmark does not support an unqualified “faster and leaner” conclusion.
