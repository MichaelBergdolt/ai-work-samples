---
# Adapted excerpt from a private project
name: prozess-pruefung
description: >-
  Schritt 7 in lang: die acht Pruefungen gegen Issue-Body, Diff und CI-Lauf, und die drei Urteile.
metadata:
  abschnitt: "Prüfung"
  reihenfolge: 8
---

## Prüfung

**Abgenommen wird gegen den Issue-Body, den Diff und den CI-Lauf am SHA** — nie gegen den
Bericht dessen, der gebaut hat: viermal war die *Rechnung* geprüft und die *Zusage* nicht.
Wer prüft, bekommt ihn deshalb nicht und darf nicht schreiben.

**Vier der acht Prüfungen führt `.claude/bin/pr-mechanik.sh` aus, nicht der Prüfer**,
gerufen vom Orchestrator **vor** ihm: **1, 4, 5 und 8**, die reinen Zeichenkettenvergleiche, denn
**Ermessen bekommt ein Modell, Vergleiche bekommen Code**. **Der Prüfer prüft sie nicht
nach** — ein zweiter Lauf wäre eine zweite Wahrheit —, und **sie sind unüberspringbar**: ist eine
rot, wird er gar nicht erst gerufen.

1. **Der Lauf gehört zu diesem SHA** — `head_sha` des Laufs = `head.sha` des PR, denn ein grüner
   Lauf auf einem älteren Commit ist keiner. Feld `ci`. **Trägt der PR-Body `<!-- gate: lokal -->`,
   ist „grün am SHA" der Commit-Status `lokaler-lauf`**, sonst der Check-Run.
2. **Das „Fertig, wenn" des Issue-Bodys** — nicht des PR-Bodys — ist im Diff erkennbar **und in
   einem Test**. Erfüllt der Diff die Rechnung, aber kein Test die Zusage, ist das ein Befund.
   **Beginnt eine Body-Zeile mit `**Ohne Test.**`, entfällt die Testhälfte**,
   `zusage_getestet: entfaellt`.
3. **Jede Datei im Diff gehört zu den vier Abschnitten des Issues**, sonst ist es ein zweiter
   Zweck: „ein Issue, ein Branch, ein PR" ist eine Zusage über den *Inhalt*, und die prüft kein
   CI. **Die eine benannte Ausnahme ist der deklarierte Nebenbefund**; an ihre Stelle
   treten **drei Formprüfungen** — die Überschrift „Nebenbefund, hier mit erledigt" im PR-Body,
   die Ausschlussliste, das Kontingent —, und fällt eine, ist die Datei ein zweiter Zweck.
4. **Eine formdefinierende Zeile zusammen mit Feature-Code** ist ein gemischter Contract — der
   gehört als eigener, kleiner PR zuerst nach `dev`. Feld `contract`; **was formdefinierend
   heißt, steht einmal, unter „Regeln quer zum Ablauf"**.
5. **Mehr als eine neue Migrationsdatei, oder `alembic heads` ≠ 1**, ist ein Befund. Feld
   `migration` — gezählt **ohne** Alembic und damit über jeden fremden SHA.
6. **Geändertes dokumentiertes Verhalten ohne Doku-Diff** ist ein Befund.
7. **Der Frontend-Diff gegen die Do's and Don'ts der Design-Doku und „Frontend" in `CLAUDE.md`,
   der Backend-Diff gegen `CLAUDE.md` → „Architektur"**. Beide Hälften, weil eine allein für die
   Hälfte der Issues blind ist.
8. **Der PR-Body trägt `Closes #<nr>`**, einen Abschnitt „Entscheidungen" und die
   Gate-Marke. Feld `pr_body` — geprüft wird, **dass** der Abschnitt dasteht, nie was darin
   steht.

**Was CI und die Suite schon prüfen, wird hier nicht noch einmal geprüft** — deshalb
führt der Prüfer keine Tests aus. **Drei Urteile, mehr nicht:** `ok`, `befunde` (zurück an den
Entwickler, einmal), `zurueckgewiesen` — das letzte nur, wenn der Diff die Zusage *erfüllt*,
die Zusage selbst aber eine Regel aus `CLAUDE.md` bricht: dann ist das Issue falsch geschnitten,
nicht der PR.

**Runde 2 nennt nur Runde-1-Funde und Mängel des Reparatur-Diffs.** Was am unveränderten
Diff erst dann auffällt, hat Runde 1 versäumt: sie geht vor dem Urteil alle Prüfungen durch,
nicht bis zum ersten Fund.

**Kein Check-Run für den SHA heißt nicht „warten":** `mergeable_state: dirty` mit null Läufen ist
ein Konflikt, kein hängendes CI, Urteil `befunde` mit dem Grund „CI nicht gestartet". **An einem
Agent-PR sind übersprungene Check-Runs der Normalfall und kein Befund** (siehe 1), und `dirty`
bleibt trotzdem ein Konflikt. **Und `base.ref` ≠ Ziel-Branch ist ein Befund:** ein gestapelter
PR mergt auf seine Basis, wo das Aufräumen den Squash wegwirft.
