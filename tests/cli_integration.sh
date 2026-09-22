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
runledger 1.1.0 — a local ledger for AI-agent build runs

Usage: runledger <command> [arguments]

Commands:
  start      Begin a new run record
             usage: runledger start --model <m> --provider <p> --task <t> [--prompt <file>] [--repo <path>]
  finish     Finalize a run (status, verdict, end git state)
             usage: runledger finish <run-id> --status <pass|partial|fail|abandoned> --verdict "text"
  list       List recorded runs in a compact table
             usage: runledger list [--json]
  verify     Check every run file and report invalid entries
             usage: runledger verify [--json]
  show       Show one run (add --json for the raw record)
             usage: runledger show <run-id> [--json]
  note       Add a timestamped note to a run
             usage: runledger note <run-id> "note text"
  followup   Add a follow-up item to a run
             usage: runledger followup <run-id> "follow-up text"
  command    Record a command description (does not execute it)
             usage: runledger command <run-id> "command text"
  test       Record a manual test outcome
             usage: runledger test <run-id> "test name" --status <pass|fail|skip>
  usage      Record token usage for a run
             usage: runledger usage <run-id> [--input N] [--output N] [--cache-read N] [--cache-write N]
  cost       Record cost for a run
             usage: runledger cost <run-id> [--total N] [--currency CODE] [--input N] [--output N] [--cache N]
  correlate  Link this receipt to Watchdog, Dispatch, Relay, or Eval identifiers
             usage: runledger correlate <run-id> [--watchdog-trace ID] [--watchdog-run ID] [--dispatch-run ID] [--relay-run ID] [--eval-run ID]
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

# Concurrent starts for the same model/task must retry ID allocation rather
# than clobbering a receipt or failing one of the writers.
START_RACE_LEDGER="$TMPROOT/start-race-ledger"
for i in $(seq 1 12); do
  KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model codex --task "Concurrent Start" --repo "$PLAIN" --ledger "$START_RACE_LEDGER" >"$TMPROOT/parallel-start-$i.out" 2>&1 &
done
wait
START_RACE_COUNT="$(find "$START_RACE_LEDGER/runs" -type f -name '*.json' | wc -l | tr -d ' ')"
[[ "$START_RACE_COUNT" -eq 12 ]] || fail "concurrent starts did not create 12 unique receipts (got $START_RACE_COUNT)"
if grep -l '^error:' "$TMPROOT"/parallel-start-*.out >/dev/null; then
  fail "a concurrent start failed instead of retrying ID allocation"
fi

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name runledger-test
printf "base\n" > "$REPO/base.txt"
git -C "$REPO" add base.txt
git -C "$REPO" commit -qm "init"

START_OUT="$(umask 000; KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model codex --task "CLI Test" --repo "$REPO" --ledger "$LEDGER")"
RID="$(printf '%s\n' "$START_OUT" | sed -n '1s/^Started run: //p')"
[[ -n "$RID" ]] || fail "did not parse run id from start output"
if stat -f '%Lp' "$LEDGER" >/dev/null 2>&1; then
  [[ "$(stat -f '%Lp' "$LEDGER")" == 700 ]] || fail "ledger directory is not private"
  [[ "$(stat -f '%Lp' "$LEDGER/runs/$RID.json")" == 600 ]] || fail "receipt is not private"
else
  [[ "$(stat -c '%a' "$LEDGER")" == 700 ]] || fail "ledger directory is not private"
  [[ "$(stat -c '%a' "$LEDGER/runs/$RID.json")" == 600 ]] || fail "receipt is not private"
fi

expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --verdict "missing status" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status pass --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status in_progress --verdict "bad terminal" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status pass --verdict "x" --notes --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" usage "$RID" --input notanint --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" cost "$RID" --total notafloat --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" cost "$RID" --currency --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" test "$RID" "suite" --status green --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" command "$RID" "   " --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" command "$RID" "$(printf '%02001d' 0)" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" test "$RID" "$(printf '%0201d' 0)" --status pass --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --unknown value --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" show "$RID" extra --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --json=false --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" usage "$RID" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" cost "$RID" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" correlate "$RID" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" correlate "$RID" --watchdog-trace '../unsafe' --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" "   " --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" followup "$RID" "   " --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" nope
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" show --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish --status pass --verdict "missing id" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model --task "missing model value" --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model codex --task "missing repo value" --repo --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider openai --model codex --task "missing prompt value" --prompt --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --ledger
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" report --output --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" compare --task --ledger "$LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" report --task --ledger "$LEDGER"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" show "../escape" --ledger "$LEDGER"
printf 'not a directory\n' > "$TMPROOT/ledger-as-file"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model m --task t --repo "$PLAIN" --ledger "$TMPROOT/ledger-as-file"
grep -q '^error: cannot create ledger runs directory:' /tmp/runledger-cli-last.out || fail "invalid ledger path did not fail cleanly"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" verify --ledger "$TMPROOT/ledger-as-file"
grep -q '^error: ledger path is not a directory:' /tmp/runledger-cli-last.out || fail "verify hid bad ledger root"

NESTED_LEDGER="$TMPROOT/nested/ledger/path"
NESTED_START="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model local-agent --task "Nested Ledger" --repo "$PLAIN" --ledger "$NESTED_LEDGER")"
NESTED_RID="$(printf '%s\n' "$NESTED_START" | sed -n '1s/^Started run: //p')"
[[ -s "$NESTED_LEDGER/runs/$NESTED_RID.json" ]] || fail "nested ledger run file missing"

PAGE_LEDGER="$TMPROOT/page-ledger"
PAGE_FIRST="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model a --task "Page" --repo "$PLAIN" --ledger "$PAGE_LEDGER" | sed -n '1s/^Started run: //p')"
PAGE_SECOND="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model b --task "Page" --repo "$PLAIN" --ledger "$PAGE_LEDGER" | sed -n '1s/^Started run: //p')"
PAGE_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" list --json --limit 1 --offset 1 --ledger "$PAGE_LEDGER")"
[[ "$PAGE_JSON" == *"\"$PAGE_SECOND\""* && "$PAGE_JSON" != *"\"$PAGE_FIRST\""* ]] || fail "file-ordered pagination returned wrong run"
PAGE_REPORT="$TMPROOT/page-report.md"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --limit 1 --offset 1 --output "$PAGE_REPORT" --ledger "$PAGE_LEDGER"
grep -q 'Summary counts refer to this page only' "$PAGE_REPORT" || fail "paged report did not identify partial totals"
grep -q "$PAGE_SECOND" "$PAGE_REPORT" || fail "paged report omitted selected run"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --limit 0 --ledger "$PAGE_LEDGER"
expect_exit 2 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --offset -1 --ledger "$PAGE_LEDGER"
printf '%s\n' '{broken' > "$PAGE_LEDGER/runs/zz-corrupt.json"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --strict --limit 1 --ledger "$PAGE_LEDGER"
PAGE_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" list --json --limit 1 --ledger "$PAGE_LEDGER")"
[[ "$PAGE_JSON" == *"\"$PAGE_FIRST\""* ]] || fail "non-strict page failed on corruption outside its window"

KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" "cli note" --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" '![remote](https://example.invalid/track)' --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" --ledger "$LEDGER" -- "--dash-prefixed note"

# Concurrent read-modify-write commands must serialize without losing entries.
for i in $(seq 1 12); do
  KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" "parallel-note-$i" --ledger "$LEDGER" >"$TMPROOT/parallel-note-$i.out" 2>&1 &
done
wait
PARALLEL_SHOW="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$RID" --json --ledger "$LEDGER")"
PARALLEL_COUNT="$(printf '%s\n' "$PARALLEL_SHOW" | grep -c '"text": "parallel-note-')"
[[ "$PARALLEL_COUNT" -eq 12 ]] || fail "concurrent notes were lost (expected 12, got $PARALLEL_COUNT)"
if find "$LEDGER/locks" -type f -print -quit | grep -q .; then
  fail "record lock remained after successful concurrent updates"
fi

