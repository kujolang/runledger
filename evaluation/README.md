# RunLedger hardening evaluation

This package compares the released `v1.0.0` baseline (`5cf186c`) with released
`v1.1.0` (`ca60031`) using identical deterministic workloads. It records raw
numeric samples and statistical summaries in `results/evaluation-results.json`, then
uses Kujo Eval to score both revisions against the same capability contract.

## Reproduce

Create detached worktrees at the two immutable revisions:

```bash
git worktree add --detach /tmp/runledger-eval-baseline 5cf186c
git worktree add --detach /tmp/runledger-eval-current ca60031
```

Run the benchmark from the repository root:

```bash
python3 evaluation/benchmark.py \
  --baseline /tmp/runledger-eval-baseline \
  --current /tmp/runledger-eval-current \
  --kujo "$(command -v kujo)" \
  --warmups 3 \
  --runs 12 \
  --stress-runs 10 \
  --writers 20 \
  --output evaluation/results/evaluation-results.json \
  --eval-input-dir evaluation/results/eval-input
```

Run the deterministic Eval scorecards through the isolated runner. It copies
the sibling Eval checkout to a temporary workspace so Eval's module and path
policies remain isolated from RunLedger:

```bash
KUJO="$(command -v kujo)" ./evaluation/run-eval.sh
```

Generated Eval runner output under `evaluation/eval-output/` is intentionally
ignored. The committed JSON inputs, results, reports, and suite definitions are
the audit package.

## Controls and interpretation

- Baseline always runs before current, so thermal or load drift is a known
  limitation rather than silently randomized away.
- Each latency workload has three warmups and twelve measured samples. Stress
  behavior uses ten independent trials with twenty writers per trial.
- Scaling fixtures contain 1, 25, and 100 complete receipts. One hundred is a
  deliberately large local RunLedger workload; the stress suite separately
  measures twenty simultaneous writers.
- Both revisions use the same Kujo binary, environment, valid record fixtures,
  Git fixture, workload sizes, and commands.
- Native test suites are run three times for reliability, but their timings are
  not compared because the test workloads differ between revisions.
- RunLedger does not call a model or build agent context. Token and model-cost
  changes therefore cannot be measured or claimed by this evaluation.
- RunLedger is interpreted by the shared Kujo runtime and creates no local
  binary. `kujo check` time and source bytes are the applicable build proxies.
