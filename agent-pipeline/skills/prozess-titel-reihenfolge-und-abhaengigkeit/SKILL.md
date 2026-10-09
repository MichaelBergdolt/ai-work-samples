---
# Adapted excerpt from a private project
name: prozess-titel-reihenfolge-und-abhaengigkeit
description: >-
  Warum im Titel keine Nummer steht, und wie Reihenfolge stattdessen als Attribut getragen wird.
metadata:
  abschnitt: "Titel, Reihenfolge und Abhängigkeit"
  reihenfolge: 10
---

## Titel, Reihenfolge und Abhängigkeit

**Im Titel steht keine Nummer** — keine ID, keine Reihenfolge, kein Label-Wort; er benennt in
einer Zeile das *Ergebnis*. Eine Nummer wäre eine *Kopie* der Reihenfolge und veraltet beim
ersten Umsortieren. Reihenfolge ist ein **Attribut**: **Rang und Priorität** im Project-Board,
**Abhängigkeiten** nativ als „Blocked by" (nicht als Satz im Fließtext, der beim Filtern nach
„was ist bereit" unsichtbar bleibt), **Bündel** im Milestone.

**Geschrieben wird die native Beziehung mit `.claude/bin/blocked-by.sh`**:
**`blocked-by.sh eintragen` ruft der `issue-autor`, unmittelbar nachdem er `Blocked by #<nr>` in
einen Body geschrieben hat**, und am Issue, dessen Body den Satz trägt.

**Ein Paket verspricht nur, was sein Diff belegen kann.** Verlangt ein „Fertig, wenn"
zusätzlich einen Zustand, den erst eine spätere Sitzung, ein echter Agentenlauf oder ein echter
Merge herstellt, gehört diese Hälfte in ein **zweites Paket**: **Paket A** liefert den
Mechanismus, ist diff-prüfbar und geht zuerst; **Paket B** weist die Wirkung gegen ein
**Artefakt** nach — Kommentar, PR-Review, Squash-Commit, CI-Log — und trägt „Blocked by" auf
Paket A. **Sonst gibt es keinen SHA, gegen den sich beide Hälften prüfen lassen** (Prüfung 1
und 2), und ob ein Satz aus einem Diff folgt, prüft kein Automat.

**Der Contract/Verbraucher-Schnitt ist derselbe Fall, und er entsteht beim Anlegen**: verlangt
ein Befund eine Wire-Form **und** die Flächen, die sie benutzen, sind das **zwei** Issues mit je
eigenem „Fertig, wenn" — das Contract-Paket zuerst, das Verbraucher-Paket mit `Blocked by`
darauf —, **geschnitten vom `issue-autor` im Moment des Anlegens**, womit jeder PR sein eigenes
Issue schließt. Ungeschnitten stehen sich zwei richtige Regeln im Weg: Prüfung 8 verlangt
`Closes #<nr>` mechanisch, und der `pr-pruefer` weist die Zeile zu Recht zurück, wenn der Diff
die Zusage nicht einlöst. **Eine eigene Form in Prüfung 8 für einen Teil-PR ist geprüft und
verworfen**; sie bleibt **ohne Ausnahme**, und das ist die Kraft, die den Schnitt an seinen Ort
zwingt.
