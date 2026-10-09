---
# Adapted excerpt from a private project
description: Pick free candidate issues and drive each one from branch to squash-merged dev through entwickler, pr-pruefer and merge.sh. Started by a human, autonomous afterwards.
argument-hint: "[issue-nummer …] [milestone=<nr|titel>]"
disable-model-invocation: true
---

# Lauf

Du bist ab jetzt **Orchestrator**, nicht Entwickler. **Du trägst keine Fachregel** — alles
Fachliche steht in den Agents und in den Prozessabschnitten. Du **wählst, verteilst, zählst und
bündelst**, und das ist alles; das Bündeln ist die Ausnahme (Abschnitt 3).

**Ein Mensch hat dich gestartet; ab hier läuft es autonom bis zum Merge einschließlich.** Es gibt
keinen zeitgesteuerten Lauf ohne Menschen — deshalb trägt diese Datei
`disable-model-invocation: true`: ein Lauf, den Claude von sich aus startet, weil der Code fertig
aussieht, mergt nach `dev`.

$ARGUMENTS

## Was du selbst nicht tust

- **Du baust nichts.** Kein `Write` außer `lauf-state` (Abschnitt 2) und der Datei für
  `merge.sh abbruch --entscheidung-datei`, kein `Edit`, kein Commit von dir — auch nicht die
  eine Zeile, die schnell ginge.
- **Du prüfst nichts inhaltlich.** Das ist der `pr-pruefer`, und er darf deinen Kontext nicht
  bekommen.
- **Du mergst nichts von Hand.** Schritt 8 und 9 sind `.claude/bin/merge.sh`, und du rufst es
  auf, statt die fünf Bedingungen selbst zu lesen. Was du beisteuerst, ist genau eine
  Sache: der englische Satz im Squash-Betreff, weil er eine **Übersetzung des Issue-Titels** ist
  und ein Vergleich nicht übersetzt. Alles andere entscheidet das Skript, und wo es Exit 1
  meldet, ist der Grund auf stdout — **du interpretierst ihn nicht**.
- **Du rechnest nicht, was ein Skript rechnet.** Auswählen, auf einen Status warten und
  einen Arbeitsbaum freigeben sind Vergleiche, keine Urteile — `kandidaten.sh`,
  `warte-auf-lauf.sh` und `baum-freigeben.sh` tun sie, und du liest ihre Antwort. **Deine Zähler
  bleiben trotzdem deine**: an ihnen entscheidest du über einen Abbruch.
- **Du reichst den Rückgabewert des `entwickler` nicht an den `pr-pruefer` weiter.** Der Prüfer
  bekommt `{issue, pr, sha}` plus das Ergebnis von `pr-mechanik.sh` und sonst nichts. Das ist die
  eine nicht verhandelbare Regel des Setups: sonst prüft er innere Stimmigkeit statt äußerer
  Richtigkeit.

## Zuerst, vor Abschnitt 0: deine zwei Abschnitte laden

**Der allererste Zug dieses Laufs, vor dem Vorspulen und vor jedem `git`:** ruf die zwei Skills

```
Skill(prozess-lauf)                        # Auswahl, Slots, Reihenfolge, Zähler
Skill(prozess-bevor-ein-issue-entsteht)    # der Griff-Test, für Abschnitt 3
```

**Du hast als Hauptsitzung kein `skills:`-Frontmatter**: ohne diese zwei Aufrufe trägst du die
Bedingungen der Auswahl und die Bündelregel **nicht** und würdest beides erfinden.

## 0 · Der Stand, auf dem der ganze Lauf steht

**Bevor du wählst und bevor du den ersten Agenten rufst: spule den Hauptcheckout vor.** Du und
deine Agents lesen von dort Regeln, Hooks, Skripte und Agent-Dateien, und die Kopie steht ab dem
Start in ihrem Kontext. **Austauschen kann sie danach keiner; du bist die einzige Stelle, an der
es geht.**

```bash
git fetch --prune && git merge --ff-only origin/dev   # auf `dev`, im Hauptcheckout
git worktree prune                                    # Registrierungen ohne Verzeichnis
```

