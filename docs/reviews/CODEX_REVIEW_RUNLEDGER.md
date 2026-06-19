# Codex Review: RunLedger Opus 4.8 Build

## Executive summary
RunLedger is substantially on target: the core local receipt workflow works end-to-end, data stays local JSON, and git metadata capture is read-only and defensive. The implementation is small and maintainable, but there are meaningful gaps in runtime onboarding, CLI error handling, and agent-handoff docs that prevent an as-is acceptance.

## Score
Total score: 77/100

- Scope fit and product judgment: 15/15
- CLI usability: 11/15
- Data model and storage: 10/12
- Git metadata handling: 8/8
- Tests and verification: 10/15
- Documentation accuracy: 8/12
- Agent-memory hygiene: 0/8
- Code quality and maintainability: 10/10
- Safety and non-destructive behavior: 5/5

## Verdict
Needs focused fix pass

## What works well
- Strong scope discipline: this stayed a local run receipt ledger and did not drift into Scout/Eval/ShipCheck/Trail/Concord lanes.
- Core workflow works: `start`, `finish`, `list`, `show`, `note`, `followup`, `usage`, `cost`, `compare`, and `report` all function in real runs.
- Storage is clean and inspectable: one JSON file per run under a local ledger directory.
- Git handling is read-only and tolerant of non-git repos.
- Code organization is clear (`cli`/`storage`/`record`/`gitmeta`/`render` split is sensible and easy to extend).

## Verification performed
Commands run, with outcomes:

- `git status --short` -> pass (clean)
- `git diff --stat` -> pass (clean)
- `git diff --name-only` -> pass (clean)
- `git log --oneline -5` -> pass (`Initial commit`)
- `which kujo && kujo --version` -> pass (`kujo 0.15.13`, but wrong binary family for this project)
- `ls -l /path/to/kujo/target/release/kujo` -> pass (correct Kujo language runtime present)
- `/path/to/kujo/target/release/kujo --help | head -n 40` -> pass
- `KUJO=/path/to/kujo/target/release/kujo ./tests/run.sh` -> pass (`46 passed, 0 failed`)
- `KUJO=/path/to/kujo/target/release/kujo ./bin/runledger help` -> pass
- `KUJO=/path/to/kujo/target/release/kujo ./bin/runledger version` -> pass
- `/path/to/kujo/target/release/kujo package-install` -> pass (`no dependencies declared`)
- `/path/to/kujo/target/release/kujo check <each source/test file>` -> pass for all files
- Full isolated smoke flow in temp dirs (git + non-git) -> pass:
  - start sample run
  - show sample run
  - show sample run as JSON
  - note
  - followup
  - usage
  - cost
  - finish
  - list
  - compare
  - report generation
  - start/finish outside git repo
- Extra CLI error checks:
  - invalid status (`finish --status nope`) -> pass (exit 1 + clear message)
  - unknown command -> pass (exit 2 + clear message)
  - invalid numeric input (`usage --input notanint`) -> fails with raw VM runtime error (exit 4)

## Acceptance criteria checklist
- [x] The CLI can be run locally.
- [x] A run can be started.
- [x] A run can be finished.
- [x] Runs can be listed.
- [x] A run can be shown.
- [x] A run can be shown as JSON.
- [x] Notes can be added.
- [x] Follow-ups can be added.
- [x] Usage and/or cost can be recorded.
- [x] A markdown report can be generated.
- [x] The tool works without network access.
- [x] The tool does not require a provider API key.
- [x] Data is stored locally in a simple inspectable format.
- [~] Tests cover the core behavior. (Core behavior is covered, but coverage is mostly module-level; CLI argument/error-path integration coverage is limited.)
- [~] README matches the actual implementation. (Mostly accurate; runtime acquisition details are incomplete/misleading for environments with Python Kujo.)
- [x] Git metadata collection is read-only and defensive.
- [x] The implementation does not depend on unstable Kujo ecosystem conventions.
- [ ] Session notes were added or updated.
- [ ] A next-agent orientation guide was added or updated.
- [~] The final repo is easier for the next agent to work with. (Code is clean, but handoff docs are missing.)

## Issues found

### Critical
None.

### High

1. Runtime onboarding/docs are insufficient and partially misleading.
- Severity: High
- Affected files: `README.md:11`, `README.md:40-60`
- What is wrong: README links Kujo to a placeholder URL (`https://github.com/your-org/kujo`) and does not clearly warn that Python's `kujo` CLI is incompatible with `kujo run`.
- Why it matters: Fresh users can follow docs and still hit immediate command failure (`error: unrecognized subcommand 'run'`), blocking basic use.
- Suggested fix: Replace placeholder link with the real Kujo runtime source and add an explicit "Python Kujo is not compatible" prerequisite check (`kujo --help` should list `run`).
- Can Codex fix later: Yes.