# A pre-existing lock produces a bounded, actionable conflict and is never
# deleted by a process that does not own it.
LOCK_PATH="$LEDGER/locks/$RID.lock"
printf '%s\n' '{"token":"other-writer","run_id":"held","created_at":"2026-08-30T00:00:00Z"}' > "$LOCK_PATH"
expect_exit 1 env RUNLEDGER_LOCK_TIMEOUT_MS=25 KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" "must-not-write" --ledger "$LEDGER"
grep -q '^error: run is busy:' /tmp/runledger-cli-last.out || fail "lock conflict was not actionable"
[[ -f "$LOCK_PATH" ]] || fail "non-owner removed an active record lock"
rm -f "$LOCK_PATH"

KUJO="$KUJO_BIN" "$RUNLEDGER" followup "$RID" "cli followup" --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" command "$RID" "touch $TMPROOT/must-not-exist" --ledger "$LEDGER"
[[ ! -e "$TMPROOT/must-not-exist" ]] || fail "recorded command was executed"
KUJO="$KUJO_BIN" "$RUNLEDGER" test "$RID" "unit suite" --status pass --details "81 assertions" --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" test "$RID" "smoke suite" --status skip --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" usage "$RID" --input 10 --output 2 --cache-read 1 --cache-write 0 --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" cost "$RID" --total 0.5 --currency USD --ledger "$LEDGER"
KUJO="$KUJO_BIN" "$RUNLEDGER" correlate "$RID" --watchdog-trace 0123456789abcdef0123456789abcdef --dispatch-run dispatch:run-1 --relay-run relay:run-1 --eval-run eval:run-1 --ledger "$LEDGER"
printf "delta\n" >> "$REPO/base.txt"
KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status partial --verdict "ok" --ledger "$LEDGER"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$RID" --status fail --verdict "rewritten" --ledger "$LEDGER"

SHOW_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$RID" --json --ledger "$LEDGER")"
[[ "$SHOW_JSON" == *'"verdict": "ok"'* ]] || fail "show --json missing verdict"
[[ "$SHOW_JSON" == *'"name": "unit suite"'* ]] || fail "show --json missing recorded test"
[[ "$SHOW_JSON" == *'"text": "touch '* ]] || fail "show --json missing recorded command"
SHOW_TEXT="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$RID" --ledger "$LEDGER")"
[[ "$SHOW_TEXT" == *'Recorded commands (1):'* && "$SHOW_TEXT" == *'Recorded tests (2):'* ]] || fail "show omitted evidence"
[[ "$SHOW_JSON" == *'"watchdog_trace_id": "0123456789abcdef0123456789abcdef"'* ]] || fail "show --json missing Watchdog correlation"
LIST_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" list --json --ledger "$LEDGER")"
[[ "$LIST_JSON" == *"\"$RID\""* ]] || fail "list --json missing run id"
KUJO="$KUJO_BIN" "$RUNLEDGER" verify --ledger "$LEDGER" | grep -q 'no invalid entries' || fail "valid ledger did not verify"
COMPARE_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" compare --json --task "CLI Test" --ledger "$LEDGER")"
[[ "$COMPARE_JSON" == *"\"$RID\""* ]] || fail "compare --json missing run id"

REPORT="$TMPROOT/RUNLEDGER_REPORT.md"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --task "CLI Test" --output "$REPORT" --ledger "$LEDGER"
[[ -s "$REPORT" ]] || fail "report file missing or empty"
if stat -f '%Lp' "$REPORT" >/dev/null 2>&1; then
  [[ "$(stat -f '%Lp' "$REPORT")" == 600 ]] || fail "generated report is not private"
else
  [[ "$(stat -c '%a' "$REPORT")" == 600 ]] || fail "generated report is not private"
fi
grep -q '^## Recorded tests' "$REPORT" || fail "report omitted test evidence"
if grep -Fq '![remote](https://example.invalid/track)' "$REPORT"; then
  fail "report left embedded Markdown image active"
