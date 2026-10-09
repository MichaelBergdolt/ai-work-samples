---
# Adapted excerpt from a private project
name: prozess-bevor-an-einem-issue-gearbeitet-wird
description: >-
  Die Reservierung: nachsehen, ob jemand daran ist, und sich selbst zuweisen, bevor die erste Zeile entsteht.
metadata:
  abschnitt: "Bevor an einem Issue gearbeitet wird"
  reihenfolge: 6
---

## Bevor an einem Issue gearbeitet wird

**Immer und zuerst**, auch wenn die Aufgabe klein aussieht, und bei mehreren Issues je Issue:

1. **Nachsehen, ob schon jemand daran ist.** Zuständig ist der *Assignee*, aber nicht das einzige
   Zeichen — auch ein offener PR, ein Branch mit dieser Nummer, ein frischer Kommentar:

   ```bash
   .claude/bin/gh-api.sh GET "/issues/<nr>"           # Assignee, Zustand
   .claude/bin/gh-api.sh GET "/issues/<nr>/comments"
   .claude/bin/gh-api.sh GET "/pulls?state=open"      # trägt einer die <nr>?
   git fetch --prune && git branch -r --list "*/*<nr>-*"
   ```

2. **Ist jemand anderes zugewiesen oder hat einen offenen PR: nicht anfangen** — melden, wer, und
   auf eine Entscheidung warten.
3. **Ist niemand zugewiesen: dem angemeldeten Konto zuweisen, bevor die erste Zeile entsteht.**
   Wer der Token ist, nennt `gh-api.sh GET /user`; zugewiesen wird mit
   `gh-api.sh POST /issues/<nr>/assignees '{"assignees":["<login>"]}'`. Die Zuweisung **ist** die
   Reservierung und das Einzige, was die andere Person in Schritt 1 sehen kann.
4. **Bei einem Sammelpaket: mit dem Anlege-Stichwort erneut suchen.** Der Griff-Test aus
   „Bevor ein Issue entsteht" lief beim **Anlegen** und kennt nur den Bestand von damals — ein
   Sammelpaket ist deshalb schon einmal an einem anderen vorbeigelaufen, das zwei seiner drei
   Zusagen inzwischen geliefert hatte. Der interessante Treffer ist dabei das **geschlossene**
   Issue; ein offenes hätte schon Schritt 1 als Reservierung gezeigt.

   ```bash
   .claude/bin/gh-api.sh GET "/search/issues?q=repo:<owner>/<repo>+<stichwort>"
   ```

   **Was schon eingelöst ist, wird nicht ein zweites Mal gebaut**, sondern im PR-Body
   nachgetragen — die Pflicht dazu steht in „Regeln quer zum Ablauf".
5. Erst danach: `git fetch`, von `dev` abzweigen, bauen.
