---
# Adapted excerpt from a private project
name: prozess-der-stand-auf-dem-gearbeitet-wird
description: >-
  Der erste Handgriff jeder Rolle: den eigenen Stand gegen origin/dev messen und einen Rueckstand melden, statt still weiterzuarbeiten.
metadata:
  abschnitt: "Der Stand, auf dem gearbeitet wird"
  reihenfolge: 1
---

## Der Stand, auf dem gearbeitet wird

**Der erste Handgriff jeder Rolle, vor jedem anderen: den eigenen Stand gegen `origin/dev`
messen.** Drei Kommandos, und keines von ihnen verändert etwas:

```bash
git fetch --prune                                            # Remote zuerst, immer
git rev-list --left-right --count HEAD...origin/dev          # <eigene> <fremde> Commits
git diff --name-only HEAD origin/dev -- CLAUDE.md .claude/   # sind Regeln darunter?
```

**Gemessen wird von dem Branch aus, auf dem gearbeitet wird — im `entwickler`-Baum also *nach*
dem Abzweigen und nicht davor**: davor liest `HEAD` den Wegwerf-Branch auf `origin/main`, und wer
dort misst, meldet `main`↔`dev` als eigenen Rückstand. Die anderen drei Rollen zweigen nicht ab:
Orchestrator und `issue-autor` laufen im Hauptcheckout auf `dev`, der `pr-pruefer` im Baum, in
dem er gerufen wird.

**Liegt der eigene Stand mehr als drei Commits zurück, oder nennt das dritte Kommando eine
Datei, ist das eine sichtbare Meldung** — im Bericht, im Ausgangsfeld `befunde`, im Satz an den
Menschen — und **nie ein stilles Weiterarbeiten**. **Eine Schwelle und nicht null**, weil `dev`
sich unter jedem Lauf bewegt; **die Dateiliste ist die schärfere Hälfte und keine Zahl**, denn
ein Commit an einer Regeldatei rutscht unter jeder Schwelle durch und kostet trotzdem einen
Agentenlauf — wer einen Mechanismus für fehlend hält, baut ihn zweimal.

**Die zweite Frage ist die injizierte Regelkopie.** Zwei Handgriffe folgen:

- **Wer zurückliegt, liest die Regel aus `origin/dev` statt aus seiner Kopie** —
  `git show origin/dev:.claude/rules/prozess.md`, kein Baumwechsel und kein `checkout`.
- **Vorgespult wird der Hauptcheckout vom Orchestrator**, nie vom Agenten selbst, auf `dev` und
  **ohne `pull`**: `git fetch --prune && git merge --ff-only origin/dev`. **Ein Fehlschlag
  ist eine Meldung und kein zweiter Versuch.**

**Und eine zweite Leseregel: lies die Zeile, nicht die Zahl.** Die Zusammenfassung eines
Testlaufs ist die **letzte** Zeile, nie die wichtigste: `784 passed, 122 errors` war der
Migrations-Reststand eines fremden Branches, `14 skipped, … deselected` ein **Abbruch mit
Exit 4** ohne Testdatenbank. **Gelesen werden der Exitcode und die Zeile darüber, nicht die
Zahl daneben**, und das gilt für **jede Rolle** — der `entwickler` an seinem eigenen Lauf, der
Orchestrator an `lokaler-lauf.sh`, der `pr-pruefer` an dem, was ihm `pr-mechanik.sh` meldet.
