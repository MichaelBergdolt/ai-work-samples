#!/usr/bin/env bash
# Adapted excerpt from a private project
#
# EXCERPT. The original is ~1 200 lines (67 KB). Kept here: the reason it exists, the five merge
# conditions, and the merge path with its post-merge checks. Omitted: argument parsing, the
# `rueckmeldung`/`abbruch`/`sync` modes, the branch cleanup (`aufraeumen`) and its helpers.
# Lines marked `# …` stand for omitted code; this file is meant to be read, not run.
#
# Steps 8 and 9 — the squash-merge and the tidying up — as a script instead of an agent.
#
# WHY THIS REPLACED AN AGENT: the merge-waechter made no decision. His own prompt said so
# ("Ermessen ist dir verboten"), and all of his tasks were comparisons, one merge call, four
# handholds and passing the reviewer's verdict through unchanged. Measured he still cost like a
# thinking agent: 13.4 % of the agent load over three runs, and in one run more turns than the
# reviewer. Worse, he got a *green* PR wrong: his condition 3 demanded
# `mergeable_state == "clean"`, and the state a PR has with the local gate is `"unstable"`. In a
# script that condition is a test, and the incident could not have happened.
# Discretion gets a model; comparisons get code.
#
# WHAT IT DOES NOT DO, AND THAT IS THE POINT: it judges nothing about content. The pr-pruefer's
# verdict arrives as a file and is posted verbatim. The English sentence in the squash subject
# arrives as an argument, because translating an issue title is exactly the kind of judgement a
# comparison cannot make; this script checks its *form* and never its wording.
#
# A FAILURE IS LOUD. Skipping quietly is the failure shape that produced this script in the first
# place: every single step looked healthy.
#
# WHERE IT RUNS: in the main checkout, derived from `--git-common-dir` rather than written down.
# It never runs `git` inside a foreign worktree, and it contains neither `git pull` nor
# `git stash` — a test against this file holds that.
#
# USAGE
#   merge.sh merge        --issue <n> --pr <n> --betreff <s> --urteil-datei <f>
#   merge.sh rueckmeldung --pr <n> --urteil-datei <f>
#   merge.sh abbruch      --issue <n> --grund <s> --entscheidung-datei <f> [--branch <b>]
#   GH_API_DRY_RUN=1 passes through to `gh-api.sh`: everything runs, nothing is written.
#
# EXIT CODES: 0 done · 1 reported and not merged (reason on stdout) · 2 usage · 3 the step could
# not run at all

set -uo pipefail

sag()  { printf 'merge: %s\n' "$1" >&2; }
grund(){ printf '%s\n' "$1"; }
raus() { sag "$1"; exit "${2:-2}"; }
# … locating the main checkout ($HAUPT), the API wrapper ($WRAPPER), argument parsing,
# … urteil_lesen, urteil_posten, abbruch_spur, ziel_aus_issue, aufraeumen