fi
REPORT_NESTED="$TMPROOT/nested/out/RUNLEDGER_REPORT.md"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --task "CLI Test" --output "$REPORT_NESTED" --ledger "$LEDGER"
[[ -s "$REPORT_NESTED" ]] || fail "nested report file missing or empty"
mkdir -p "$TMPROOT/report-target-is-directory"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" report --output "$TMPROOT/report-target-is-directory" --ledger "$LEDGER"
grep -q '^error: cannot write file:' /tmp/runledger-cli-last.out || fail "report write failure was not actionable"

# A tiny POSIX file-size quota simulates exhausted writable capacity without
# mounting a disk or altering the host. Ignore SIGXFSZ so write returns an
# error that the CLI must turn into exit 1; atomic output must not be published.
KUJO="$KUJO_BIN" "$RUNLEDGER" note "$RID" "$(printf '%04000d' 0)" --ledger "$LEDGER" >/dev/null
set +e
bash -c 'trap "" XFSZ; ulimit -f 1; KUJO="$1" "$2" report --output "$3/quota-report.md" --ledger "$4"' _ "$KUJO_BIN" "$RUNLEDGER" "$TMPROOT" "$LEDGER" >/tmp/runledger-cli-last.out 2>&1
quota_exit=$?
set -e
[[ "$quota_exit" -eq 1 ]] || fail "file-size quota did not return operational exit 1 (got $quota_exit)"
grep -q '^error: cannot write file:' /tmp/runledger-cli-last.out || fail "file-size quota error was not actionable"
[[ ! -e "$TMPROOT/quota-report.md" ]] || fail "partial quota-constrained report was published"

# POSIX read/write permission failures are operational errors; a privileged
# runner may bypass chmod restrictions, in which case this fixture is skipped.
PROTECTED_DIR="$TMPROOT/protected"
mkdir -p "$PROTECTED_DIR"
chmod 500 "$PROTECTED_DIR"
if ! (printf 'probe\n' > "$PROTECTED_DIR/probe") 2>/dev/null; then
  expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" report --output "$PROTECTED_DIR/report.md" --ledger "$LEDGER"
  grep -q '^error: cannot write file:' /tmp/runledger-cli-last.out || fail "permission-denied report failure was not actionable"
fi
chmod 700 "$PROTECTED_DIR"

chmod 000 "$LEDGER/runs"
if ! (ls "$LEDGER/runs" >/dev/null 2>&1); then
  expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" verify --ledger "$LEDGER"
  grep -q '^error: cannot list runs directory:' /tmp/runledger-cli-last.out || fail "unreadable ledger directory was hidden"
fi
chmod 700 "$LEDGER/runs"

# A completed, clean commit is still a run change, and committed + uncommitted
# paths are reported once each.
git -C "$REPO" add base.txt
git -C "$REPO" commit -qm "prepare clean commit test"
COMMIT_START="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model local-agent --task "Committed Work" --repo "$REPO" --ledger "$LEDGER")"
COMMIT_RID="$(printf '%s\n' "$COMMIT_START" | sed -n '1s/^Started run: //p')"
printf 'committed\n' > "$REPO/committed.txt"
git -C "$REPO" add committed.txt
git -C "$REPO" commit -qm "implement run"
KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$COMMIT_RID" --status pass --verdict "clean commit" --ledger "$LEDGER"
COMMIT_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$COMMIT_RID" --json --ledger "$LEDGER")"
[[ "$COMMIT_JSON" == *'"git_dirty_end": false'* ]] || fail "committed run should finish clean"
[[ "$COMMIT_JSON" == *'"committed.txt"'* ]] || fail "committed change missing from run receipt"

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

# An explicit different repository cannot resolve the original start commit;
# finish should still capture its worktree safely without claiming a diff.
OTHER_REPO="$TMPROOT/other-repo"
mkdir -p "$OTHER_REPO"
git -C "$OTHER_REPO" init -q
git -C "$OTHER_REPO" config user.email test@example.com
git -C "$OTHER_REPO" config user.name runledger-test
printf 'before\n' > "$OTHER_REPO/base.txt"
git -C "$OTHER_REPO" add base.txt
git -C "$OTHER_REPO" commit -qm base
OVERRIDE_START="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model local-agent --task "Repo Override" --repo "$REPO" --ledger "$LEDGER")"
OVERRIDE_RID="$(printf '%s\n' "$OVERRIDE_START" | sed -n '1s/^Started run: //p')"
printf 'untracked\n' > "$OTHER_REPO/other.txt"
KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$OVERRIDE_RID" --status partial --verdict "repo override" --repo "$OTHER_REPO" --ledger "$LEDGER"
OVERRIDE_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$OVERRIDE_RID" --json --ledger "$LEDGER")"
[[ "$OVERRIDE_JSON" == *'"other.txt"'* ]] || fail "override repository lost working-tree evidence"

