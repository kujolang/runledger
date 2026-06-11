# RunLedger Report

Generated: 2026-05-29T18:24:48Z

## Summary

| Runs | Pass | Partial | Fail | Abandoned |
| ---: | ---: | ---: | ---: | ---: |
| 3 | 1 | 1 | 1 | 0 |

## Cost

Total recorded cost: 2.5 (across 3 run(s)).

## Runs

| ID | Task | Provider | Model | Status | Verdict | Changed files | Follow-ups | Cost |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: |
| 2026-05-29-claude-opus-4-8-build-tool-x-001 | Build Tool X | anthropic | claude-opus-4-8 | pass | clean handoff | 1 | 0 | 1.18 USD |
| 2026-05-29-codex-build-tool-x-001 | Build Tool X | openai | codex | partial | good start | 1 | 1 | 0.92 USD |
| 2026-05-29-deepseek-v3-build-tool-x-001 | Build Tool X | deepseek | deepseek-v3 | fail | tests broken | 1 | 1 | 0.4 USD |

## Runs by task

### Build Tool X

- 2026-05-29-claude-opus-4-8-build-tool-x-001 — pass (claude-opus-4-8)
- 2026-05-29-codex-build-tool-x-001 — partial (codex)
- 2026-05-29-deepseek-v3-build-tool-x-001 — fail (deepseek-v3)

## Follow-ups

### 2026-05-29-codex-build-tool-x-001

- Add tests for JSON output

### 2026-05-29-deepseek-v3-build-tool-x-001

- Fix failing build

## Notes

None.
