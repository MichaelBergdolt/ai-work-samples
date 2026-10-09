#!/usr/bin/env bash
# Adapted excerpt from a private project
#
# EXCERPT. The original is ~900 lines (52 KB). Kept here: why the gate exists, the promise it
# makes, and the skeleton of its nine steps. Omitted: dependency linking, test-schema handling,
# the per-run log, signal handling and the exact test commands. Lines marked `# …` stand for
# omitted code; this file is meant to be read, not run.
#
# The merge gate of every agent PR, run locally instead of at GitHub.
#
# WHY IT EXISTS: the hosted CI quota covers only a fraction of the PR runs an agent day produces.
# Agent PRs therefore carry `<!-- gate: lokal -->` in their body, CI skips them, and this script
# is their gate. PRs opened by hand still run at GitHub.
#
# WHAT IT IS NOT: a second version of the CI file. That file stays authoritative, and the
# commands are copied from it — including the step that proves the integration tests did not
# skip themselves. Only the place of execution changes.
#
# THE THROWAWAY WORKTREE IS THE PROMISE, NOT A DETAIL. A run in whatever tree happens to be open
# answers "are the tests green here and now", which is the question the author already answered.
# The question a gate asks is: does this run belong to *this* commit? Here that is a detached
# worktree created on the SHA and verified afterwards. If it cannot be created on that SHA, this
# is a LOUD ABORT and never a skipped step.
#
# AND IT IS A TREE THAT NEVER HOLDS A SECRET. `mktemp -d` is outside the repository: no
# `.gitignore`, no hook, and its removal hangs on a trap that SIGKILL does not run. So the token
# file is not copied there at all.
#
# THE RESULT GOES TO GITHUB AS A COMMIT STATUS, posted BY THIS SCRIPT, not by the agent that
# called it: a result the caller types in by hand is the caller's claim about a run.
#
# AND THE RUN LEAVES A TRACE THAT OUTLIVES IT. Every run writes its own log, and a `success` that
# replaces a `failure` at the same SHA is announced out loud — otherwise a flaky test goes green
# by being repeated, and nothing is left to read afterwards.
#
# WHO RUNS IT: the orchestrator, between step 6 and step 7 — not the entwickler, whose own claim
# it would be, and not the pr-pruefer, who runs no tests and may not write.
#
# EXIT CODES: 0 green and posted · 1 red · 2 usage · 3 the gate could not run on that SHA ·
#             130/143 stopped by a signal, posted as error

set -uo pipefail

sag()  { printf 'lokaler-lauf: %s\n' "$1" >&2; }
raus() { sag "$1"; exit "${2:-2}"; }

# 1. The SHA, in full. A short one is refused rather than expanded: the status is filed under the
#    40 characters GitHub knows, and the run and the commit must not drift apart.
SHA="${1:-}"
[[ -n "$SHA" ]] || raus "Aufruf: lokaler-lauf.sh <sha> — der volle head.sha des PR, 40 Hexziffern."
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || raus "'$SHA' ist kein voller SHA. Erwartet werden 40 Hexziffern."

# 2. The main checkout, derived from `--git-common-dir`, never written down.        # …
# 3. Does the commit exist here at all? Asked before anything is created.            # …
# 4. `beenden <state> <exit> <text>`: every exit from here on posts a commit status
#    (`POST /statuses/<sha>`, context `lokaler-lauf`) and then exits.                # …

# 5. The throwaway worktree, under `mktemp -d`, removed by a trap on every path.
ELTERN=$(mktemp -d) || raus "mktemp fehlgeschlagen." 3
BAUM="$ELTERN/lauf"
aufraeumen() {
  # … drop this run's own test schema, if this run created it
  git -C "$HAUPT" worktree remove --force "$BAUM" >/dev/null 2>&1
  git -C "$HAUPT" worktree prune >/dev/null 2>&1
  rm -rf "$ELTERN"
}
trap aufraeumen EXIT

git -C "$HAUPT" worktree add --detach "$BAUM" "$SHA" >/dev/null 2>&1 \
  || beenden error 3 "Wegwerf-Worktree auf $SHA nicht anlegbar — es wurde nichts geprueft."

# The promise, read back instead of assumed.
STEHT=$(git -C "$BAUM" rev-parse HEAD 2>/dev/null)
[[ "$STEHT" == "$SHA" ]] \
  || beenden error 3 "Der Arbeitsbaum steht auf ${STEHT:-nichts} statt auf $SHA — der Lauf wuerde zu einem anderen Commit gehoeren."

# 6. Dependencies: linked read-only from the main checkout, or installed from the lockfile
#    when the PR changes it.                                                         # …
# 7. A test schema per run (named after the PID, dropped in the trap): two overlapping gate
#    runs on one schema took each other apart and showed up as a false red.         # …

# 8. The commands, in the CI file's order. Each step's output goes to stderr and to the log.
ROT=""
# schritt backend   …   (unit + integration tests; then a check that integration tests did not skip)
# schritt frontend  …   (lint, type check, tests)
# schritt build     …

# 9. The verdict — a comparison, not a judgement.
if [[ -n "$ROT" ]]; then
  beenden failure 1 "rot: $ROT (lokaler Lauf am $SHA)"
fi
beenden success 0 "Tests, Integrationstests, Frontend-Pruefung und Build gruen am $SHA"
