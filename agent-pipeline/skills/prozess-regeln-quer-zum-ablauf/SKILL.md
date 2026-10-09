---
# Adapted excerpt from a private project
name: prozess-regeln-quer-zum-ablauf
description: >-
  Was unabhaengig von der Station gilt: Contract-PR zuerst, eine Migration je Issue, der Nebenbefund unter zehn Zeilen.
metadata:
  abschnitt: "Regeln quer zum Ablauf"
  reihenfolge: 12
---

## Regeln quer zum Ablauf

Wo eine dieser Regeln und die neun Schritte dasselbe sagen, gilt der Ablauf.

- **Auf dem eigenen Feature-Branch und auf `dev` wird automatisch committet und gepusht**;
  **`main` ist ausgenommen.**
- **Ein Issue, ein Branch, ein PR.** Wächst ein Issue beim Bauen über sich hinaus, wird es geteilt
  — das neue Stück ist ein neues Issue, nicht ein zweiter Zweck im selben Branch.
- **Ein Sammelpaket prüft seine Fundstellen erneut, bevor die erste Zeile entsteht** — ein
  Issue-Body beschreibt den Zustand beim **Anlegen**, und zwischen Anlegen und Bauen wird
  gemergt. **Jede genannte Fundstelle wird gegen `origin/dev` gehalten**, und eine, die es dort
  nicht mehr gibt, **ist ein Befund und kein Auftrag**. **Der Nachweis steht im PR-Body**: welche
  Teilzusagen vorab eingelöst waren und wodurch, denn „war schon erledigt" und „übersehen" sehen
  im Diff gleich aus. **Neu erfunden wird ein zitierter Wortlaut nie** — ein `bad revision` ist
  ein Lesefehler und kein Beleg dafür, dass es die Fundstelle nicht gab.
- **Änderungen am Wire-Contract gehen als eigener, kleiner PR zuerst** nach `dev` — sonst
  entsteht die Drift zwischen Backend und Frontend-Typen. **Entscheidend ist die geänderte Zeile,
  nicht die Datei**; formdefinierend: im API-Modul die Zeilen, die ein Antwortmodell
  **definieren**, in `types.ts` eine **Typdeklaration** (`interface`, `type`, `enum`) oder
  **Felddeklaration** (`name:`), im Socket-Modul ein Eintrag in den Event-Interfaces.
  **Nicht formdefinierend:** ein Modell **anwenden**, **Kommentar**, **Werteliste**,
  Beschreibungstext. **Eine Deklaration ist nicht immer eine Zeile**: die Fortsetzung zählt zur
  umschließenden, außerhalb des Hunks der **Hunk-Kopf**.
- **Eine Migration pro Issue, eigene Datei**; vorher nachsehen, ob schon eine mit demselben
  `down_revision` existiert, denn zwei davon sind ein Migrations-Branch, der erst beim Start
  auffällt.
- **Doku gehört in den PR, der sie verursacht**; Querschnittliches geht direkt auf `dev`.
- **Ein Nebenbefund unter zehn Zeilen wird im Branch erledigt, nicht zum Issue** — nicht
  die Doku, die die Änderung **verursacht**, sondern ein Befund, der beim Bauen **auffällt** und
  kleiner ist als der Aufwand, ihn zu verwalten. Weil „ein zweiter Zweck im Branch" verboten
  bleibt, zieht die Regel eine als **Form** prüfbare Grenze:
  - **Der `entwickler` deklariert, der `pr-pruefer` prüft die Deklaration:** im PR-Body unter
    **„Nebenbefund, hier mit erledigt"**, je Befund eine Zeile aus `datei:zeile`, einem Satz und
    der Zahl der geänderten Zeilen. **Ohne Deklaration ist es ein zweiter Zweck.**
  - **Hartes Kontingent: höchstens zwei Nebenbefunde, zusammen höchstens zehn geänderte Zeilen**,
    die deklarierte Zahl gegen `git diff --stat` gehalten. **Ausgeschlossen unabhängig von der
    Größe** — dort wirkt eine kleine Änderung groß —: Tests, Migrationen, Wire-Contract,
    `settings.json`, `.claude/hooks/*`, `.claude/agents/*`.
  - **Was einen Test bräuchte, um belegt zu sein, ist kein Nebenbefund**, und
    **eine neue Regel oder Entscheidung** ist nie einer. **Was nicht hineinpasst, geht in
    `befunde[]`.**
- **Commit-Messages nennen das Issue:** `feat: <englischer Satz> (#<nr>)`.
