---
# Adapted excerpt from a private project
name: prozess-die-anmeldung-an-github
description: >-
  Wie ein Aufruf an GitHub aussieht: gh-api.sh, die Schreib-Allowlist und der Token aus einer gitignorierten Datei.
metadata:
  abschnitt: "Die Anmeldung an GitHub"
  reihenfolge: 4
---

## Die Anmeldung an GitHub

**Der Zugang zu Issues, PRs und Labels kommt aus `.gh_token`** im Repo-Wurzelverzeichnis — ein
PAT mit Scope `repo`, gitignored und nie eingecheckt. Gelesen wird der Token **nicht von Hand**:
jeder Aufruf geht durch einen Wrapper, der ihn selbst liest.

```bash
.claude/bin/gh-api.sh <METHOD> <PFAD> [JSON | @DATEI | -]
.claude/bin/gh-api.sh POST /issues/<nr>/assignees '{"assignees":["<login>"]}'
```

**Nie in die URL** — die steht in der Shell-History und in jedem Log —, nie durch `echo`, nie in
eine Commit-Message, einen Issue- oder PR-Body. **Der Wrapper macht diese Regel strukturell
unhaltbar-falsch statt sie zu wiederholen:** der Token geht durch kein Argument, Host und Repo
sind verdrahtet, und ein URL-artiger Pfad wird **abgelehnt statt repariert**. Vier Dinge dazu:

- **`GET` ist frei, geschrieben wird nur auf dreizehn Pfadformen** — die, die die neun Schritte
  brauchen; `DELETE` hat gar keine, und **kein Unterpfad einer erlaubten Form ist erlaubt**, denn
  darunter läge das Entfernen fremder Arbeit. **Die Liste steht als `WRITE_ALLOWLIST`
  im Skript**, weil eine Berechtigungsregel Argumente nicht einschränken kann; **fehlt eine Form,
  kommt sie dort hinein — in dem PR, der sie braucht.**
- **Formen mit einer Bedingung, die im Skript allein nicht steht.** `POST /statuses/<40 Hexziffern>`
  trägt das lokale Gate und verlangt den SHA in voller Länge, weil eine Abkürzung die Form ist,
  in der ein *anderer* Commit gemeint sein kann. `POST /issues/<n>/dependencies/blocked_by`: **ihr
  Body wird geprüft**, weil `issue_id` die **Datenbank-Id** ist und eine Issue-**Nummer** dort die
  gültige Id eines fremden Issues — dann wartet ein Paket auf etwas, das nie geschlossen wird.
- **Ein Fehlschlag ist ein Fehlschlag.** HTTP **≥ 300** geht auf stderr und endet mit Exit 1.
  **Die Schwelle liegt bei 300, weil ein Redirect zweimal darunter durchgerutscht ist**: nur ein
  `GET` folgt Weiterleitungen.
- **`GH_API_DRY_RUN=1`** druckt Methode und URL und sendet nichts. **Wer schreiben darf,
  entscheidet dabei nicht das Skript:** der `pr-pruefer` kommt an `GET` und an nichts sonst, und
  das steht in `pr-pruefer-guard.sh`.

**Das Project-Board bleibt ein Handgriff im Browser** — Scope `repo` erreicht ProjectsV2 nicht;
das steht hier, weil der Fehler wie ein kaputter Token aussieht.
