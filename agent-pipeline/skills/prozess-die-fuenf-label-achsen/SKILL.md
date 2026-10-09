---
# Adapted excerpt from a private project
name: prozess-die-fuenf-label-achsen
description: >-
  Genau ein Label je Achse, die Regeln darueber und wer sie von Hand nachhaelt.
metadata:
  abschnitt: "Die fünf Label-Achsen"
  reihenfolge: 11
---

## Die fünf Label-Achsen

**Genau ein Label je Achse**, und mehr Achsen gibt es nicht: **Priorität** (`1 · jetzt`,
`2 · als nächstes`, `3 · später`), **Aufwand** (`Aufwand 1|2|3|5|8`), **Art** (`defekt`,
`feature`, `politur`, `untersuchung`, `Prozessänderung`), **Ebene** (`backend`, `frontend`:
*was* angefasst wird, nicht *wer*) und **Voraussetzung** (`braucht-geraete`,
`braucht-testpersonen`, `braucht-entscheidung`). **Jedes Label trägt eine Beschreibung**, denn
ohne sie hieß dieselbe Arbeit zweimal verschieden.

1. **Priorität im Milestone wie außerhalb.** Kein Prio-Label heißt **nicht triagiert**.
2. **`braucht-*` ersetzt die Priorität**, es ergänzt sie nicht: ein Issue, das auf ein Testgerät
   wartet, hat keine Dringlichkeit, sondern eine Bedingung.
3. **Was kaputt ist, steht ganz oben: `defekt` ⇒ `1 · jetzt`**, sonst verliert ein Defekt
   gegen Politur, weil die kleiner aussieht. Für `untersuchung` gilt das **nicht**.
4. **`Prozessänderung` ⇒ `1 · jetzt`**: sie wirkt auf **jedes Issue, das danach
   entsteht**, und hinter fünf Produkt-Issues wird fünfmal falsch gearbeitet. **Regel 2 bleibt
   stärker**, und **`Aufwand 8` heißt zu groß**.
5. **Der Body nennt seine Labels, und diese Zeile ist die Form** — sie beginnt mit
   `**Labels:**` und nennt die Namen **in Backticks**, so:

   ```
   **Labels:** `1 · jetzt` · `Aufwand 3` · `Prozessänderung` · `backend`
   ```

   **Genannt heißt gesetzt.** **Geprüft wird die Zeile mit
   `.claude/bin/issue-stimmigkeit.sh pruefen`, bevor der `POST` rausgeht**, von der **Station**,
   die Body und Labels zugleich in der Hand hat. **Eine Form und kein Satz im Fließtext**, denn
   ein Zustand, der nur beschrieben ist, steht in keinem Feld.
6. **`braucht-entscheidung` trägt einen festen Block** — vom `issue-autor` im Body, von
   `merge.sh abbruch` im Kommentar (`--entscheidung-datei`); zwei oder drei Optionen:

   ```
   **Frage:** <ein Satz>
   - **A** — <Option>. Dafür: <Halbsatz>; dagegen: <Halbsatz>.
   - **B** — <Option>. Dafür: <Halbsatz>; dagegen: <Halbsatz>.
   **Empfehlung:** <Buchstabe>, weil <Grund>.
   Antwort: ein Kommentar mit dem Buchstaben genügt.
   ```

   **Ohne ihn lehnt `issue-stimmigkeit.sh pruefen` ab.** Die Antwort überträgt der Orchestrator
   („Lauf"), denn eine Frage ohne Antwortweg wartet beliebig lange.

**Regel 3 und 4 prüfen zwei Stationen, keine setzt nach**: beim Anlegen lehnt
`issue-stimmigkeit.sh pruefen` `defekt` und `Prozessänderung` ohne `braucht-*` ab, deren Zeile
`1 · jetzt` nicht nennt; beim Start von `/lauf` meldet `kandidaten.sh` schiefe Labels im Block
`label_befunde`. **Kein lokaler Automat entfernt oder setzt Labels** — wer fremde Issues
umstuft, entscheidet über fremde Arbeit.
