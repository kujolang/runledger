#!/usr/bin/env bash
# CLI integration checks for RunLedger.
#
# Exercises the user-facing command surface through bin/runledger, including
# success paths and key failure/exit-code behavior.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUJO_BIN="${KUJO:-kujo}"
RUNLEDGER="$PROJECT_DIR/bin/runledger"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_exit() {
  local expected="$1"
  shift
  set +e
  "$@" >/tmp/runledger-cli-last.out 2>&1
  local actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    cat /tmp/runledger-cli-last.out >&2 || true
    fail "expected exit $expected, got $actual for: $*"
  fi
}

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/runledger-cli-test.XXXXXX")"
trap 'rm -rf "$TMPROOT" /tmp/runledger-cli-last.out' EXIT

LEDGER="$TMPROOT/ledger"
REPO="$TMPROOT/repo"
PLAIN="$TMPROOT/plain"
mkdir -p "$REPO" "$PLAIN"

HELP_OUT="$(KUJO="$KUJO_BIN" "$RUNLEDGER" help)"
EXPECTED_HELP="$(cat <<'EOF'
runledger 1.0.0 — a local ledger for AI-agent build runs

Usage: runledger <command> [arguments]

Commands:
  start      Begin a new run record
             usage: runledger start --model <m> --provider <p> --task <t> [--prompt <file>] [--repo <path>]
  finish     Finalize a run (status, verdict, end git state)
             usage: runledger finish <run-id> --status <pass|partial|fail|abandoned> --verdict "text"
  list       List recorded runs in a compact table
             usage: runledger list [--json]
  show       Show one run (add --json for the raw record)
             usage: runledger show <run-id> [--json]
  note       Add a timestamped note to a run
             usage: runledger note <run-id> "note text"
  followup   Add a follow-up item to a run
             usage: runledger followup <run-id> "follow-up text"
  usage      Record token usage for a run
             usage: runledger usage <run-id> [--input N] [--output N] [--cache-read N] [--cache-write N]
  cost       Record cost for a run
             usage: runledger cost <run-id> [--total N] [--currency CODE] [--input N] [--output N] [--cache N]
  compare    Compare runs in the ledger
             usage: runledger compare [--task <name>] [--json]
  report     Generate a markdown report (--output <file> to save)
             usage: runledger report [--task <name>] [--output <file>]
  help       Show this help
  version    Show version

Global:
  --ledger <dir>   Ledger location (default ./.runledger, or $RUNLEDGER_DIR)

Run scripts via: kujo run runledger.kujo -- <command> [arguments]
EOF
)"
[[ "$HELP_OUT" == "$EXPECTED_HELP" ]] || fail "help output changed unexpectedly"

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name runledger-test
printf "base\n" > "$REPO/base.txt"
git -C "$REPO" add base.txt
git -C "$REPO" commit -qm "init"

START_OUT="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model codex --task "CLI Test" --repo "$REPO" --ledger "$LEDGER")"
RID="$(printf '%s\n' "$START_OUT" | sed -n '1s/^Started run: //p')"
[[ -n "$RID" ]] || fail "did not parse run id from start output"

expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --verdict "missing status" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status pass --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status in_progress --verdict "bad terminal" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status pass --verdict "x" --notes --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" usage "$RID" --input notanint --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" cost "$RID" --total notafloat --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" cost "$RID" --currency --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" nope
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" show --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish --status pass --verdict "missing id" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model --task "missing model value" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model codex --task "missing repo value" --repo --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --ledger
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" report --output --ledger "$LEDGER"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" show "../escape" --ledger "$LEDGER"

NESTED_LEDGER="$TMPROOT/nested/ledger/path"
NESTED_START="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model local-agent --task "Nested Ledger" --repo "$PLAIN" --ledger "$NESTED_LEDGER")"
NESTED_RID="$(printf '%s\n' "$NESTED_START" | sed -n '1s/^Started run: //p')"
[[ -s "$NESTED_LEDGER/runs/$NESTED_RID.json" ]] || fail "nested ledger run file missing"

KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" "cli note" --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" followup "$RID" "cli followup" --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" usage "$RID" --input 10 --output 2 --cache-read 1 --cache-write 0 --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" cost "$RID" --total 0.5 --currency USD --ledger "$LEDGER"
printf "delta\n" >> "$REPO/base.txt"
KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status partial --verdict "ok" --ledger "$LEDGER"

SHOW_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$RID" --json --ledger "$LEDGER")"
[[ "$SHOW_JSON" == *'"verdict": "ok"'* ]] || fail "show --json missing verdict"
LIST_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" list --json --ledger "$LEDGER")"
[[ "$LIST_JSON" == *"\"$RID\""* ]] || fail "list --json missing run id"
COMPARE_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" compare --json --task "CLI Test" --ledger "$LEDGER")"
[[ "$COMPARE_JSON" == *"\"$RID\""* ]] || fail "compare --json missing run id"

REPORT="$TMPROOT/RUNLEDGER_REPORT.md"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --task "CLI Test" --output "$REPORT" --ledger "$LEDGER"
[[ -s "$REPORT" ]] || fail "report file missing or empty"
REPORT_NESTED="$TMPROOT/nested/out/RUNLEDGER_REPORT.md"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --task "CLI Test" --output "$REPORT_NESTED" --ledger "$LEDGER"
[[ -s "$REPORT_NESTED" ]] || fail "nested report file missing or empty"

