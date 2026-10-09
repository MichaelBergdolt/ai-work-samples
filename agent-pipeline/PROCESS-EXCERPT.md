# Prozess — Auszug

> **Auszug, selbst geschrieben** für dieses Repo. Das Original ist ein Index (`.claude/rules/prozess.md`)
> über zwölf Skills; zwei davon sind zu groß zum Übernehmen und hier in je einem Absatz zusammengefasst.

## Wer liest was

Jeder Agent lädt nur seine Abschnitte, über `skills:` im Frontmatter. Der Orchestrator ist die
Hauptsitzung und hat kein Frontmatter; er lädt seine zwei per `Skill(...)` als ersten Zug.

| Rolle | Abschnitte (Skills) |
|---|---|
| `issue-autor` | Stand · Anmeldung · Bevor ein Issue entsteht · Titel/Abhängigkeit · Label-Achsen |
| `entwickler` | Stand · Anmeldung · Arbeitsbaum je Sitzung* · Bevor an einem Issue gearbeitet wird · Der Weg, Schritte 1–6* · Regeln quer zum Ablauf |
| `pr-pruefer` | Stand · Anmeldung · Prüfung · Regeln quer zum Ablauf |
| Orchestrator (`/lauf`) | Lauf · Bevor ein Issue entsteht |

\* nicht übernommen (über 20 KB), unten zusammengefasst.

## Der Weg vom Issue zum gemergten `dev` (Zusammenfassung)

1. `git fetch --prune`, bevor irgendetwas entsteht.
2. Zuweisen, dann im eigenen Arbeitsbaum von `origin/dev` abzweigen (nicht vom lokalen `dev`).
3. Branch mit dem allerersten Push veröffentlichen — er ist das zweite Zeichen der Reservierung.
4. Jeden Commit sofort pushen, danach `git ls-remote` gegen `git rev-parse HEAD` halten.
5. Beide Testsuiten lokal.
6. PR gegen den frisch geholten `dev`, mit `Closes #<nr>`, „Entscheidungen" und Gate-Marke.
7. Abnahme durch den `pr-pruefer`, nicht durch den Autor.
8. Hartes Gate: grüner Lauf **am SHA**. Squash-Merge durch `merge.sh`.
9. Nachziehen: Issue schließen, Branch remote und lokal löschen, `dev` gegen den Merge-SHA prüfen.

## Ein Arbeitsbaum je Sitzung (Zusammenfassung)

Jede Sitzung und jeder `entwickler` arbeitet in einem eigenen `git worktree`. Zwei Sitzungen in
einem Checkout teilen HEAD, Index und ausgecheckte Refs, ohne es zu merken; nicht committete
Dateien wandern beim fremden `git switch` mit. Was trotzdem geteilt bleibt (`.git`, Datenbank,
Venv, Scratchpad), bekommt je Baum einen eigenen Namen oder wird nur gelesen.
