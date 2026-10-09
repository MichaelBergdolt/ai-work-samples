#!/usr/bin/env bash
# Adapted excerpt from a private project
#
# PreToolUse gate on Bash, for every agent and the main session.
#
# WHY THIS EXISTS AT ALL: all of the command forms blocked here were already written down as
# rules in CLAUDE.md when they did their damage. A rule in a system prompt is a request; four
# agents would be four chances to forget it.
#
# WHAT IT MAY AND MAY NOT DO: it checks *form*, never content. Layer violations, lock order,
# a second purpose in a branch — those are judgement calls and belong to the pr-pruefer.
# This script must stay a set of string tests with no opinion, because a gate with discretion
# is not a gate.
#
# CONTRACT: reads the PreToolUse hook JSON on stdin, prints a deny decision as JSON and exits 0,
# or exits 0 silently to let the normal permission flow decide. Exit 2 is deliberately NOT used:
# it blocks whether or not JSON is printed, which would swallow the reason — and a gate whose
# message nobody sees is the failure mode this repo keeps hitting.
#
# HOW THE SECOND GATE FINDS ITS AGENT: the input carries `agent_type` inside a subagent call, so
# one script can serve every role. See pr-pruefer-guard.sh.

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

TOOL=$(field tool_name)
[[ "$TOOL" == "Bash" ]] || exit 0

CMD=$(field tool_input.command)
[[ -n "$CMD" ]] || exit 0
CWD=$(field cwd)

deny() {
  # $1 = rule, $2 = where it is written down
  python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'deny',
    'permissionDecisionReason': sys.argv[1] + '  —  Fundstelle: ' + sys.argv[2],
}}))
" "$1" "$2"
  exit 0
}

# Collapse whitespace so `git   add    -A` and a line continuation read like the plain form.
FLAT=$(printf '%s' "$CMD" | tr '\n\t' '  ' | tr -s ' ')

# Then empty out quoted spans, because otherwise the gate reads prose as a command. This is not
# hypothetical: the commit that fixed the other gate carried the sentence `git push origin
# HEAD:refs/heads/dev` in its message as the defect being described, and this gate refused to let
# it be committed.
#
# THE ONE EXCEPTION: a quoted string is prose *unless* something executes it. `bash -c
# "git push --force origin dev"` is the real thing wearing quotes, so an interpreter invocation is
# tested raw.
if [[ "$FLAT" =~ (^|[;&|]|\ )(bash|sh|zsh|dash|ksh)\ +-[a-z]*c($|[[:space:]]) ]] \
   || [[ "$FLAT" =~ (^|[;&|]|\ )eval($|[[:space:]]) ]]; then
  # Keep every character, but turn the quotes themselves into spaces (\042 is ", \047 is ').
  SAFE=$(printf '%s' "$FLAT" | tr '\042\047' '  ')
