# Adapted excerpt from a private project
"""Regression tests for the hook gates — an excerpt of the original suite (129 test functions).

WHY THIS FILE EXISTS: the first version of the gates shipped with a protocol in the PR body —
35 cases, run by hand, written down as a table. A reviewer reading only the diff called that what
it was: a claim by the author, not a test. Four defects were in the scripts at the time, two of
them false positives that had already fired on the reviewer's own commands:

  * `git diff origin/dev...<sha> 2>/dev/null` was refused as "writing through the shell"
  * `echo "--- git push ---"` was refused as a write, because the gate read the inside of a string
  * `set -euo pipefail` was refused with a token-leak message
  * `git push origin HEAD:refs/heads/dev` passed — a gate that did not gate

A gate is worth exactly what its regression test is worth. The negative cases are not padding:
a gate that blocks everything is not a strict gate, it is an outage.

Run: `uvx pytest agent-pipeline/tests` (needs bash and python3).
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

HOOKS = Path(__file__).resolve().parents[1] / 'hooks'
GLOBAL_GATE = HOOKS / 'pre-tool-use.sh'
PRUEFER_GATE = HOOKS / 'pr-pruefer-guard.sh'
TOKEN_LOG = HOOKS / 'token-log.sh'

pytestmark = pytest.mark.skipif(shutil.which('bash') is None, reason='bash not available')


def _decide(script: Path, command: str, agent_type: str | None = None,
            tool_name: str = 'Bash', tool_input: dict | None = None,
            cwd: str | None = None) -> str | None:
    """Run a gate over one tool call; return its deny reason, or None when it lets it pass."""
    payload = {
        'session_id': 'test',
        'cwd': cwd or str(Path(__file__).resolve().parent),
        'hook_event_name': 'PreToolUse',
        'tool_name': tool_name,
        'tool_input': {'command': command} if tool_input is None else tool_input,
    }
    if agent_type:
        payload['agent_type'] = agent_type
        payload['agent_id'] = 'test-agent'
    done = subprocess.run(['bash', str(script)], input=json.dumps(payload),
                          capture_output=True, text=True, timeout=30)
    assert done.returncode == 0, f'gate exited {done.returncode}: {done.stderr}'
    if not done.stdout.strip():
        return None
    out = json.loads(done.stdout)['hookSpecificOutput']
    assert out['permissionDecision'] == 'deny'
    return out['permissionDecisionReason']


# --- Global gate: blocks, and names where the rule is written ---------------------------------

@pytest.mark.parametrize('command', [
    'git add -A',
    'git add .',
    'git push --force origin dev',
    'git push origin +HEAD:dev',
    'git push origin dev',
    'git push origin HEAD:refs/heads/dev',
    'git push origin HEAD:main',
    'curl -s -X PUT https://api.github.com/repos/x/y/pulls/1/merge --admin',
    'curl -s https://ghp_secret@github.com/x/y',
    'echo $GH_TOKEN',
    'cat .gh_token',
    'printenv',
    'rm -rf .claude/worktrees',
])
def test_global_gate_blocks_and_names_its_source(command):
    reason = _decide(GLOBAL_GATE, command)
    assert reason is not None, f'{command!r} passed the gate'
    # A message nobody can act on is the failure mode one level down.
    assert 'Fundstelle' in reason


@pytest.mark.parametrize('command', [
    'git add src/app.py tests/test_app.py',
    'git push -u origin feat/42-some-feature',
    'git push origin --delete feat/42-some-feature',
    "TOKEN=$(tr -d '\\r\\n' < .gh_token)",
    'curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/repos/x/y/issues/1',
    'printenv | grep DATABASE_URL',
    'env APP_TEST_DATABASE_URL=x pytest',
    'set -euo pipefail; ls src',
    'rm -rf /tmp/scratch/build',
])
def test_global_gate_lets_real_work_through(command):
    assert _decide(GLOBAL_GATE, command) is None, f'{command!r} was wrongly blocked'


@pytest.mark.parametrize('command', [
    # A repository documenting its own gates has to be able to name the commands they block.
    'git commit -m "fix: git push origin HEAD:refs/heads/dev passed the gate"',
    'echo "--- git push --force origin dev is refused ---"',
    'grep -rn "git add -A" docs/process.md',
])
def test_prose_about_a_blocked_command_is_not_a_blocked_command(command):
    assert _decide(GLOBAL_GATE, command) is None, f'{command!r} was wrongly blocked'


@pytest.mark.parametrize('command', [
    # ... but a quoted string that something *executes* is the real thing wearing quotes.
    'bash -c "git push --force origin dev"',
    'sh -c "git add -A"',
    'eval "git push origin HEAD:refs/heads/main"',
])
def test_an_interpreter_is_read_raw(command):
    assert _decide(GLOBAL_GATE, command) is not None, f'{command!r} passed the gate'


# --- Reviewer gate: no writing, no testing, nobody else affected ------------------------------

@pytest.mark.parametrize('command', [
    'curl -s --request PATCH https://api.github.com/x',
    '.claude/bin/gh-api.sh PATCH /issues/1 \'{"state":"closed"}\'',
    '.claude/bin/gh-api.sh PUT /pulls/1/merge \'{"merge_method":"squash"}\'',
    'git commit -m "kleine Reparatur"',
    'git -C /other/tree reset --hard',
    'git pull',
    'sed -i "" s/a/b/ src/app.py',
    'echo hallo > src/app.py',
    'pytest',
    'npm run verify',
])
def test_pruefer_gate_blocks_writing_and_testing(command):
    assert _decide(PRUEFER_GATE, command, agent_type='pr-pruefer') is not None, \
        f'{command!r} passed the reviewer gate'


@pytest.mark.parametrize('command', [
    'git diff origin/dev...0ac045c --stat',
    # The two that fired on the reviewer's own first review.
    'git diff origin/dev...0ac045c 2>/dev/null',
    'echo "--- git push in guard ---"',
    '.claude/bin/gh-api.sh GET /issues/1',
    'git fetch --prune',
    # A branch or a word named like a verb is still work.
    'git branch -d pull',
    'git log --grep="pull request"',
])
def test_pruefer_gate_lets_reading_through(command):
    assert _decide(PRUEFER_GATE, command, agent_type='pr-pruefer') is None, \
        f'{command!r} was wrongly blocked'


@pytest.mark.parametrize('agent_type', [None, 'entwickler', 'issue-autor'])
def test_pruefer_gate_touches_nobody_else(agent_type):
    assert _decide(PRUEFER_GATE, 'git commit -m "feat: x (#1)"', agent_type=agent_type) is None
    assert _decide(PRUEFER_GATE, 'pytest', agent_type=agent_type) is None


@pytest.mark.parametrize('tool_name, tool_input', [
    ('Read', {'file_path': '.claude/metrics/agents.jsonl'}),
    ('Glob', {'pattern': '.claude/metrics/*'}),
    ('Grep', {'pattern': 'x', 'path': '.claude/metrics'}),
    ('Bash', {'command': 'grep -rn entwickler .claude'}),
])
def test_the_reviewer_reaches_the_metrics_through_none_of_his_four_tools(tool_name, tool_input):
    assert _decide(PRUEFER_GATE, '', agent_type='pr-pruefer',
                   tool_name=tool_name, tool_input=tool_input) is not None


@pytest.mark.parametrize('tool_name, tool_input', [
    ('Read', {'file_path': '.claude/rules/prozess.md'}),
    # The pattern says *what* to look for, not where.
    ('Grep', {'pattern': '.claude/metrics', 'path': '.claude/hooks'}),
    ('Bash', {'command': 'grep -rn entwickler .claude --exclude-dir=metrics'}),
])
def test_the_reviewers_own_reading_is_not_caught_by_the_metrics_fence(tool_name, tool_input):
    assert _decide(PRUEFER_GATE, '', agent_type='pr-pruefer',
                   tool_name=tool_name, tool_input=tool_input) is None


# --- Metrics hook: numbers and field names, never the report ----------------------------------

REPORT = 'Fertig. Der Zaun verwehrt jetzt alles; Tests gruen. (Abschlussbericht des Entwicklers)'


def _run_token_log(project: Path, hook_input: dict) -> dict:
    done = subprocess.run(['bash', str(TOKEN_LOG)], input=json.dumps(hook_input),
                          capture_output=True, text=True, timeout=60,
                          env={**os.environ, 'CLAUDE_PROJECT_DIR': str(project)})
    assert done.returncode == 0
    rows = (project / '.claude' / 'metrics' / 'agents.jsonl').read_text().strip().split('\n')
    assert len(rows) == 1
    return json.loads(rows[0])


def test_the_metric_does_not_write_the_report_anywhere(tmp_path):
    row = _run_token_log(tmp_path, {
        'hook_event_name': 'SubagentStop',
        'agent_type': 'entwickler',
        'agent_id': 'agent-1',
        'agent_transcript_path': str(tmp_path / 'missing.jsonl'),
        'last_assistant_message': REPORT,
    })
    for f in (tmp_path / '.claude' / 'metrics').iterdir():
        assert 'Der Zaun verwehrt' not in f.read_text(), f'{f.name} carries the report'
    # The field NAME stays visible in `hook_keys`, its value nowhere.
    assert 'last_assistant_message' in row['hook_keys']
    assert row['transcript_found'] is False


def test_a_subagent_does_not_inherit_the_orchestrators_transcript(tmp_path):
    main = tmp_path / 'main.jsonl'
    main.write_text(json.dumps({'message': {'usage': {'input_tokens': 9000}}}) + '\n')
    row = _run_token_log(tmp_path, {
        'hook_event_name': 'SubagentStop',
        'agent_type': 'pr-pruefer',
        'agent_id': 'agent-2',
        'transcript_path': str(main),                       # the MAIN session's transcript
        'agent_transcript_path': str(tmp_path / 'none.jsonl'),
    })
    assert row['in'] == 0 and row['transcript_found'] is False


def test_the_numbers_are_still_counted(tmp_path):
    t = tmp_path / 't.jsonl'
    t.write_text('\n'.join(json.dumps(z) for z in [
        {'message': {'usage': {'input_tokens': 11, 'output_tokens': 22,
                               'cache_read_input_tokens': 33, 'cache_creation_input_tokens': 44,
                               'cache_creation': {'ephemeral_1h_input_tokens': 44,
                                                  'ephemeral_5m_input_tokens': 0}},
                     'content': [{'type': 'tool_use', 'name': 'Read',
                                  'input': {'file_path': '/x/DESIGN.md'}}]}},
        {'message': {'usage': {'input_tokens': 1, 'output_tokens': 2},
                     'content': [{'type': 'tool_use', 'name': 'Bash',
                                  'input': {'command': 'git diff --stat'}}]}},
    ]) + '\n')
    row = _run_token_log(tmp_path, {'hook_event_name': 'SubagentStop', 'agent_type': 'entwickler',
                                    'agent_id': 'agent-3', 'agent_transcript_path': str(t)})
    assert (row['turns'], row['in'], row['out'], row['cache_read'], row['cache_write']) == \
        (2, 12, 24, 33, 44)
    assert (row['first_turn_cache_read'], row['cache_write_1h']) == (33, 44)
    assert row['tools'] == {'Read': 1, 'Bash': 1} and row['bash'] == {'git': 1}
