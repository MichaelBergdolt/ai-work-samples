---
# Adapted excerpt from a private project
name: prozess-lauf
description: >-
  Was /lauf tut: Kandidaten waehlen, zwei Slots verteilen, die Zaehler halten -- und welche Skripte in welcher Reihenfolge laufen.
metadata:
  abschnitt: "Lauf"
  reihenfolge: 9
---

## Lauf

Ein Mensch startet `/lauf`; danach läuft er autonom bis zum Merge einschließlich. Das Kommando
trägt **keine Fachregel** — es wählt, verteilt und zählt.

**Auswahl.** Zuerst `git fetch --prune`, dann über die API. Ein Issue ist Kandidat, wenn alles
davon gilt: offen ∧ kein Milestone (mit Argument: dieser) ∧ ein Prio-Label
(`1` vor `2` vor `3`) ∧ kein `braucht-*` ∧ kein Assignee ∧ kein Branch und kein PR mit der
Nummer ∧ kein `Aufwand 8` ∧ jedes „Blocked by"-Issue geschlossen ∧ **keine Zeile
`**Als belegt schließen.**` im Body**. **Eine Zuweisung an das eigene Token-Konto macht daraus
keinen Kandidaten, sondern eine Meldung.** **`Prozessänderung` wird vom Lauf nicht gebaut**, sie
ändert den Prozess, den er gerade ausführt.

**Ausgeführt wird diese Rechnung von `.claude/bin/kandidaten.sh`**, nicht vom Orchestrator: es
sind Vergleiche, kein Ermessen, und **Ermessen bekommt ein Modell, Vergleiche bekommen Code**.
Die Bedingungen stehen weiter hier, denn Code sagt nicht, *warum* eine gilt. Die Ausgabe ist
eine Nummer je Zeile in Prioritätsreihenfolge, jeder Ausschluss mit seinem Grund auf stderr;
**Exit 1 heißt „nichts zu tun" und ist kein Fehler**.

**Die achte Bedingung ist die einzige, die in den Body sieht**: ein Issue, dessen Body eine
Zeile mit `**Als belegt schließen.**` beginnt, ist **entschieden und kein Bau-Kandidat mehr** —
sein „Fertig, wenn" folgt aus Artefakten und nicht aus einem Diff. **Dass das Skript sonst keinen
Body liest, ist Absicht und bleibt es**: gelesen wird ein **Marker am Zeilenanfang** und kein
Sinn.

**Antworten auf `braucht-entscheidung` überträgt der Orchestrator vor `kandidaten.sh`**:
`entscheidungen.sh liste` nennt Frage und Antwort (als Kommentar der Buchstabe allein oder
`Entscheidung: B`), `entscheidungen.sh uebertrag` setzt sie samt Frage in den Body und nimmt das
Label ab. **Übertragen, nie gedeutet.**

**Slots.** Höchstens **zwei** `entwickler` gleichzeitig, Slot `a` und `b`, jeder mit eigenem
Testschema — die Datenbank hängt nicht am Arbeitsbaum, und zwei Entwickler auf einem Schema
sind reproduzierbar `Can't locate revision identified by …`. **Das Schema heißt nach dem
Arbeitsbaum und nicht nach dem Slot**, denn **der Slot ist keine Kennung, weil er
wiederbenutzt wird**. **Geschrieben wird der Name von `.claude/bin/testschema.sh`, gerufen aus
dem `SubagentStart`-Hook** — nicht von Hand, denn eine geerbte `.env` vergisst man.

**Reihenfolge je Issue:** `entwickler(slot)` → bei `pr`: `baum-freigeben.sh <branch>` →
`lokaler-lauf.sh <sha>` [→ `warte-auf-lauf.sh <sha>`] → `pr-mechanik.sh pruefen` →
`pr-pruefer{issue, pr, sha, mechanik}` → `merge.sh merge`. **Der lokale Lauf ist das Gate
jedes Agent-PR.** Der Lauf muss **vor** die Mechanik, weil deren Prüfung 1 sonst nichts zu lesen
hat, und die Mechanik **vor** den Prüfer, weil sie ihm vier seiner acht Prüfungen abnimmt; bei
rotem Lauf **und bei roter mechanischer Prüfung** geht es wie bei `befunde` weiter, und **der
Prüfer wird gar nicht erst gerufen**. Bei `befunde`: **zuerst
`merge.sh rueckmeldung --pr <nr> --urteil-datei <datei>`**, dann einmal `entwickler(runde 2)`,
dann **erneut Lauf und Mechanik am neuen SHA**, Prüfer, Merge; beim zweiten `befunde` **wieder
`rueckmeldung`, dann** `merge.sh abbruch`. Bei `zurueck` oder `abbruch` des Entwicklers: direkt
`merge.sh abbruch`.

