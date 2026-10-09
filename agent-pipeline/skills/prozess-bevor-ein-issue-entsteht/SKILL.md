---
# Adapted excerpt from a private project
name: prozess-bevor-ein-issue-entsteht
description: >-
  Die Duplikatsregel ueber den ganzen Bestand, die vier Deckungen und der Griff-Test fuers Buendeln.
metadata:
  abschnitt: "Bevor ein Issue entsteht"
  reihenfolge: 5
---

## Bevor ein Issue entsteht

**Erst prüfen, dann anlegen.** Derselbe Befund zweimal aufgeschrieben sind zwei Zusagen und zwei
Branches, die sich überschreiben. Geprüft wird über den **ganzen Bestand, offen wie
geschlossen**:

```bash
.claude/bin/gh-api.sh GET "/search/issues?q=repo:<owner>/<repo>+<stichwort>"
.claude/bin/gh-api.sh GET "/issues?state=all&labels=defekt&per_page=100"  # bei einem Defekt
```

**Starke Überschneidung heißt: das bestehende Issue wird ergänzt, nicht ein zweites angelegt.**
„Stark" ist keine Wortähnlichkeit, sondern **eine von vier Deckungen** — dieselbe **Fundstelle**,
dieselbe **Ursache**, dieselbe **Zusage** im „Fertig, wenn", oder **derselbe Griff**:

- **Eine Deckung, Issue offen:** der Befund wandert in den Abschnitt des bestehenden Issues —
  **in den Body, nicht in einen Kommentar**: der Body ist die gültige Fassung.
- **Keine Deckung, eigener Issue-Wert:** neues Issue, dessen „Fertig, wenn"-Satz **ohne das
  andere Issue** abgenommen werden kann.
- **Deckung, Issue geschlossen:** neues Issue, das das geschlossene **verlinkt** und sagt, warum
  dessen Zusage nicht mehr trägt — **ein geschlossenes wird nicht wieder aufgemacht**.

**Der vierte urteilt als einziger über zwei *verschiedene* Sachverhalte**: er fragt, ob ein
Entwickler sie **in demselben Branch** erledigen würde, ohne dass der zweite dort ein zweiter
Zweck wäre, und greift nur, wenn **alle drei** Fragen ja sind — **dieselbe Ebene?**, **dieselbe
Sorte Änderung?**, **zusammen ein Paket?** **Bündeln ist der Normalfall,
ein eigenes Issue die Ausnahme mit Begründung**, denn **ein Befund, der allein betrachtet wird,
sieht immer aus wie ein eigenes Issue**. **Eine feste Aufwandszahl als Schranke gibt es bewusst
nicht:** sie wäre zahnlos oder schöbe kleine Defekte in Pakete, die niemand anfasst.
**Entschieden wird aus einem Lauf heraus vom Orchestrator**, weil nur er die `befunde[]` aller
Slots und den offenen Bestand auf einmal sieht — sonst vom Menschen, der meldet.

**Der Nachweis steht im Body:** *Geprüft gegen: #x, #y — <warum das nicht dasselbe ist>*, dazu
*Gebündelt mit …, weil …* bzw. *Eigenes Paket, weil kein offenes Issue es mit-erledigt* — ohne
beides ist „geprüft und verschieden" von „nicht geprüft" nicht zu unterscheiden. **Einen
Duplikat-Wächter gibt es bewusst nicht:** ein Automat urteilt nach Wortähnlichkeit, gefragt ist
die **Ursache**.
