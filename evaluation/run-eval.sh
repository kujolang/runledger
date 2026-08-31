#!/usr/bin/env bash
set -euo pipefail

RUNLEDGER_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL_REPO="${KUJO_EVAL_REPO:-$RUNLEDGER_REPO/../eval}"
KUJO_BIN="${KUJO:-kujo}"
EVAL_WORKSPACE="$(mktemp -d /tmp/runledger-eval-runner.XXXXXX)"

cleanup() {
  find "$EVAL_WORKSPACE" -type f -delete
  find "$EVAL_WORKSPACE" -depth -type d -empty -delete
}
trap cleanup EXIT

cp -R "$EVAL_REPO/." "$EVAL_WORKSPACE/"
mkdir -p "$EVAL_WORKSPACE/evaluation/results/eval-input"
cp "$RUNLEDGER_REPO/evaluation/results/eval-input/baseline.json" "$EVAL_WORKSPACE/evaluation/results/eval-input/baseline.json"
cp "$RUNLEDGER_REPO/evaluation/results/eval-input/current.json" "$EVAL_WORKSPACE/evaluation/results/eval-input/current.json"

cd "$EVAL_WORKSPACE"
"$KUJO_BIN" run main.kujo lint "$RUNLEDGER_REPO/evaluation/eval-baseline.json"
"$KUJO_BIN" run main.kujo lint "$RUNLEDGER_REPO/evaluation/eval-current.json"
set +e
"$KUJO_BIN" run main.kujo run "$RUNLEDGER_REPO/evaluation/eval-baseline.json" \
  --output-dir "$RUNLEDGER_REPO/evaluation/eval-output/baseline" --json
baseline_exit=$?
"$KUJO_BIN" run main.kujo run "$RUNLEDGER_REPO/evaluation/eval-current.json" \
  --output-dir "$RUNLEDGER_REPO/evaluation/eval-output/current" --json
current_exit=$?
set -e

if [[ "$baseline_exit" -ne 1 ]]; then
  echo "expected baseline Eval to expose missing hardening capabilities" >&2
  exit 1
fi
if [[ "$current_exit" -ne 0 ]]; then
  echo "current Eval did not pass" >&2
  exit 1
fi

mkdir -p "$RUNLEDGER_REPO/evaluation/results/eval"
cp "$RUNLEDGER_REPO/evaluation/eval-output/baseline/summary.json" \
  "$RUNLEDGER_REPO/evaluation/results/eval/baseline-summary.json"
cp "$RUNLEDGER_REPO/evaluation/eval-output/current/summary.json" \
  "$RUNLEDGER_REPO/evaluation/results/eval/current-summary.json"

results_file="$RUNLEDGER_REPO/evaluation/results/evaluation-results.json"
results_tmp="$RUNLEDGER_REPO/evaluation/results/evaluation-results.json.tmp"
jq -s '.[0] + {kujo_eval: {baseline: .[1], current: .[2]}}' \
  "$results_file" \
  "$RUNLEDGER_REPO/evaluation/results/eval/baseline-summary.json" \
  "$RUNLEDGER_REPO/evaluation/results/eval/current-summary.json" \
  > "$results_tmp"
mv "$results_tmp" "$results_file"
