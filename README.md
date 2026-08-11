# RunLedger

[![Version](https://img.shields.io/badge/version-1.0.0-black)](https://github.com/kujolang/runledger)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![built with Kujo](https://img.shields.io/badge/built%20with-Kujo-white.svg)](https://github.com/kujolang/kujo)

A local ledger for AI-agent build runs.

When you hand several agents (Claude, Codex, DeepSeek, a local model, a future
Kujo-native agent) the same prompt and ask them to build the same thing,
RunLedger gives you a repeatable, inspectable **receipt** for each attempt: what
model ran, against which repo and commit, what files changed, whether tests
passed, optional token/cost data you recorded, your verdict, and the follow-ups
needed.

It is built in the Kujo language runtime and stores everything as plain JSON on
your local disk. No database, no network, no API key.

## What RunLedger is — and is not

RunLedger **is** a structured receipt system for agent work. It records and
compares runs so you can answer questions like:

- Which model followed the prompt best?
- Which run changed the fewest files?
- Which run produced passing tests?
- Which run needed the fewest follow-up fixes?
- Which run was most expensive?
- Which run produced the cleanest handoff?

RunLedger is deliberately **not**:

- a deep automated code reviewer,
- an Eval runner or benchmark judge,
- a Scout replacement,
- a ShipCheck replacement,
- a Trail replacement,
- a prompt manager or workflow-pack validator.

It does not try to judge code quality. It records facts you give it plus a few
read-only git facts, and presents them back clearly.

## Readiness posture

RunLedger is intentionally small, local-first, and automation-friendly. It is
ready to use as a practical agent-run receipt ledger, but "enterprise grade" is
an ongoing standard rather than a one-time label. The current implementation
prioritizes:

- local JSON storage with no network calls and no provider API keys,
- read-only git metadata collection,
- atomic writes for run files and generated reports,
- explicit exit codes for automation,
- defensive loading of partial or malformed run files,
- safe run-id handling so user-supplied IDs cannot escape the ledger directory,
- markdown report output that stays stable when user text contains table
  punctuation.

The next major robustness frontier is optional higher-level workflow capture:
recording commands/tests, adding machine-readable report metadata, and adding
coordination safeguards if multiple writers target the same ledger at once.

## Installation

RunLedger runs on the Kujo interpreter. You need a `kujo` binary available.

### Preflight: verify the right `kujo` binary

RunLedger requires the Kujo language runtime (the one that supports
`kujo run ...`). Python's linting tool named `kujo` is not compatible.

```bash
kujo --help
# Expected: help output includes a `run` command.
```

```bash
# 1. Get this project
cd runledger

# 2. Confirm Kujo is on your PATH
kujo --version

# 3. (optional) put the launcher on your PATH
export PATH="$PWD/bin:$PATH"

# 4. Check it works
runledger version
```

You can always invoke it directly without the wrapper:

```bash
kujo run /path/to/runledger/runledger.kujo -- <command> [arguments]
```

> Note the `--`: it separates Kujo's own flags from RunLedger's arguments.

## Quick start

```bash
# Start a run (records start commit + dirty state from the repo)
runledger start \
  --provider anthropic \
  --model claude-opus-4-8 \
  --task "Build Tool X" \
  --prompt ./examples/build-tool-x.md \
  --repo .

# ... let the agent do its work ...

# Record token usage and cost (both optional, both manual)
runledger usage <run-id> --input 140000 --output 22000
runledger cost  <run-id> --total 1.18 --currency USD

# Add a follow-up you noticed
runledger followup <run-id> "Add tests for JSON output"

# Finish it: status, verdict, and end git state are captured
runledger finish <run-id> --status partial --verdict "good foundation, needs docs fixes"

# Review and report
runledger list
runledger compare
runledger report --output RUNLEDGER_REPORT.md
```

## Comparing Claude, Codex, and DeepSeek

Give each agent the same prompt, then record each attempt against the same task
name so they line up in `compare` and `report`. The helper below keeps the
repeated command shape copyable without obscuring the lifecycle steps:

```bash
TASK="Build Tool X"
PROMPT="./examples/build-tool-x.md"

start_run() {
  runledger start --provider "$1" --model "$2" --task "$TASK" --prompt "$PROMPT" --repo . |
    sed -n '1s/^Started run: //p'
}

# Claude
id=$(start_run anthropic claude-opus-4-8)
# ...run the agent...
runledger usage "$id" --input 140000 --output 22000
runledger cost  "$id" --total 1.18
runledger finish "$id" --status pass --verdict "clean handoff"

# Codex
id=$(start_run openai codex)
runledger usage "$id" --input 190000 --output 26000
runledger cost  "$id" --total 0.92
runledger followup "$id" "Add tests for JSON output"
runledger finish "$id" --status partial --verdict "good start"

# DeepSeek
id=$(start_run deepseek deepseek-v3)
runledger usage "$id" --input 210000 --output 31000
runledger cost  "$id" --total 0.40
runledger finish "$id" --status fail --verdict "tests broken"

runledger compare --task "$TASK"
runledger report  --task "$TASK" --output RUNLEDGER_REPORT.md
```

## Command reference

| Command | Description |
|---|---|
| `start` | Create a new run record and capture start git state. |
| `finish <run-id>` | Finalize a run: status, verdict, optional note, end git state. |
| `list` | List recorded runs in a compact table (`--json` for raw). |
| `show <run-id>` | Show one run in readable form (`--json` for the raw record). |
| `note <run-id> "text"` | Add a timestamped note. |
| `followup <run-id> "text"` | Add a follow-up item. |
| `usage <run-id>` | Record token usage. |
| `cost <run-id>` | Record cost (manual, with configurable currency). |
| `compare` | Compare runs (`--task` to filter, `--json` for raw). |
| `report` | Generate a markdown report (`--output <file>` to save). |
| `help` / `--help` | Show usage. |
| `version` / `--version` | Show the current RunLedger version. |

### Flags

- `start`: `--model` `--provider` `--task` (required); `--prompt <file>` `--repo <path>` (default `.`) `--ledger <dir>`
- `finish`: `--status <s>` `--verdict <text>` (required); `--notes <text>` `--repo <path>` (defaults to the run's recorded repo)
- `usage`: `--input` `--output` `--cache-read` `--cache-write` (all optional integers)
- `cost`: `--total` `--currency` `--input` `--output` `--cache` (amounts are floats; only provided fields change)
- `compare` / `report`: `--task <name>`; `compare --json`; `report --output <file>`

Allowed statuses: `in_progress`, `pass`, `partial`, `fail`, `abandoned`. An
invalid status fails with a clear error and a non-zero exit code.
`finish` accepts only terminal statuses: `pass`, `partial`, `fail`, and
`abandoned`.

### Exit codes

- `0` success
- `1` operational failure (no such run, invalid status, corrupt file)
- `2` usage error (bad/missing arguments, unknown command, invalid numeric flag value)

## Where data is stored

By default RunLedger writes to `./.runledger/` in your current directory:

```text
.runledger/
  runs/
    2026-05-29-claude-opus-4-8-build-tool-x-001.json
    2026-05-29-codex-build-tool-x-001.json
    ...
```

One run = one human-readable, sortable JSON file named by its id
(`YYYY-MM-DD-<model>-<task>-NNN`). Existing run files are never silently
overwritten on `start`.

Override the location with `--ledger <dir>` on any command, or set the
`RUNLEDGER_DIR` environment variable. The ledger directory is independent of the
`--repo` you record against, so a single ledger can track runs across many repos.

## Storage format

Each run is a single JSON object. Fields:

| Field | Meaning |
|---|---|
| `id` | Stable, human-readable run id. |
| `created_at` / `updated_at` | ISO-8601 UTC timestamps. |
| `status` | `in_progress` \| `pass` \| `partial` \| `fail` \| `abandoned`. |
| `provider` / `model` | Who ran it. |
| `task_name` | The task the run is an attempt at. |
| `prompt_file` | Path to the prompt used (optional). |
| `repo_path` | Repo the run worked on. |
| `start_commit` / `end_commit` | Git commit at start/finish (null if no git). |
| `git_dirty_start` / `git_dirty_end` | Working-tree dirty state (null if no git). |
| `changed_files` | Files changed in the working tree at finish. |
| `commands` / `tests` | Reserved arrays for reported commands and test results. |
| `usage` | `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`. |
| `cost` | `currency`, `input_cost`, `output_cost`, `cache_cost`, `total_cost`. |
| `verdict` | Your one-line human verdict. |
| `followups` | Timestamped follow-up items. |
| `notes` | Timestamped notes. |

`null` means "unknown" (e.g. token counts you never recorded, or git facts when
the repo isn't under git) — distinct from a genuine zero.

### Example run record

```json
{
  "id": "2026-05-29-codex-build-tool-x-001",
  "created_at": "2026-05-29T18:19:59Z",
  "updated_at": "2026-05-29T18:19:59Z",
  "status": "partial",
  "provider": "openai",
  "model": "codex",
  "task_name": "Build Tool X",
  "prompt_file": "./examples/build-tool-x.md",
  "repo_path": ".",
  "start_commit": "b5d96adb054cb26fe92aa8e8b6524e5d89a56051",
  "end_commit": "b5d96adb054cb26fe92aa8e8b6524e5d89a56051",
  "git_dirty_start": false,
  "git_dirty_end": true,
  "changed_files": ["main.kujo"],
  "commands": [],
  "tests": [],
  "usage": {
    "input_tokens": 190000,
    "output_tokens": 26000,
    "cache_read_tokens": null,
    "cache_write_tokens": null
  },
  "cost": {
    "currency": "USD",
    "input_cost": null,
    "output_cost": null,
    "cache_cost": null,
    "total_cost": 0.92
  },
  "verdict": "good start",
  "followups": [
    { "at": "2026-05-29T18:20:00Z", "text": "Add tests for JSON output" }
  ],
  "notes": []
}
```

## Example markdown report

`runledger report` produces a clean markdown summary. A full sample lives in
[examples/RUNLEDGER_REPORT.example.md](examples/RUNLEDGER_REPORT.example.md):

```markdown
# RunLedger Report

Generated: 2026-05-29T18:20:01Z

## Summary

| Runs | Pass | Partial | Fail | Abandoned |
| ---: | ---: | ---: | ---: | ---: |
| 3 | 1 | 1 | 1 | 0 |

## Runs

| ID | Task | Provider | Model | Status | Verdict | Changed files | Follow-ups | Cost |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: |
| ...-claude-opus-4-8-... | Build Tool X | anthropic | claude-opus-4-8 | pass | clean handoff | 1 | 0 | 1.18 USD |
| ...-codex-...           | Build Tool X | openai    | codex           | partial | good start | 1 | 1 | 0.92 USD |
| ...-deepseek-v3-...     | Build Tool X | deepseek  | deepseek-v3     | fail | tests broken | 1 | 1 | 0.4 USD |
```

The report never declares a "best" or "worst" run automatically — it surfaces
your verdicts and the raw counts and lets you decide.

## Cost and pricing

RunLedger does not hardcode provider pricing. Cost is **manual**: you supply
`--total` (and optionally per-segment `--input` / `--output` / `--cache` costs
and a `--currency`). This keeps the tool honest and provider-agnostic; pricing
tables change constantly and don't belong baked into a receipt system.
Reports aggregate recorded costs per currency; unlike currencies are never
combined into a dimensionally invalid grand total.

## Git metadata

When `--repo` points inside a git repository, RunLedger records the start/end
commit, dirty state, and changed files using **read-only** git commands only
(`rev-parse`, `status --porcelain`, `diff --name-only`, `ls-files`). It never
stages, commits, resets, checks out, or otherwise mutates git state. If git is
absent or the path isn't a repo, those fields are recorded as `null`/empty and
the command still succeeds.

## Running the tests

```bash
./tests/run.sh
# or
kujo run tests/runledger_test.kujo
```

The suite is filesystem-isolated (it uses a throwaway ledger and a throwaway git
repo under the system temp dir), needs no network or API key, and exits non-zero
on any failure. `tests/run.sh` runs both the module-level Kujo test harness and
CLI integration checks through `bin/runledger`.

## Limitations

- Token usage and cost are recorded manually; RunLedger does not capture them
  from any provider automatically.
- `finish` requires an explicit terminal status (`pass`, `partial`, `fail`, or
  `abandoned`) and a non-empty `--verdict`.
- `commands` and `tests` are present in the schema but are reserved for future
  population; the current CLI does not write them.
- The launcher needs a `kujo` binary (via `KUJO` or your `PATH`).
- Run files are plain JSON; editing them by hand is supported. RunLedger
  tolerates missing fields, rejects mismatched run IDs, and skips invalid run
  files during list/report operations.

## Non-goals

Repo intelligence, generic code review, automated benchmarking/Eval, prompt
management, and workflow-pack validation are explicitly out of scope. RunLedger
stays a small, focused, local receipt system for agent runs.

## Project layout

```text
runledger/
  runledger.kujo          # entrypoint
  bin/runledger           # launcher wrapper
  kujo.toml               # project manifest
  src/
    util.kujo             # slugs, time, padding, display helpers
    record.kujo           # run record shape + status validation
    storage.kujo          # ledger dir, id minting, safe save/load/list
    gitmeta.kujo          # defensive read-only git metadata
    render.kujo           # tables, single-run view, markdown report
    cli.kujo              # arg parsing + command dispatch
  tests/
    runledger_test.kujo   # test suite
    cli_integration.sh    # user-facing CLI checks
    run.sh                # test runner
  examples/
    build-tool-x.md             # sample prompt
    RUNLEDGER_REPORT.example.md  # sample generated report
  docs/reviews/
    BUG_HUNT_REPORT.md
    CODEX_REVIEW_RUNLEDGER.md
    RUNLEDGER_ENTERPRISE_REVIEW_2026-06-19.md
  .agent/
    next-agent-guide.md
    session-notes.md
```

## Contributor notes

Canonical copyable examples live in this README and
`examples/build-tool-x.md`. `examples/RUNLEDGER_REPORT.example.md` is a sample
generated report for output shape. Historical and follow-up review artifacts
live under `docs/reviews/`.

For repo sweeps, exclude generated/bulk paths such as `.runledger/` and avoid
treating generated report output as source examples unless the task explicitly
targets report formatting.