else
  SAFE=$(printf '%s' "$FLAT" | python3 -c "
import re, sys
s = sys.stdin.read()
s = re.sub(r'\"[^\"]*\"', ' \"\" ', s)
s = re.sub(r\"'[^']*'\", \" '' \", s)
sys.stdout.write(s)
" 2>/dev/null)
  # If python is unavailable the gate must still bite: fall back to the raw command, which is
  # stricter, not looser.
  [[ -n "$SAFE" ]] || SAFE="$FLAT"
fi

# A third version, for the rules that must keep reading quoted text. `$FLAT` turns every newline
# into a space, and a rule anchored on "a separator or a space" then reads a whole multi-line
# command as one statement. What is missing is not quoting, it is *boundaries*:
#
#   * A newline outside quotes ends a statement; inside quotes it does not.
#   * A heredoc body is an argument, not shell — unless a shell is what reads it.
#
# Both are still form, never content.
LEAK=$(printf '%s' "$CMD" | python3 -c "
import re, sys

s = sys.stdin.read()

# A backslash before the newline is a line continuation: one statement written over two lines.
s = re.sub(r'\\\\\n', ' ', s)

# Cut the heredoc bodies a shell does not run.
here = re.compile(r'<<-?[ \t]*([\"\']?)([A-Za-z_][A-Za-z0-9_]*)\1')
shell = re.compile(r'(^|[;&|]|[ \t])(bash|sh|zsh|dash|ksh)([ \t]|$)')
lines, kept, i = s.split('\n'), [], 0
while i < len(lines):
    line = lines[i]
    kept.append(line)
    i += 1
    found = here.search(line)
    if not found:
        continue
    body = []
    while i < len(lines) and lines[i].strip() != found.group(2):
        body.append(lines[i])
        i += 1
    i += 1                      # step over the terminator itself
    if shell.search(line):
        kept.extend(body)       # a shell reads this body, so it is code after all
s = '\n'.join(kept)

# A newline outside quotes is a statement separator; inside quotes it is just a character.
out, quote = [], None
for ch in s:
    if quote is not None:
        out.append(' ' if ch == '\n' else ch)
        if ch == quote:
            quote = None
    elif ch == '\"' or ch == chr(39):
        quote = ch
        out.append(ch)
    else:
        out.append(';' if ch == '\n' else ch)

sys.stdout.write(''.join(out))
" 2>/dev/null | tr '\t' ' ' | tr -s ' ')
[[ -n "$LEAK" ]] || LEAK="$FLAT"

# ---------------------------------------------------------------------------
# 1. `git add` that sweeps the tree.
#    `git add -A` once pulled another session's half-finished files into a foreign commit.
# ---------------------------------------------------------------------------
if [[ "$SAFE" =~ (^|[;&|]|\ )git\ add\ (-A|--all|-a|\.)($|[[:space:];&|]) ]]; then
  deny "git add sammelt hier den ganzen Baum ein. Namentlich stagen, dann \`git diff --cached --stat\` gegen die eigene Änderungsliste halten." \
       "Prozess → „Ein Arbeitsbaum je Sitzung\""
fi

# ---------------------------------------------------------------------------
# 2. Force-push, and any direct push to dev or main at all.
#    dev and main are delivered by the process, not by a push: dev only through the squash-merge
#    of `merge.sh` (an API call, not a push), main only by a human.
# ---------------------------------------------------------------------------
if [[ "$SAFE" =~ (^|[;&|]|\ )git\ push\  ]]; then
  # Three spellings, and the third one is the reason this is a single test:
  # `git push origin HEAD:refs/heads/dev` reads nothing like `git push origin dev`.
  TARGETS_PROTECTED=false
  if [[ "$SAFE" =~ git\ push\ ([^\;\&\|]*\ )?(origin\ )?(dev|main)($|[[:space:]]) ]] \
     || [[ "$SAFE" =~ git\ push[^\;\&\|]*:(refs/heads/)?(dev|main)($|[[:space:]]) ]] \
     || [[ "$SAFE" =~ git\ push[^\;\&\|]*\ \+[A-Za-z0-9_/.:^~-]*(dev|main)($|[[:space:]]) ]]; then
    TARGETS_PROTECTED=true
  fi

  if [[ "$TARGETS_PROTECTED" == true ]]; then
    # `+ref` is force-push spelled as a refspec and reads like an ordinary push.
    if [[ "$SAFE" =~ (--force|--force-with-lease|\ -f($|[[:space:]])) ]] \
       || [[ "$SAFE" =~ git\ push[^\;\&\|]*\ \+[A-Za-z0-9_/.:^~-]*(dev|main)($|[[:space:]]) ]]; then
      deny "Force-Push auf \`dev\` oder \`main\`, gegebenenfalls als \`+<ref>\` geschrieben. Beide werden nur vom Prozess beliefert — \`dev\` per Squash-Merge, \`main\` von einem Menschen." \
           "Prozess → „Der Weg vom Issue zum gemergten dev\""
    fi
    deny "Direkter Push auf \`dev\`/\`main\`, in welcher Refspec-Schreibweise auch immer. Nach \`dev\` liefert nur der Squash-Merge aus \`.claude/bin/merge.sh\`, nach \`main\` nur ein Mensch." \
         "Prozess → „Der Weg vom Issue zum gemergten dev\", Schritt 8"
  fi
fi

# ---------------------------------------------------------------------------
# 3. `--admin` on a merge: the documented way past a failing check.
# ---------------------------------------------------------------------------
if [[ "$SAFE" =~ --admin ]] && [[ "$SAFE" =~ (merge|pulls/[0-9]+) ]]; then
  deny "\`--admin\` geht an einem fehlgeschlagenen Check vorbei. Rot heißt melden, was rot ist." \
       "Prozess → „Der Weg vom Issue zum gemergten dev\", Schritt 8"
fi

# WHICH VERSION EACH RULE READS, AND WHY IT IS NOT ONE ANSWER:
#   * `$SAFE` (quotes emptied) for rules about the *shape of a command*.
#   * `$FLAT` (raw) for rules whose payload is a *secret or a path*: `echo "$TOKEN"` is quoted and
#     still a leak; `rm -rf ".claude/worktrees"` is quoted and still deletes every parallel session.
#   * `$LEAK` (raw, but with statement boundaries and without heredoc bodies a shell never runs)
#     for the token rules below.
# ---------------------------------------------------------------------------
# 4. The token leaving its variable: never in a URL, never through `echo`, never printed.
#    Reading the file into a variable (`TOKEN=$(tr -d '\r\n' < .gh_token)`) passes untouched.
# ---------------------------------------------------------------------------
if [[ "$LEAK" =~ https?://[^/@[:space:]]*(\$|ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[^/@[:space:]]*@github\.com ]] \
   || [[ "$LEAK" =~ https?://[^/@[:space:]]{20,}@github\.com ]]; then
  deny "Der Token gehört nie in eine URL — die steht in der Shell-History und in jedem Log. In eine Variable lesen, von dort in den \`Authorization\`-Header." \
       "Prozess → „Die Anmeldung an GitHub\""
fi
if [[ "$LEAK" =~ (^|[;&|]|\ )(echo|printf)\ [^\;\&\|]*\$\{?(TOKEN|GH_TOKEN|GITHUB_TOKEN) ]]; then
  deny "Der Token wird nie geechot — die Ausgabe landet im Transkript und im Log." \
       "Prozess → „Die Anmeldung an GitHub\""
fi
if [[ "$LEAK" =~ (^|[;&|]|\ )(cat|less|more|head|tail|bat|xxd|od)\ [^\;\&\|]*\.gh_token ]]; then
  deny "\`.gh_token\` wird nicht ausgegeben, nur gelesen: \`TOKEN=\$(tr -d '\\r\\n' < .gh_token)\`." \
       "Prozess → „Die Anmeldung an GitHub\""
fi
# Only the *unfiltered* dump. `printenv | grep <NAME>` is the sanctioned form; `env VAR=x cmd` is a
# prefix, not a dump; `set -euo pipefail` is not a dump at all.
if [[ "$LEAK" =~ (^|[;&|]|\ )(printenv|env)[[:space:]]*($|\;|&&) ]]; then
  deny "Ein ungefiltertes \`printenv\`/\`env\` schreibt jedes Geheimnis der Umgebung ins Transkript. Nach dem einen Namen filtern, den du brauchst — \`printenv | grep <NAME>\` geht durch." \
       "Prozess → „Die Anmeldung an GitHub\""
fi

# ---------------------------------------------------------------------------
# 5. Deleting the worktree directory: every parallel session lives under there.
#    `git worktree remove <pfad>` removes exactly one and refuses when it is dirty; `rm -r` does not.
# ---------------------------------------------------------------------------
if [[ "$FLAT" =~ (^|[;&|]|\ )rm\ [^\;\&\|]*-[a-zA-Z]*r[a-zA-Z]*\ [^\;\&\|]*\.claude/worktrees ]]; then
  deny "\`rm -r\` auf \`.claude/worktrees\` nimmt jede parallele Sitzung mit, auch die mit ungepushten Commits. Einzeln mit \`git worktree remove <pfad>\`." \
       "Prozess → „Ein Arbeitsbaum je Sitzung\""
fi

# ---------------------------------------------------------------------------
# 6. Switching branches in the main checkout.
#    A checkout has one HEAD, one index and one set of checked-out refs. Two sessions in it share
#    all three without noticing. A worktree is recognised by git itself, not by its path: inside
#    one, `--git-dir` points at `.git/worktrees/<name>` while `--git-common-dir` stays at `.git`.
# ---------------------------------------------------------------------------
if [[ "$SAFE" =~ (^|[;&|]|\ )git\ (switch|checkout)\  ]] \
   && [[ ! "$SAFE" =~ git\ (switch|checkout)\ (--|-)?[^\;\&\|]*(\.|--\ ) ]]; then
  DIR=$(cd "${CWD:-.}" 2>/dev/null && git rev-parse --git-dir 2>/dev/null)
  COMMON=$(cd "${CWD:-.}" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)
  if [[ -n "$DIR" && "$(cd "${CWD:-.}" && cd "$DIR" 2>/dev/null && pwd)" == "$(cd "${CWD:-.}" && cd "$COMMON" 2>/dev/null && pwd)" ]]; then
    deny "Branch-Wechsel im Hauptcheckout. Jede Sitzung nimmt zuerst ihren eigenen Arbeitsbaum; im Hauptcheckout teilen zwei Sitzungen HEAD, Index und ausgecheckte Refs, ohne es zu merken." \
         "CLAUDE.md → „Ein Arbeitsbaum je Sitzung\""
  fi
fi

# A rule 7 used to stand here: it took `git pull` and `git stash` away from the `merge-waechter`.
# That agent is a script now, the rule's condition can never match, and a rule whose condition
# never matches is dead code the next reader mistakes for protection. It was removed; the script
# simply does not contain the two verbs, and a test holds that. Structurally absent beats fenced.

exit 0