2. Agent handoff artifacts required by the task are missing.
- Severity: High
- Affected files: missing `AGENTS.md`, `.agent/next-agent-guide.md`, `.agent/session-notes.md` (or equivalent documented convention)
- What is wrong: No session notes or next-agent orientation guide exists in repo.
- Why it matters: Explicit acceptance criteria in this run requested maintainable handoff context for follow-on agents.
- Suggested fix: Add concise, concrete session notes and next-agent guide with repo map, verification commands, known caveats, and prioritized next steps.
- Can Codex fix later: Yes.

### Medium

1. Numeric flag validation leaks raw VM runtime errors.
- Severity: Medium
- Affected files: `src/cli.kujo:305-310`, `src/cli.kujo:340-345`
- What is wrong: `parse_int`/`parse_float` exceptions are not handled.
- Why it matters: Invalid user input yields non-UX-friendly VM stack/runtime errors and inconsistent exit code (`4`), violating the declared CLI error model.
- Suggested fix: Add safe parse helpers returning `{ok,value}` or `{error}` and surface friendly usage errors with exit code `2`.
- Can Codex fix later: Yes.

2. `finish` does not enforce finalization semantics.
- Severity: Medium
- Affected files: `src/cli.kujo:173-185`, `src/cli.kujo:198-204`
- What is wrong: `finish` can succeed without `--status` and without `--verdict`, leaving run status as `in_progress` while printing "Finished run".
- Why it matters: This weakens receipt integrity and can create ambiguous run records.
- Suggested fix: Require terminal `--status` and non-empty `--verdict` on `finish` (or rename semantics to clarify "update").
- Can Codex fix later: Yes.

3. Report writes are non-atomic and delete existing outputs first.
- Severity: Medium
- Affected files: `src/cli.kujo:385-389`, `src/storage.kujo:68-78`
- What is wrong: Existing file is deleted before write.
- Why it matters: On write failure/crash, prior report/run data can be lost.
- Suggested fix: Write to temp file in same directory, then atomically rename.
- Can Codex fix later: Yes.

4. Tests are strong at module level but thin at CLI integration boundary.
- Severity: Medium
- Affected files: `tests/runledger_test.kujo:3-5`, `tests/runledger_test.kujo:124-199`
- What is wrong: Harness exercises internals directly; command parsing/exit code behavior and bad-input UX are mostly untested.
- Why it matters: Real-user regressions can slip through despite green tests.
- Suggested fix: Add small integration tests that invoke `bin/runledger` for key success and error paths.
- Can Codex fix later: Yes.

### Low

1. `README` includes an em-dash-heavy style and long prose where quick operational checks could be more explicit.
- Severity: Low
- Affected files: `README.md`
- What is wrong: Prerequisites and compatibility checks are buried compared to narrative text.
- Why it matters: Increases onboarding friction.
- Suggested fix: Add a short "Preflight" section with exact checks and expected output.
- Can Codex fix later: Yes.

2. Test harness shell command construction is not path-quoted.
- Severity: Low
- Affected files: `tests/runledger_test.kujo:54`, `tests/runledger_test.kujo:59-64`, `tests/runledger_test.kujo:68`
- What is wrong: Shell strings concatenate raw paths (`rm -rf`, `git -C`) without quoting.
- Why it matters: Rare failures on paths with spaces/special chars.
- Suggested fix: Quote paths or centralize shell-escaping helper in tests.
- Can Codex fix later: Yes.

### Nits

1. Help output does not include per-command usage examples.
- Severity: Nit
- Affected files: `src/cli.kujo:416-439`
- What is wrong: Global help is good but terse for individual flags.
- Why it matters: Slight UX friction.
- Suggested fix: Add 1-line usage for each command in help text.
- Can Codex fix later: Yes.

## Documentation review
README is largely aligned with observed behavior, including local-only scope and command set. The largest doc problem is runtime onboarding: it does not clearly disambiguate this Kujo runtime from Python Kujo and uses a placeholder Kujo URL. Session notes and next-agent docs are absent.

## Test review
The existing test suite is meaningful and passes (`46/46`), with strong coverage for storage, rendering, and git metadata behavior. The main gap is CLI integration and user-facing error paths (numeric parse failures, argument handling, exit-code contract), where runtime behavior currently diverges from the documented CLI error model.

## Scope review
Scope is good and focused. This implementation stays in the intended RunLedger lane (local provenance receipts) and does not attempt Scout/Eval/ShipCheck/Trail/Concord/spec/prompt-management responsibilities. No material scope drift found.

## Suggested fix order
1. Fix runtime onboarding and README prerequisite clarity (real Kujo link + incompatibility warning for Python Kujo).
2. Add session notes and next-agent guide artifacts.
3. Harden CLI numeric parsing and error mapping to the declared exit-code contract.
4. Tighten `finish` semantics so "finished" records cannot remain ambiguous.
5. Make report/run-file writes atomic.
6. Add thin CLI integration tests for critical success/error paths.

## Final recommendation
Keep the Opus implementation and request a focused Codex fix pass. A rebuild is unnecessary; the foundation is solid, but the above fixes should land before treating this as a reliable primitive.