# Git SHA-256 repositories produce 64-character commit IDs. Skip only when the
# installed Git cannot create them; normal SHA-1 behavior is tested above.
SHA_REPO="$TMPROOT/sha256-repo"
if git init -q --object-format=sha256 "$SHA_REPO" >/dev/null 2>&1; then
  git -C "$SHA_REPO" config user.email test@example.com
  git -C "$SHA_REPO" config user.name runledger-test
  printf 'before\n' > "$SHA_REPO/base.txt"
  git -C "$SHA_REPO" add base.txt
  git -C "$SHA_REPO" commit -qm base
  SHA_START="$(KUJO="$KUJO_BIN" "$RUNLEDGER" start --provider local --model local-agent --task "SHA256" --repo "$SHA_REPO" --ledger "$LEDGER")"
  SHA_RID="$(printf '%s\n' "$SHA_START" | sed -n '1s/^Started run: //p')"
  printf 'after\n' > "$SHA_REPO/sha-file.txt"
  git -C "$SHA_REPO" add sha-file.txt
  git -C "$SHA_REPO" commit -qm after
  KUJO="$KUJO_BIN" "$RUNLEDGER" finish "$SHA_RID" --status pass --verdict "sha256" --ledger "$LEDGER"
  SHA_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$SHA_RID" --json --ledger "$LEDGER")"
  [[ "$SHA_JSON" == *'"sha-file.txt"'* ]] || fail "SHA-256 committed file missing"
else
  echo "SHA-256 Git fixture: unsupported by installed Git (skipped)" >&2
fi

# Non-object JSON run files should be ignored without crashing.
cat > "$LEDGER/runs/not-an-object.json" <<'JSON'
[]
JSON
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" verify --ledger "$LEDGER"
grep -q 'invalid run file shape:' /tmp/runledger-cli-last.out || fail "verify hid invalid receipt"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" list --strict --json --ledger "$LEDGER"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" compare --strict --ledger "$LEDGER"
expect_exit 1 env KUJO="$KUJO_BIN" "$RUNLEDGER" report --strict --ledger "$LEDGER"
VERIFY_JSON="$(KUJO="$KUJO_BIN" "$RUNLEDGER" verify --json --ledger "$LEDGER" || true)"
[[ "$VERIFY_JSON" == *'"file": "not-an-object.json"'* ]] || fail "verify JSON did not identify invalid receipt"
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

# Invalid scalar types are normalized to unknown values instead of crashing
# show/report, and invalid changed-file entries are discarded.
TYPED_ID="invalid-field-types"
cat > "$LEDGER/runs/$TYPED_ID.json" <<'JSON'
{"id":"invalid-field-types","cost":{"currency":[],"total_cost":"oops"},"usage":{"input_tokens":"many"},"changed_files":[1,"valid.txt"]}
JSON
TYPED_SHOW="$(KUJO="$KUJO_BIN" "$RUNLEDGER" show "$TYPED_ID" --json --ledger "$LEDGER")"
[[ "$TYPED_SHOW" == *'"total_cost": null'* ]] || fail "invalid cost was not normalized"
[[ "$TYPED_SHOW" == *'"valid.txt"'* && "$TYPED_SHOW" != *'"changed_files": [\n    1'* ]] || fail "invalid changed-file entry was not filtered"
KUJO="$KUJO_BIN" "$RUNLEDGER" report --ledger "$LEDGER" >/tmp/runledger-cli-report-types.out 2>&1 || fail "report crashed on invalid field types"

echo "CLI integration: ok"