START2="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model local-agent --task "No Git" --repo "$PLAIN" --ledger "$LEDGER")"
RID2="$(printf '%s\n' "$START2" | sed -n '1s/^Started run: //p')"
[[ -n "$RID2" ]] || fail "did not parse non-git run id"
KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID2" --status pass --verdict "nongit" --ledger "$LEDGER"

# Repo with no commits: changed_files should still include staged files.
NO_COMMIT_REPO="$TMPROOT/no-commit"
mkdir -p "$NO_COMMIT_REPO"
git -C "$NO_COMMIT_REPO" init -q
printf "staged\n" > "$NO_COMMIT_REPO/staged.txt"
git -C "$NO_COMMIT_REPO" add staged.txt
START3="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model local-agent --task "No Commit Repo" --repo "$NO_COMMIT_REPO" --ledger "$LEDGER")"
RID3="$(printf '%s\n' "$START3" | sed -n '1s/^Started run: //p')"
[[ -n "$RID3" ]] || fail "did not parse no-commit run id"
KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID3" --status pass --verdict "no-commit" --repo "$NO_COMMIT_REPO" --ledger "$LEDGER"
SHOW3_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$RID3" --json --ledger "$LEDGER")"
[[ "$SHOW3_JSON" == *'"changed_files": ['* ]] || fail "no-commit run missing changed_files"
[[ "$SHOW3_JSON" == *'"staged.txt"'* ]] || fail "no-commit staged file not detected"

# Non-object JSON run files should be ignored without crashing.
cat > "$LEDGER/runs/not-an-object.json" <<'JSON'
[]
JSON
KUJO="$KUJO_BIN" "$RUNLEDGER" list --ledger "$LEDGER" >/tmp/runledger-cli-list-shape.out 2>&1 || fail "list crashed on non-object json run file"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --ledger "$LEDGER" >/tmp/runledger-cli-report-shape.out 2>&1 || fail "report crashed on non-object json run file"

cat > "$LEDGER/runs/mismatched.json" <<'JSON'
{"id":"other-id","created_at":"2026-06-01T00:00:00Z","status":"pass"}
JSON
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" show mismatched --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" list --ledger "$LEDGER" >/tmp/runledger-cli-list-mismatched.out 2>&1 || fail "list crashed on mismatched run id"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --ledger "$LEDGER" >/tmp/runledger-cli-report-mismatched.out 2>&1 || fail "report crashed on mismatched run id"

# Partial JSON run files with missing keys should not crash show/list/report.
BROKEN_ID="broken-shape"
cat > "$LEDGER/runs/$BROKEN_ID.json" <<'JSON'
{"id":"broken-shape","created_at":"2026-06-01T00:00:00Z","status":"pass"}
JSON
KUJO="$KUJO_BIN" "$RUNLEDGER" show "$BROKEN_ID" --ledger "$LEDGER" >/tmp/runledger-cli-show-broken.out 2>&1 || fail "show crashed on partial JSON"
KUJO="$KUJO_BIN" "$RUNLEDGER" list --ledger "$LEDGER" >/tmp/runledger-cli-list-broken.out 2>&1 || fail "list crashed on partial JSON"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --ledger "$LEDGER" >/tmp/runledger-cli-report-broken.out 2>&1 || fail "report crashed on partial JSON"

# Null/invalid typed fields should also be tolerated.
NULLS_ID="null-fields"
cat > "$LEDGER/runs/$NULLS_ID.json" <<'JSON'
{"id":"null-fields","created_at":"2026-06-01T00:00:00Z","updated_at":"2026-06-01T00:00:00Z","status":"pass","provider":"p","model":"m","task_name":"t","prompt_file":null,"repo_path":".","changed_files":null,"commands":null,"tests":null,"usage":null,"cost":null,"followups":null,"notes":null}
JSON
KUJO="$KUJO_BIN" "$RUNLEDGER" show "$NULLS_ID" --ledger "$LEDGER" >/tmp/runledger-cli-show-nulls.out 2>&1 || fail "show crashed on null-typed fields"

# Unreadable run files should be skipped without crashing list/report.
UNREADABLE_ID="unreadable-entry"
cat > "$LEDGER/runs/$UNREADABLE_ID.json" <<'JSON'
{"id":"unreadable-entry","created_at":"2026-06-01T00:00:00Z","status":"pass"}
JSON
chmod 000 "$LEDGER/runs/$UNREADABLE_ID.json"
mkdir -p "$LEDGER/runs/not-a-run.json"
KUJO="$KUJO_BIN" "$RUNLEDGER" list --ledger "$LEDGER" >/tmp/runledger-cli-list-unreadable.out 2>&1 || fail "list crashed on unreadable file"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --ledger "$LEDGER" >/tmp/runledger-cli-report-unreadable.out 2>&1 || fail "report crashed on unreadable file"
chmod 644 "$LEDGER/runs/$UNREADABLE_ID.json"

echo "CLI integration: ok"
