#!/usr/bin/env bash
# Adapted excerpt from a private project
#
# PreToolUse gate for the `pr-pruefer` only, on the four tools it has (Bash, Read, Grep, Glob).
# Which tools that is, is decided by the matcher in `settings.json`, not by this line.
#
# WHY A SECOND GATE: the pr-pruefer's whole value is that it cannot drift. Its frontmatter leaves
# out `Write` and `Edit`, but Bash is a hole in that: `sed -i`, `curl -X PATCH`, `git commit`
# would each turn the reviewer back into an author. A reviewer that can repair "because it's
# small" reviews its own repair on the next pass — the failure this project had four times.
#
# WHY IT ALSO BLOCKS THE TESTS: the CI run at the SHA is the gate. A second local run is a second
# truth, and when the two disagree nobody can say which one the merge was decided on.
#
# WHY IT LIVES HERE AND NOT IN THE AGENT'S FRONTMATTER: a gate registered in the file it guards
# disappears with one careless edit to that file. So the wiring stays in `settings.json`, and this
# script tests JSON on stdin, which means it can be proven to fire without spawning an agent.

set -uo pipefail

INPUT=$(cat)

field() {
  printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for key in sys.argv[1].split('.'):
    if not isinstance(d, dict):
        sys.exit(0)
    d = d.get(key)
    if d is None:
        sys.exit(0)
print(d if isinstance(d, str) else json.dumps(d))
" "$1" 2>/dev/null
}

# Everything below applies to exactly one role. Any other caller passes untouched.
[[ "$(field agent_type)" == "pr-pruefer" ]] || exit 0

TOOL=$(field tool_name)
case "$TOOL" in
  Bash|Read|Grep|Glob) ;;
  *) exit 0 ;;
esac

deny() {
  python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'deny',
    'permissionDecisionReason': sys.argv[1] + '  —  Fundstelle: ' + sys.argv[2],
}}))
"  "$1" "$2"
  exit 0
}

# ---------------------------------------------------------------------------------------------
# `.claude/metrics/` is the one place this reviewer may not read.
#
# WHY A READING RULE STANDS IN A GATE FULL OF WRITING RULES: the reviewer must not see the
# author's report — a reviewer who has read it checks inner consistency instead of outer
# correctness. Not passing the value along is only half of that: an earlier version of the
# metrics hook stored the raw hook input, including the developer's closing message verbatim, and
# an ordinary search over `.claude/` found it. The hook no longer stores it (absence beats a
# fence), but absence does not reach backwards to lines already on disk — this rule covers those.
#
# FORM, NEVER CONTENT: the rule judges the *path*, never what stands in the file, and it must catch
# `.claude/metrics/` and nothing else. Each tool is read where it names its target:
#   * `Read`  — `file_path`.
#   * `Glob`  — `pattern` AND `path`: a glob pattern *is* a path.
#   * `Grep`  — `path` and `glob`, but NOT `pattern`: the pattern says *what* to look for.
#   * `Bash`  — the command line, three rules further down.
METRICS_GRUND="\`.claude/metrics/\` liest der Prüfer nicht: dort kann der Abschlussbericht des \`entwickler\` liegen, und der wird ihm nicht weitergereicht — sonst prüft er innere Stimmigkeit statt äußerer Richtigkeit. Suchst du nach der Zeichenkette, setz sie in Anführungszeichen: dann ist sie ein Muster und kein Ort."
METRICS_FUNDSTELLE="Prozess → „Lauf\""

case "$TOOL" in
  Read) ZIEL=$(field tool_input.file_path) ;;
  Glob) ZIEL="$(field tool_input.pattern) $(field tool_input.path)" ;;
  Grep) ZIEL="$(field tool_input.path) $(field tool_input.glob)" ;;
  *)    ZIEL="" ;;
esac

if [[ "$ZIEL" == *".claude/metrics"* ]]; then
  deny "$METRICS_GRUND" "$METRICS_FUNDSTELLE"
fi

# A rule for a `Grep` rooted at `.claude` stood here until it was measured that the tool's search
# engine skips git-ignored directories unless the ignored path itself is the search root — which
# the path rule above already catches. A rule whose condition never fires is dead code the next
# reader mistakes for protection, so it went.

# Everything below reads a command line, so it is Bash and nothing else.
[[ "$TOOL" == "Bash" ]] || exit 0

CMD=$(field tool_input.command)
[[ -n "$CMD" ]] || exit 0
FLAT=$(printf '%s' "$CMD" | tr '\n\t' '  ' | tr -s ' ')