# ---------------------------------------------------------------------------
# The five conditions. Each one is a comparison and prints its reason when it fails.
# ---------------------------------------------------------------------------
bedingungen_pruefen() {
  ISSUE="$1" URTEIL="$2" PRJ="$3" STATUSJ="$4" CHECKSJ="$5" ZIEL="${6:-dev}" python3 <<'PYEOF'
import json, os, re, sys


def lade(pfad):
    if not pfad:
        return None
    try:
        with open(pfad) as datei:
            return json.load(datei)
    except (OSError, ValueError) as fehler:
        print(f'{pfad} ist nicht lesbar oder kein JSON: {fehler}')
        sys.exit(1)


issue = os.environ['ISSUE']
ziel = os.environ['ZIEL']
urteil = os.environ['URTEIL']
pr = lade(os.environ['PRJ'])
status = lade(os.environ['STATUSJ'])
checks = lade(os.environ['CHECKSJ'])

if pr is None:
    print('Kein PR-JSON — ohne den PR ist keine der fuenf Bedingungen pruefbar.')
    sys.exit(1)

# 1 — the reviewer's verdict, passed through rather than re-formed.
if urteil != 'ok':
    print(f'Urteil des pr-pruefer ist "{urteil}", nicht "ok".')
    sys.exit(1)

# 2 — green at the head.sha.
kopf = (pr.get('head') or {}).get('sha') or ''
if not kopf:
    print('Der PR nennt keinen head.sha.')
    sys.exit(1)

MARKE = '<!-- gate: lokal -->'
gate_lokal = MARKE in (pr.get('body') or '')

lokaler = None
if status and gate_lokal:
    if status.get('sha') and status['sha'] != kopf:
        print(f'Der Commit-Status gehoert zu {status["sha"]}, der PR steht auf {kopf} — '
              f'ein Lauf an einem anderen Commit ist keiner.')
        sys.exit(1)
    for eintrag in status.get('statuses') or []:
        if eintrag.get('context') == 'lokaler-lauf':
            lokaler = eintrag.get('state')
            break

laeufe = [] if gate_lokal else ((checks or {}).get('check_runs') or [])
for lauf in laeufe:
    if lauf.get('head_sha') and lauf['head_sha'] != kopf:
        print(f'Ein Check-Run haengt an {lauf["head_sha"]}, der PR steht auf {kopf} — '
              f'ein gruener Lauf an einem aelteren Commit ist keiner.')
        sys.exit(1)

if lokaler is not None:
    beleg = 'lokaler-lauf'
    if lokaler != 'success':
        print(f'Der Commit-Status "lokaler-lauf" steht am {kopf} auf "{lokaler}", nicht auf '
              f'"success".')
        sys.exit(1)
elif laeufe:
    beleg = 'check-runs'
    rot = [l.get('name', '?') for l in laeufe if l.get('conclusion') != 'success']
    if rot:
        print(f'Rot am {kopf}: {", ".join(rot)}.')
        sys.exit(1)
else:
    gesucht = 'kein Commit-Status "lokaler-lauf"' if gate_lokal else 'kein Check-Run'
    print(f'Am {kopf} haengt {gesucht} — '
          f'nicht gelaufen. Das ist ein Grund zu melden, nie einer zu mergen.')
    sys.exit(1)

# 3 — the mergeable state. Written over the conflict, not over the blessing, and not bound to
# who ran the tests (this is the condition the agent version got wrong).
zustand = pr.get('mergeable_state')
if zustand == 'dirty':
    print('mergeable_state ist "dirty" — das ist ein Konflikt, kein haengendes CI. `dev` hat '
          'sich unter dem PR bewegt. Nicht warten, es kommt nichts.')
    sys.exit(1)
mergbar = pr.get('mergeable')
if mergbar is not True:
    print(f'mergeable ist "{mergbar}" und nicht true (mergeable_state "{zustand}") — GitHub hat '
          f'die Mergbarkeit nicht bestaetigt. Ein Zustand, den niemand berechnet hat, ist kein '
          f'gruener.')
    sys.exit(1)

# 4 — the PR closes its own issue. A line of its own, not a substring: a PR whose prose merely
# mentioned another issue's "Closes" line once passed here and closed that issue half-done.
rumpf = pr.get('body') or ''
if not re.search(rf'(?m)^[ \t]{{0,3}}Closes #{re.escape(issue)}\b', rumpf):
    print(f'Der PR-Body enthaelt "Closes #{issue}" nicht — ohne die Zeile fehlt der Weg vom PR '
          f'zum Issue und zurueck.')
    sys.exit(1)

# 5 — the base is the target. A stacked PR does not merge into its target: GitHub rehangs the
# base of an open PR only when the base branch is DELETED, and until then the squash writes onto
# the base, where the tidying up throws it away. Two of seven squash commits vanished that way in
# one day — the merge API answered 200 and the PR stood on `merged`.
basis = (pr.get('base') or {}).get('ref')
if basis != ziel:
    print(f'base.ref ist "{basis}", nicht "{ziel}" — ein gestapelter PR mergt nicht nach '
          f'`{ziel}`, der Squash landet auf der Basis und wird beim Aufraeumen weggeworfen.')
    sys.exit(1)

print(f'alle fuenf Bedingungen erfuellt (Gruen-Beleg: {beleg}, Ziel: {ziel})')
PYEOF
}