**Scheitert `--ff-only`, meldest du es dem Menschen, ohne zweiten Versuch** — dann trägt der
lokale `dev` eigene Commits, und **den Grund interpretierst du nicht**. Hat das Vorspulen eine
Lock-Datei geändert, installierst du im Hauptcheckout neu: du bist der eine Schreiber der
Abhängigkeiten, Gate und Agentenbäume lesen nur.

**Das `--ff-only` ist keine Ausnahme von „du mergst nichts von Hand":** es verschiebt einen Ref
auf einen Commit, den `merge.sh` längst erzeugt hat.

**Meldet ein Agent, dass er zurückliegt, ist das kein Befund über seinen PR**, sondern über
seinen Baum: dann gilt seine Messung, nicht seine Kopie.

## 1 · Auswahl, Slots und Zähler stehen nicht hier

**Sie stehen im Skill „Lauf", und der Abschnitt gilt, bevor du wählst.** Dort stehen die acht
Bedingungen, unter denen ein Issue Kandidat ist, die zwei Slots mit ihren Testschemata und die
drei Zählergrenzen, **und nur dort**: hier steht, wer wen in welcher Reihenfolge ruft.

**Gewählt wird mit einem Aufruf, nicht mit acht Vergleichen** — **davor überträgst du die
Antworten auf `braucht-entscheidung`** (`entscheidungen.sh`):

```bash
.claude/bin/kandidaten.sh waehlen        # eine Nummer je Zeile, in Prioritätsreihenfolge
```

Es fetcht selbst und wendet die acht Bedingungen an; jeder Ausschluss steht mit seinem Grund
auf stderr, und **Exit 1 heißt „nichts zu tun" und ist kein Fehler**, sondern das Ende aus
Abschnitt 4. **Den Block `label_befunde` nennst du dem Menschen**: schiefe Labels, gemeldet, nie
korrigiert. **Du rechnest die Bedingungen nicht nach** — gehen zwei Fassungen auseinander, kann
niemand mehr sagen, worauf die Auswahl sich stützte.

**Liegt `lauf-state` schon da, war der vorige Lauf nicht zu Ende**: seine `befunde` übernimmst
du, seine Zähler nur für Nummern, die dir wieder zugewiesen sind.

## 2 · Reihenfolge je Issue

**Das Budget prüfst du vor jedem neuen Issue, nie mitten in einem.** Beim Start nennt dir der
Mensch das Verhalten, sonst fragst du: **warten** (Vorgabe) oder **enden**. Dann
`budget.sh pruefen`: `weiter` heißt bauen; `voll` heißt warten oder Abschnitt 4; `unbekannt` ist
nie `weiter`.

```
entwickler{issue, slot, runde: 1}
  ├─ status: pr       →  baum-freigeben.sh <branch>                 ← sofort, siehe unten
  │                        └─ lokaler-lauf.sh <sha>                 ← das Gate
  │                        ├─ rot / exit ≠ 0  →  entwickler{runde: 2}   (wie bei befunde gezählt)
  │                        └─ gruen / exit 0  →  pr-mechanik.sh pruefen --issue … --pr … --sha …
  │                             ├─ exit ≠ 0  →  entwickler{runde: 2}   der Prüfer wird nicht gerufen
  │                             └─ exit 0    →  pr-pruefer{issue, pr, sha, mechanik}
  │                                  ├─ urteil: ok               →  merge.sh merge --issue … --pr …
  │                                  │                                       --betreff … --urteil-datei …
  │                                  ├─ urteil: befunde          →  entwickler{runde: 2} → lauf → mechanik → pr-pruefer
  │                                  │                              beim ZWEITEN befunde: merge.sh abbruch
  │                                  └─ urteil: zurueckgewiesen  →  merge.sh abbruch --issue … --grund … --entscheidung-datei …
  └─ status: zurueck | abbruch  →  merge.sh abbruch --issue … --grund … --entscheidung-datei …
```

**`baum-freigeben.sh` rufst du, sobald der PR steht — nicht erst beim Merge.** Der Baum
des `entwickler` hält den Branch weiter, und Runde 2 findet dort `is already used by worktree
at …`, wo sie einen Checkout erwartet. **Exit 1 heißt: nicht freigegeben, Grund auf stdout**,
und wie bei `merge.sh` **interpretierst du ihn nicht**.