**`warte-auf-lauf.sh <sha>` ersetzt das Pollen von Hand**, denn Warten kostet eine Shell nichts,
ein Modell aber eine Runde. Es **endet immer** — ein Wartezyklus ohne Zeitlimit ist schlimmer als
ein roter Lauf, weil er wie Arbeit aussieht. **Es antwortet über *seinen* Lauf, nicht über den
SHA**: ein Ergebnis, das beim ersten Versuch schon dastand, gehört einem früheren Lauf.

**`merge.sh rueckmeldung` ist die Review-Spur eines `befunde`, und sie geht *vor* die zweite
Runde**, sonst bleibt die Reparatur sichtbar und ihr Grund nicht — **ein Skript, das
niemand aufruft, ist so gut wie keins.** **Das Urteil geht als Datei, nie als Argument**: eine
gekürzte Fassung wäre nicht mehr das Urteil des Prüfers, **es geht unverändert durch**.
**Gerufen wird es vom Orchestrator**, nicht vom `pr-pruefer`, der nicht schreiben darf.

**Der Prüfer bekommt das Skriptergebnis und weiterhin keinen Bericht des Entwicklers** —
das Ergebnis ist eine Messung an PR und Diff, der Bericht wäre eine Aussage dessen, der gebaut
hat. **Der englische Satz im Betreff ist die eine Ausnahme und bleibt beim Orchestrator**, denn
übersetzen kann ein Vergleich nicht.

**Und die Befunde gehen gebündelt, mit einer Weisung**: nur der Orchestrator hält die
`befunde[]` **beider** Slots gleichzeitig. **Gerufen wird der Autor einmal je Lauf, am Ende, mit
allen Befunden** — **gesammelt, nicht durchgereicht**: jeder Aufruf zahlt den vollen Start.
**Der Autor führt die Weisung aus, er überstimmt sie nicht:** findet seine eigene Suche eine
Deckung, die der Orchestrator nicht kannte, **meldet er sie zurück statt selbst umzuentscheiden**.

**Der Rückgabewert des `entwickler` wird dem `pr-pruefer` nicht weitergereicht**; der Prüfer
bekommt `{issue, pr, sha}` und sonst nichts, **auch nicht von der Platte**: `token-log.sh`
legt den Bericht nicht ab, denn **strukturell abwesend ist stärker als eingezäunt**, und
weil Abwesenheit nicht rückwärts reicht, verwehrt `pr-pruefer-guard.sh` dem Prüfer
`.claude/metrics/` über **alle vier** Werkzeuge seiner Rolle, und nur dieses Verzeichnis.

**Die Zähler hält der Orchestrator, nicht der Agent:** `reparaturen ≤ 2` je Branch (der
Entwickler meldet sie), `rueckrunden ≤ 1`, `zurueck ≤ 1`. Danach ein Mensch. Es sind
Heuristiken, keine Garantien — jedes Ende ist ein Kommentar plus `braucht-entscheidung`, nie ein
stiller Zustand. **Sie sind ausdrücklich kein weiteres Skript**: sie sind die Stelle, an der
über einen **Abbruch** entschieden wird. **Und der Orchestrator bleibt aus demselben Grund
ein Modell**: **ein Lauf braucht mittendrin Urteile**, und ein Workflow-Skript **kann keine
Eingabe entgegennehmen**.

**Vor jedem neuen Issue fragt der Orchestrator `.claude/bin/budget.sh pruefen`**, nie
mitten in einem: kontoweiter Verbrauch plus Sicherheitsabstand gegen eine Schwelle.
`unbekannt` ist nie `weiter`. Eine feste Obergrenze an Issues gibt es bewusst nicht.

**Der Lauf endet**, wenn nichts mehr zu tun ist oder beide Slots auf einen Menschen warten.
**Keine Zusammenfassung außerhalb von GitHub** — die Spur sind der Start-Kommentar am Issue, die
PR-Review und die `dev`-Historie.

**Nicht angefasst vom Lauf:** alles mit `braucht-*` außer dieser Übertragung; `main` (dorthin
liefert nur ein Mensch); das Project-Board (PAT-Grenze).
