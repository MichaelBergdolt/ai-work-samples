# Agent cost report (aggregated)

Generated with [`tools/agent_costs.py`](tools/agent_costs.py) from the project's local
`agents.jsonl` (2 427 raw rows, 2026-09-04 to 2026-10-09). The raw log is not part of this
repository. Weights in input-token equivalents of the same model: input 1, cache read 0.1,
cache write 2 (1h) / 1.25 (5m), output 5. Price differences between models are not applied.

## Subagents, whole period

```
python3 tools/agent_costs.py agents.jsonl
```

| Agent | Runs | Turns/run | Weighted tokens (M) | Cost share | Output share of own cost | Start prefix read from cache |
|---|---:|---:|---:|---:|---:|---:|
| entwickler | 59 | 105 | 130.7 | 71.3% | 3.1% | 11% |
| pr-pruefer | 79 | 20 | 27.8 | 15.1% | 2.8% | 19% |
| issue-autor | 40 | 29 | 21.0 | 11.5% | 3.0% | 7% |
| merge-waechter | 5 | 45 | 3.1 | 1.7% | 3.9% | n/a |
| general-purpose | 4 | 4 | 0.7 | 0.4% | 0.8% | n/a |

Period: 2026-09-04 – end of log. Deduplicated runs: 187. Rows without agent type or transcript
skipped: 1817. Runs whose cache writes were assumed to be 1h (no TTL split in the log): 39.

## Subagents and main session, since the main session is measured

```
python3 tools/agent_costs.py agents.jsonl --since 2026-09-17 --include-main
```

| Agent | Runs | Turns/run | Weighted tokens (M) | Cost share | Output share of own cost | Start prefix read from cache |
|---|---:|---:|---:|---:|---:|---:|
| main session | 46 | 116 | 140.4 | 48.8% | 13.3% | 41% |
| entwickler | 51 | 103 | 113.1 | 39.4% | 2.8% | 11% |
| pr-pruefer | 72 | 20 | 23.2 | 8.1% | 2.7% | 19% |
| issue-autor | 26 | 29 | 10.8 | 3.7% | 0.9% | 7% |

Period: 2026-09-17 – end of log. Deduplicated runs: 195. Rows without agent type or transcript
skipped: 1509. Runs whose cache writes were assumed to be 1h (no TTL split in the log): 1.

"Main session" is every top-level session in the project, not only `/lauf` orchestrator runs;
the log cannot tell them apart.

## Reading the columns

- **Runs** are deduplicated: `SubagentStop` fires several times per agent with a growing
  transcript, so rows are reduced to one per `agent_id` (one per `session_id` for the main
  session), keeping the one with the most turns.
- **Start prefix read from cache** = first-turn cache reads ÷ (first-turn cache reads + writes),
  only for runs logged after the hook started recording the first turn (2026-09-17).
- **Composition over all subagent runs** (same weights): cache reads 56.4 %, cache writes 40.6 %,
  output 3.0 %, uncached input < 0.1 %.