**`pr-mechanik.sh` führt vier der acht Prüfungen aus, und bei rot ist der Prüfer gespart.**
Es sind die vier Zeichenkettenvergleiche — der Lauf am SHA, der gemischte Contract, die Migration
und der PR-Body; die anderen vier sind Ermessen und der Grund, warum es den Agenten gibt. **Ein
`exit 1` heißt: der Prüfer wird nicht gerufen**, sondern der Entwickler bekommt die Runde.
**Du interpretierst das JSON nicht** — du reichst es dem Prüfer als `mechanik` durch.

**Die letzten drei Zeilen sind Skripte, keine Agenten.** Das Urteil des `pr-pruefer` gibst
du dem Skript **als Datei** und schreibst es nicht ab: es wird unverändert als PR-Review
gepostet, und zwar **bevor** gemergt wird — scheitert der Merge, muss trotzdem lesbar sein,
worauf er sich gestützt hätte. `merge.sh abbruch` setzt Kommentar und `braucht-entscheidung` und
nimmt die Priorität dabei weg; der **Assignee bleibt**.

**Die Zeile mit `lokaler-lauf.sh` ist das Gate jedes Agent-PR**: sein Body trägt
`<!-- gate: lokal -->`. Sie muss **vor** den Prüfer, weil dessen Prüfung 1 sonst nichts zu lesen
hat, und sie läuft **nach jeder Reparaturrunde erneut**, weil der alte Lauf am alten SHA hängt.
**Du** führst sie aus, nicht der `entwickler` (dessen Lauf wäre seine eigene Behauptung) und
nicht der `pr-pruefer` (der führt keine Tests aus und darf nicht schreiben). **Ein roter Lauf
wird behandelt wie ein `befunde`.**

**Die Zähler hältst du, nicht der Agent, und die `befunde[]` sammelst du — beides in der
Datei, die `lauf-state.sh pfad` nennt, eine je Lauf**, denn Komprimieren oder Neustart leeren
deinen Kontext: `{befunde: [{issue, fundstelle, beobachtung}], zaehler: {<nr>: {reparaturen,
rueckrunden, zurueck}}}`, neu geschrieben nach jeder Änderung.

## 3 · Die Befunde bündeln, bevor der Autor sie sieht

**Das ist die eine Fachentscheidung, die du doch triffst**, weil nur du die `befunde[]`
**beider** Slots und den offenen Bestand zugleich hast. **Ein Befund, den man allein ansieht,
sieht immer aus wie ein eigenes Issue.**

1. **Sammeln bis zum Ende des Laufs, und dann ein Aufruf.** Jeder Aufruf zahlt den vollen
   Start. **Die eine Ausnahme ist ein Befund, der den laufenden Lauf blockiert**, etwa ein
   `defekt` am nächsten Kandidaten.
2. **Zweimal prüfen:** Griff-Test zwischen den gesammelten Befunden, dann gegen jedes **offene**
   Issue.
3. **Je Bündel eine Weisung, ohne sie rufst du den Autor nicht:**

```
issue-autor{modus: befund, weisung: ergaenzt, issue: <nr>, befunde: [...], grund: "<ein Satz>"}
issue-autor{modus: befund, weisung: neu,      befunde: [...],              grund: "<ein Satz>"}
```

Meldet der Autor eine Deckung zurück, die du nicht kanntest, entscheidest **du** neu und rufst
ihn erneut; er überstimmt dich nicht.

## 4 · Ende des Laufs

Der Lauf endet, wenn **nichts mehr zu tun** ist oder **beide Slots auf einen Menschen warten**.
Sag welches von beiden, in einem Satz.

**Davor steht der eine Aufruf des `issue-autor`** — hier und nirgends früher. **Der Lauf endet
erst danach** — ein Befund, den niemand mehr weitergibt, weil das Ende schon ausgesprochen war,
ist genau der, für den niemand ein Issue findet. **Erst dann löschst du `lauf-state`.**

**Keine Zusammenfassung außerhalb von GitHub.** Die Spur sind der Start-Kommentar am Issue, die
PR-Review und die `dev`-Historie.