# Normalise before testing. Both substitutions exist because a review caught this gate firing on
# commands that write nothing at all:
#   1. Quoted spans become empty: `grep -n "git commit" datei.md` is a search, not a commit.
#   2. Redirects to /dev/null and `2>&1` disappear: `git diff origin/dev...<sha> 2>/dev/null` is
#      the reviewer's own bread and butter. This one bit the reviewer during its very first review.
SAFE=$(printf '%s' "$FLAT" | python3 -c "
import re, sys
s = sys.stdin.read()
s = re.sub(r'2>&1|&>\s*/dev/null|[0-9]?>\s*/dev/null', ' ', s)
s = re.sub(r'\"[^\"]*\"', ' \"\" ', s)
s = re.sub(r\"'[^']*'\", \" '' \", s)
sys.stdout.write(s)
" 2>/dev/null)
[[ -n "$SAFE" ]] || SAFE="$FLAT"

# --- The same one forbidden read, on a command line -------------------------------------------
# 1. As an operand, verb-agnostic, on `$SAFE` — a list of verbs would be missing the next one.
if [[ "$SAFE" == *".claude/metrics"* ]]; then
  deny "$METRICS_GRUND" "$METRICS_FUNDSTELLE"
fi

# 2. Quoted, behind a verb for which *every* argument is a path, on the raw command. Quoting does
#    not launder a path.
if [[ "$FLAT" =~ (^|[;&|]|\ )(cat|less|more|head|tail|bat|xxd|od|nl|strings|wc|jq)\ [^\;\&\|]*\.claude/metrics ]]; then
  deny "$METRICS_GRUND" "$METRICS_FUNDSTELLE"
fi

# 3. A recursive search whose root is `.claude`: POSIX grep knows no ignore file. The way out is
#    named in the message — name the subdirectory, or exclude `metrics`.
SWEEPS_CLAUDE=false
if [[ "$SAFE" =~ (^|[;&|]|\ )(grep|egrep|fgrep)\ [^\;\&\|]*(-[A-Za-z]*[rR][A-Za-z]*|--recursive|--dereference-recursive)[^\;\&\|]*[[:space:]][^[:space:]\;\&\|]*\.claude/?($|[[:space:];\&\|]) ]]; then
  SWEEPS_CLAUDE=true
fi
if [[ "$SAFE" =~ (^|[;&|]|\ )(rg|ag|ack)\ [^\;\&\|]*[[:space:]][^[:space:]\;\&\|]*\.claude/?($|[[:space:];\&\|]) ]]; then
  SWEEPS_CLAUDE=true
fi
if [[ "$SWEEPS_CLAUDE" == true ]] && [[ ! "$SAFE" =~ exclude(-dir)?=?[^[:space:]]*metrics ]]; then
  deny "Ein rekursiver Lauf über \`.claude\` liest \`.claude/metrics/\` mit. Nenne das Unterverzeichnis, das du meinst, oder schließ \`metrics\` aus (\`--exclude-dir=metrics\`)." \
       "$METRICS_FUNDSTELLE"
fi

# Writing GitHub state: the verdict is a return value; merge.sh posts it.
if [[ "$SAFE" =~ curl\ [^\;\&\|]*-X\ ?(POST|PATCH|PUT|DELETE) ]] \
   || [[ "$SAFE" =~ curl\ [^\;\&\|]*--request\ ?(POST|PATCH|PUT|DELETE) ]]; then
  deny "Der Prüfer schreibt nichts, auch nicht an GitHub. Das Urteil ist ein Rückgabewert; gepostet wird es von \`merge.sh\`." \
       "Prozess → „Prüfung\""
fi

# The same rule through the wrapper. A gate that only knows the old spelling of a command is no
# gate the day the spelling changes.
if [[ "$SAFE" =~ gh-api\.sh[[:space:]]+(POST|PATCH|PUT|DELETE|post|patch|put|delete) ]]; then
  deny "Der Prüfer schreibt nichts, auch nicht durch \`gh-api.sh\`. Lesen (\`GET\`) ist sein ganzes Werkzeug; das Urteil postet \`merge.sh\`." \
       "Prozess → „Prüfung\""
fi

# Writing the repository: a reviewer with a commit is an author.
#
# `pull` is here although it does not "write": it is `fetch` plus `merge`, and the reviewer has no
# worktree of its own, so it would move HEAD in a directory it does not own. `fetch` stays open.
#
# ONLY OPTION-SHAPED TOKENS MAY STAND BETWEEN `git` AND THE VERB: `git -C /other/tree reset --hard`
# must be caught, while `git branch -d pull` or `git log --grep="pull request"` is work and must
# pass. A rule that catches too much is worse than no rule.
if [[ "$SAFE" =~ (^|[;&|]|\ )git(\ -[cC]\ [^\ \;\&\|]+|\ -[^\ \;\&\|]+)*\ (add|commit|push|merge|pull|switch|stash|restore|reset|rebase|cherry-pick|tag)($|[[:space:];\&\|]) ]]; then
  deny "Der Prüfer ändert den Diff nicht. Wer schreiben darf, prüft am Ende die eigene Reparatur." \
       "Prozess → „Prüfung\""
fi

# In-place editing through the shell, which is what `Write`/`Edit` were left out to prevent.
if [[ "$SAFE" =~ (^|[;&|]|\ )(sed\ [^\;\&\|]*-i|tee|dd)($|[[:space:]]) ]] \
   || [[ "$SAFE" =~ \>\ ?[A-Za-z0-9_./-]+ ]]; then
  deny "Schreiben über die Shell umgeht die Tool-Allowlist, die \`Write\` und \`Edit\` genau deshalb weglässt." \
       "Prozess → „Prüfung\""
fi

# A second test run is a second truth; the gate is the CI run at the SHA.
if [[ "$SAFE" =~ (^|[;&|]|\ )(uv\ run\ )?pytest($|[[:space:]]) ]] \
   || [[ "$SAFE" =~ (^|[;&|]|\ )(npm|npx|vitest|tsc)($|[[:space:]]) ]]; then
  deny "Der Prüfer führt keine Tests aus. Was CI und die Suite prüfen, wird nicht noch einmal geprüft — ein zweiter Lauf wäre eine zweite Wahrheit." \
       "Prozess → „Prüfung\""
fi

exit 0