# ---------------------------------------------------------------------------
# `merge` — step 8 and the four handholds of step 9.
# ---------------------------------------------------------------------------
[[ -n "$ARG_issue" && -n "$ARG_pr" ]] || raus "merge erwartet --issue <nr> --pr <nr>."
[[ -n "$ARG_betreff" ]] || raus "merge erwartet --betreff <satz>. Der englische Satz ist eine Übersetzung des Issue-Titels und kommt vom Aufrufer — ein Skript übersetzt nicht."
[[ -n "$ARG_urteil_datei" ]] || raus "merge erwartet --urteil-datei <datei> mit dem Urteil des pr-pruefer."
# … the verdict is read from the reviewer's own file; a missing verdict is a call error (exit 2)

# THE SUBJECT'S FORM, NEVER ITS WORDING. What the sentence says is the caller's judgement; that the
# issue number is in it is a comparison, and a comparison belongs here.
if [[ ! "$ARG_betreff" =~ ^(feat|fix|chore|docs):\ .+\ \(#${ARG_issue}\)$ ]]; then
  raus "Der Betreff '$ARG_betreff' hat nicht die Form \`<feat|fix|chore|docs>: <satz> (#$ARG_issue)\`."
fi

# FIRST THE TRACE, THEN THE ACTION. If the merge fails, it still has to be readable what it
# would have relied on.
urteil_posten "$ARG_pr" "$ARG_urteil_datei" \
  || { grund "Das Urteil ließ sich nicht als PR-Review posten — ohne die Spur wird nicht gemergt."; exit 1; }

PR_JSON=$("$WRAPPER" GET "/pulls/$ARG_pr") \
  || { grund "GET /pulls/$ARG_pr ist fehlgeschlagen."; exit 1; }

# `unknown` is lazy, not a conflict: GitHub computes mergeability asynchronously.
for _versuch in 1 2 3; do
  ZUSTAND=$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("mergeable_state") or "unknown"))')
  [[ "$ZUSTAND" != "unknown" ]] && break
  sleep 2
  PR_JSON=$("$WRAPPER" GET "/pulls/$ARG_pr") || break
done

SHA=$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("head") or {}).get("sha") or "")')
[[ -n "$SHA" ]] || { grund "Der PR #$ARG_pr nennt keinen head.sha."; exit 1; }

ARBEIT=$(mktemp -d) || raus "mktemp fehlgeschlagen." 3
trap 'rm -rf "$ARBEIT"' EXIT INT TERM
printf '%s' "$PR_JSON" > "$ARBEIT/pr.json"
"$WRAPPER" GET "/commits/$SHA/status"     > "$ARBEIT/status.json" 2>/dev/null
"$WRAPPER" GET "/commits/$SHA/check-runs" > "$ARBEIT/checks.json" 2>/dev/null
# … the issue must still be open; the target branch comes from the issue's milestone ($ZIEL)

if ! BEFUND=$(bedingungen_pruefen "$ARG_issue" "$ARG_urteil" "$ARBEIT/pr.json" "$ARBEIT/status.json" "$ARBEIT/checks.json" "$ZIEL"); then
  abbruch_spur "$ARG_issue" "$BEFUND"
  grund "$BEFUND"
  exit 1
fi
sag "$BEFUND"

