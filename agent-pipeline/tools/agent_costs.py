#!/usr/bin/env python3
"""Cost share per agent from the `agents.jsonl` written by `hooks/token-log.sh`.

New for this repository; the source project has a budget script, but nothing that prints this
table.

Two rules from the measurement series decide the arithmetic:

* `SubagentStop` fires several times per agent, and each row holds the cumulative numbers of a
  growing transcript. Summing the rows counts one agent three times. So: deduplicate by
  `agent_id` and keep the row with the most turns.
* `Stop` fires after every answer of the main session; its rows are nested prefixes of one
  transcript. Same rule, keyed by `session_id`. Those rows cover *every* main session in the
  project (the `/lauf` orchestrator and ordinary interactive sessions alike) and only exist since
  the hook was attached to `Stop`; they are therefore reported only with `--include-main`.

Weights are in input-token equivalents of the same model: input 1, cache read 0.1,
cache write 2 (1h TTL) or 1.25 (5m TTL), output 5. Rows from client versions that do not report
the TTL split are counted as 1h writes (the project sets a 1h TTL for subagents); the report says
how many rows that affected. Price differences *between* models are not applied: a Sonnet token
and an Opus token count the same here.

Usage:
    python3 agent_costs.py path/to/agents.jsonl [--since YYYY-MM-DD] [--until YYYY-MM-DD]
                                                 [--include-main]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from dataclasses import dataclass, field

W_IN, W_READ, W_WRITE_1H, W_WRITE_5M, W_OUT = 1.0, 0.1, 2.0, 1.25, 5.0
MAIN = 'main session'


@dataclass
class Totals:
    runs: int = 0
    turns: int = 0
    tin: int = 0
    out: int = 0
    read: int = 0
    write: int = 0
    weighted: float = 0.0
    first_read: int = 0
    first_write: int = 0
    first_seen: str = '9999'
    ttl_fallback: int = 0
    models: set = field(default_factory=set)


def weighted_cost(row: dict) -> tuple[float, bool]:
    """Weighted tokens of one deduplicated row, and whether the TTL split had to be assumed."""
    w1h, w5m = row.get('cache_write_1h'), row.get('cache_write_5m')
    fallback = w1h is None or w5m is None
    if fallback:
        write = (row.get('cache_write') or 0) * W_WRITE_1H
    else:
        write = w1h * W_WRITE_1H + w5m * W_WRITE_5M
    cost = ((row.get('in') or 0) * W_IN + (row.get('cache_read') or 0) * W_READ
            + write + (row.get('out') or 0) * W_OUT)
    return cost, fallback


def load(path: str, since: str | None, until: str | None, include_main: bool):
    best: dict[tuple, dict] = {}
    skipped = 0
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            if not line.strip():
                continue
            row = json.loads(line)
            day = (row.get('ts') or '')[:10]
            if (since and day < since) or (until and day > until):
                continue
            if row.get('event') == 'Stop':
                if not include_main:
                    continue
                key, name = ('session', row.get('session_id')), MAIN
            else:
                key, name = ('agent', row.get('agent_id')), row.get('agent') or ''
            if not name or not row.get('turns'):
                skipped += 1          # no agent type or no transcript: nothing to count
                continue
            row['_name'] = name
            if key not in best or row['turns'] > best[key]['turns']:
                best[key] = row
    return list(best.values()), skipped


def aggregate(rows: list[dict]) -> dict[str, Totals]:
    by: dict[str, Totals] = defaultdict(Totals)
    for r in rows:
        t = by[r['_name']]
        cost, fallback = weighted_cost(r)
        t.runs += 1
        t.turns += r['turns']
        t.tin += r.get('in') or 0
        t.out += r.get('out') or 0
        t.read += r.get('cache_read') or 0
        t.write += r.get('cache_write') or 0
        t.weighted += cost
        t.ttl_fallback += fallback
        t.first_seen = min(t.first_seen, r['ts'][:10])
        if r.get('first_turn_cache_read') is not None:
            t.first_read += r['first_turn_cache_read']
            t.first_write += r.get('first_turn_cache_write') or 0
        if r.get('model'):
            t.models.add(r['model'])
    return by


def report(by: dict[str, Totals], skipped: int, since: str | None, until: str | None) -> str:
    total = sum(t.weighted for t in by.values()) or 1.0
    lines = [
        '| Agent | Runs | Turns/run | Weighted tokens (M) | Cost share | Output share of own cost '
        '| Start prefix read from cache |',
        '|---|---:|---:|---:|---:|---:|---:|',
    ]
    for name, t in sorted(by.items(), key=lambda kv: -kv[1].weighted):
        out_share = t.out * W_OUT / t.weighted if t.weighted else 0
        first = t.first_read + t.first_write
        hit = f'{t.first_read / first:.0%}' if first else 'n/a'
        lines.append(f'| {name} | {t.runs} | {t.turns / t.runs:.0f} | {t.weighted / 1e6:.1f} '
                     f'| {t.weighted / total:.1%} | {out_share:.1%} | {hit} |')
    span = f'{since or min(t.first_seen for t in by.values())} – {until or "end of log"}'
    fallback = sum(t.ttl_fallback for t in by.values())
    lines += [
        '',
        f'Period: {span}. Deduplicated runs: {sum(t.runs for t in by.values())}. '
        f'Rows without agent type or transcript skipped: {skipped}. '
        f'Runs whose cache writes were assumed to be 1h (no TTL split in the log): {fallback}.',
    ]
    return '\n'.join(lines)


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('log')
    p.add_argument('--since')
    p.add_argument('--until')
    p.add_argument('--include-main', action='store_true',
                   help='add deduplicated main-session rows (Stop hook) as one line')
    a = p.parse_args(argv)
    rows, skipped = load(a.log, a.since, a.until, a.include_main)
    if not rows:
        print('no rows in range', file=sys.stderr)
        return 1
    print(report(aggregate(rows), skipped, a.since, a.until))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
