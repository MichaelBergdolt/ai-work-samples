#!/usr/bin/env bash
# Adapted excerpt from a private project
#
# SubagentStop and Stop hook: one row per finished agent into .claude/metrics/agents.jsonl.
#
# WHY IT EXISTS: /context shows the context window of the session you type it in — the
# orchestrator's. What a subagent spent in ITS window is not visible there.
#
# WHAT ITERATIONS TAUGHT IT (each from a gap in the version before):
#
#   1. BASH COMMANDS, NOT ONLY `Read`. The first version counted only the Read tool and measured
#      past the target: the developer used Read once to six times per run, but Bash about 60. Only
#      the first word of each command is stored — it answers "where do the sixty turns go"
#      without writing paths, tokens or issue texts into a file nobody treats as a secret.
#
#   2. NO RAW HOOK INPUT. An earlier version also stored the raw hook payload, to learn which
#      fields `SubagentStop` sends. That payload carries `last_assistant_message` — the
#      developer's closing report, verbatim — which the reviewer must never see. A filter would be
#      a list of field names the platform owns, not this repository; so the raw row was dropped
#      entirely (absence instead of a fence). `hook_keys` keeps the *names* of the fields, never
#      their values.
#
#   3. WRITTEN AT THE MOMENT OF THE STOP. Transcripts did not survive until the next day; what is
#      not extracted here cannot be reconstructed later.
#
#   4. THE ORCHESTRATOR IS MEASURED TOO. `SubagentStop` never fires for the main session, so the
#      same script also hangs on `Stop` and writes `"agent": "orchestrator"`. `Stop` fires at the
#      end of EVERY answer, so rows of one session are nested prefixes of one transcript:
#      deduplicate by `session_id` (max), like subagents by `agent_id` (max) — `SubagentStop` also
#      fires several times per agent. That is a rule of the EVALUATION, not of the hook.
#
#      EACH EVENT READS ITS OWN FIELD: a `SubagentStop` carries both `agent_transcript_path`
#      (the subagent's) and `transcript_path` (the MAIN session's). An `or` between the two would
#      fill every subagent without its own transcript with the orchestrator's numbers — large,
#      plausible and wrong. What is missing stays `transcript_found: false`.
#
#   5. WHAT THE CACHE BRINGS BACK, NOT ONLY WHAT IT COSTS. Whether a 1h cache TTL pays off is
#      decided by whether the NEXT start hits the same prefix — visible only in the FIRST turn's
#      `cache_read`. Hence `first_turn_cache_read/_write`, the 1h/5m split of cache writes,
#      `max_context` and `model`. `None` and `0` are not the same: `0` means "measured, no write
#      of that TTL", `None` means "this client version does not send the split".
#
# WHAT IT MAY AND MAY NOT DO: it reads and writes one log file, nothing else. It never judges,
# never blocks, and must never make a run fail — hence `exit 0` at every exit. A measuring
# instrument that breaks the measurement is none.
#
# CONTRACT: reads the hook JSON on stdin, appends one JSONL row, always exits 0.

set -uo pipefail

INPUT=$(cat)
DIR="${CLAUDE_PROJECT_DIR:-.}"

printf '%s' "$INPUT" | python3 -c '
import json, sys, os, datetime, collections

BASE = os.path.join(sys.argv[1], ".claude", "metrics")
OUT  = os.path.join(BASE, "agents.jsonl")

raw_text = sys.stdin.read()
os.makedirs(BASE, exist_ok=True)

try:
    hook = json.loads(raw_text)
except Exception:
    sys.exit(0)

tin = tout = cread = cwrite = 0
cwrite_1h = cwrite_5m = 0
ttl_seen = False                 # did any turn carry a `cache_creation` object at all?
first_read = first_write = None  # the first turn alone - see point 5 above
max_context = 0
model = None
keys  = set()
reads = collections.Counter()   # file -> how often opened via Read
bash  = collections.Counter()   # first word of a Bash command -> how often
tools = collections.Counter()
turns = 0

def first_word(cmd):
    """First word of a command, without path and arguments. Deliberately coarse."""
    cmd = (cmd or "").strip()
    for prefix in ("(", "{", "!"):
        cmd = cmd.lstrip(prefix).strip()
    head = cmd.split()[0] if cmd.split() else "?"
    if head.startswith("VAR=") or "=" in head.split("/")[0][:12]:
        parts = cmd.split()
        head = parts[1] if len(parts) > 1 else head
    return os.path.basename(head)[:24]

# Which transcript is decided by the event, never by a fallback (point 4 above).
event = hook.get("hook_event_name")
if event == "Stop":
    agent, path = "orchestrator", hook.get("transcript_path")
else:
    agent, path = hook.get("agent_type"), hook.get("agent_transcript_path")

transcript_found = bool(path) and os.path.exists(path)

if transcript_found:
    with open(path, errors="replace") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get("message") or {}
            usage = msg.get("usage") or rec.get("usage") or {}
            if usage:
                turns += 1
                keys.update(usage.keys())
                t_in    = usage.get("input_tokens", 0) or 0
                t_read  = usage.get("cache_read_input_tokens", 0) or 0
                t_write = usage.get("cache_creation_input_tokens", 0) or 0
                tin    += t_in
                tout   += usage.get("output_tokens", 0) or 0
                cread  += t_read
                cwrite += t_write

                if first_read is None:
                    first_read, first_write = t_read, t_write

                # How full the window got in this turn - the number the sum cannot show.
                max_context = max(max_context, t_in + t_read + t_write)

                if msg.get("model"):
                    model = msg["model"]

                split = usage.get("cache_creation")
                if isinstance(split, dict):
                    ttl_seen = True
                    cwrite_1h += split.get("ephemeral_1h_input_tokens", 0) or 0
                    cwrite_5m += split.get("ephemeral_5m_input_tokens", 0) or 0
            content = msg.get("content")
            if isinstance(content, list):
                for block in content:
                    if not (isinstance(block, dict) and block.get("type") == "tool_use"):
                        continue
                    name = block.get("name", "?")
                    tools[name] += 1
                    inp = block.get("input") or {}
                    if name == "Read" and inp.get("file_path"):
                        reads[os.path.basename(inp["file_path"])] += 1
                    elif name == "Bash" and inp.get("command"):
                        bash[first_word(inp["command"])] += 1

row = {
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "event": event,
    "agent": agent,
    "agent_id": hook.get("agent_id"),
    "session_id": hook.get("session_id"),
    # Field NAMES of the hook input, never a single value.
    "hook_keys": sorted(hook.keys()),
    "transcript_found": transcript_found,
    "turns": turns,
    "in": tin, "out": tout, "cache_read": cread, "cache_write": cwrite,
    "first_turn_cache_read": first_read,
    "first_turn_cache_write": first_write,
    "cache_write_1h": cwrite_1h if ttl_seen else None,
    "cache_write_5m": cwrite_5m if ttl_seen else None,
    "max_context": max_context,
    "model": model,
    "tools": dict(tools.most_common(12)),
    "bash": dict(bash.most_common(25)),
    "reads": dict(reads.most_common(15)),
    "keys": sorted(keys),
}

with open(OUT, "a") as fh:
    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
' "$DIR" 2>/dev/null

exit 0