# The merge itself. Squash and nothing else: the dev history is the list of issues.
MERGE_BODY=$(printf '{"merge_method": "squash", "commit_title": %s}' "$(json_escape "$ARG_betreff")")
MERGE_ANTWORT=$(printf '%s' "$MERGE_BODY" | "$WRAPPER" PUT "/pulls/$ARG_pr/merge" -) || {
  MELDUNG="PUT /pulls/$ARG_pr/merge hat nicht 200 geantwortet — es ist nichts gemergt worden."
  abbruch_spur "$ARG_issue" "$MELDUNG"
  grund "$MELDUNG"
  exit 1
}
MERGE_SHA=$(printf '%s' "$MERGE_ANTWORT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha") or "")')
[[ -n "$MERGE_SHA" ]] || { grund "Die Merge-Antwort nennt keinen SHA."; exit 1; }

# ---------------------------------------------------------------------------
# Handhold 1 — count back instead of believing the API, and read the SHAPE of the commit.
# GitHub once produced a real merge commit twice in one day although `squash` was sent, both
# times answering `merged: true`. A squash has exactly one parent; anything else stops here, the
# issue stays open and the branch stays standing for whoever repairs it by hand.
# ---------------------------------------------------------------------------
git -C "$HAUPT" fetch --prune >/dev/null 2>&1
ELTERN=$(git -C "$HAUPT" rev-list --parents -n 1 "$MERGE_SHA" 2>/dev/null | wc -w | tr -d ' ')
if [[ "$ELTERN" != "2" ]]; then
  MELDUNG="Der Merge-Commit $MERGE_SHA hat nicht genau einen Elternteil — GitHub hat einen echten Merge-Commit erzeugt, obwohl \`squash\` gesendet wurde. Kein Nachziehen."
  abbruch_spur "$ARG_issue" "$MELDUNG"
  grund "$MELDUNG"
  exit 1
fi

FERN_DEV=$(git -C "$HAUPT" ls-remote origin "refs/heads/$ZIEL" 2>/dev/null | awk '{print $1}')
if [[ "$FERN_DEV" != "$MERGE_SHA" ]]; then
  MELDUNG="\`git ls-remote origin $ZIEL\` nennt ${FERN_DEV:-nichts}, die Merge-Antwort $MERGE_SHA. Kein Aufräumen: ein gelöschter Branch nähme den Commit mit."
  abbruch_spur "$ARG_issue" "$MELDUNG"
  grund "$MELDUNG"
  exit 1
fi

# Handhold 2 — close the issue by hand: `Closes #<nr>` resolves only on a merge into the
# DEFAULT branch, and that is `main` here.
if printf '{"state": "closed"}' | "$WRAPPER" PATCH "/issues/$ARG_issue" - >/dev/null; then
  ISSUE_ZU=true
else
  ISSUE_ZU=false
fi

# Handhold 3 — worktree remove → branch -d (local, while the upstream still exists) → push
# --delete (remote) → worktree prune. The order is the point: the old order (remote first)
# made `branch -d` fail silently after every squash. `-D` stays forbidden.
BRANCH=$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("head") or {}).get("ref") or "")')
AUFGERAEUMT=true
AUF_BEFUND=$(aufraeumen "$BRANCH") || AUFGERAEUMT=false

# Handhold 4 — fetch and hold the remote ref against the merge SHA. No `pull`.
git -C "$HAUPT" fetch --prune >/dev/null 2>&1

if [[ "$AUFGERAEUMT" != true || "$ISSUE_ZU" != true ]]; then
  MELDUNG="Gemergt als $MERGE_SHA, aber das Nachziehen ist unvollständig (Issue geschlossen: $ISSUE_ZU, Branch aufgeräumt: $AUFGERAEUMT). ${AUF_BEFUND:-}"
  abbruch_spur "$ARG_issue" "$MELDUNG" befund
  grund "$MELDUNG"
  exit 1
fi

grund "gemergt als $MERGE_SHA nach $ZIEL, Issue #$ARG_issue geschlossen, $BRANCH remote und lokal gelöscht"
exit 0
