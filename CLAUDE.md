# Knot My Problem – Projektübergabe

Arbeitstitel: **Knot My Problem** (Alternative: *Wire We Here?*). Interner Name: Kabelsalat.
Ziel ist ein 3D-Incremental-Game mit offener Welt für Steam, später mit Koop für 2–4 Spieler.
Das vollständige Game Design Document liegt hier: https://claude.ai/artifact/1AGe969RxsVRD93hecZe8e

## Worum es geht

Drei Chefs der fiktiven „Wolkig AG“ ersetzen am Stammtisch die IT-Abteilung durch eine schnell zusammengebastelte KI namens **C.O.R.D.** (Cable Ordering & Repair Daemon). C.O.R.D. bestellt bei jedem defekten Kabel Ersatz, tauscht aber nie etwas aus. Die Kabelberge wachsen, bis die Cloud weltweit ausfällt. Der Spieler ist der gefeuerte IT-Admin, der das Chaos beseitigen soll.

Kernschleife: Kabelende finden → an Handkurbel oder Motorrolle einhängen → ziehen → Knoten lösen → Kabel rollt sich auf → Geld. Gewöhnliche Kabel bringen Geld, 2000 wichtige Kabel gehören an feste Ports im Server-Schrank und reaktivieren Dienste.

## Aktueller Auftrag: Vertical Slice (solo)

Eine kleine, spielbare Version, die nur eine Frage beantwortet: **Macht Ziehen und Aufrollen Spaß?**

### Enthalten

- Eine Zone („Schubladen-Ebene“) mit 2–3 kleinen Kabelhaufen à 10–30 Kabel
- Spielfigur in Third-Person, frei begehbar, mit Fadenkreuz, das beim Anvisieren eines Kabelendes zur Hand wird
- Handkurbel (manuelles Ziehen per Taste) und aufstellbare Motorrolle (zieht automatisch)
- Knoten: Kabel bleiben an festen Stellen hängen und müssen per Taste gelöst werden
- Geld pro aufgerolltem Meter, schwebendes „+12 €“ über der Rolle
- Mini-Server-Schrank mit 20 Ports; wichtige Kabel leuchten schwach und tragen ein Etikett
- Drei Upgrades über ein einfaches Tablet-Menü: Festerer Griff, Stärkere Motoren, Weitere Motorrolle
- C.O.R.D. als einfacher Platzhalter (Zylinder mit Leuchtring), der dem Spieler folgt
- Bestellfalle: C.O.R.D. fragt gelegentlich „Defektes Kabel erkannt. Ersatz bestellen?“; wird nicht rechtzeitig „Nein“ gedrückt, fallen 100 Kabel als neuer Haufen neben den Spieler
- Speichern und Laden als JSON

### Ausdrücklich nicht enthalten

Koop, Steam-Anbindung, weitere Zonen, Prestige, Story-Zwischensequenzen, finale Grafik, Sound über Platzhalter hinaus. Bitte die Architektur aber so anlegen, dass Koop später möglich ist (siehe unten).

## Technik

### Engine

Vorschlag: **Godot 4 mit GDScript**. Szenen und Ressourcen sind Textdateien, das macht die Arbeit mit Claude Code einfacher. Falls ich mich doch für Unity entscheide, sage ich Bescheid, bevor Code entsteht.

### Kabel-Simulation (wichtigste Regel)

**Keine echte Seilphysik.** Jedes Kabel ist eine feste Kurve aus Punkten (z. B. Catmull-Rom, gleichmäßig nach Bogenlänge abgetastet). Beim Ziehen gleitet das Kabel entlang dieser Bahn:

- Fortschritt `p = gezogene_meter / kabel_laenge` (0 bis 1)
- Der Teil im Haufen ist die Bahn von Index 0 (eingehängtes Ende) bis `(1 - p) * N`; das hintere Ende wandert also durch den Haufen nach vorne
- Vom eingehängten Ende führt ein kurzes Verbindungsstück (leicht nach oben gebogen) zur Rolle
- Auf der Rolle liegt eine Spirale (Helix) mit der Länge `p * bahnlaenge`, Lage für Lage
- Die drei Teile werden zu einem Pfad verbunden und als Tube-Mesh gerendert; nur aktive Kabel werden pro Frame neu erzeugt

Gründe: günstig für tausende Kabel, stabil, und der Zustand eines Kabels besteht nur aus wenigen Werten (Kabel-ID, Rolle, gezogene Meter, Knoten-Status). Das ist später leicht übers Netzwerk zu synchronisieren.

Ein funktionierender Browser-Prototyp dieser Technik liegt als `kabelsalat-3d.html` bei (three.js). Die Funktionen `spawnCable`, `coilPts`, `rebuild` und `advance` zeigen das Prinzip.

### Werkzeug-Kette und Eingabe (entschieden nach M3)

Der Fortschritt soll sich spürbar beschleunigen, das ist der Reiz:

1. **Per Hand (Start):** Die Spielfigur wickelt das Kabel zwischen Hand und Ellbogen um den Arm. Eine Taste muss **wiederholt gedrückt** werden; das ist absichtlich mühsam. Fertige Knäuel werden abgelegt.
2. **Handkurbel (erstes Upgrade):** aufstellbare Rolle mit Kurbel, deutlich mehr Meter pro Tastendruck.
3. **Motorrolle:** zieht automatisch.
4. **Mehr:** eine weitere Stufe wird im Slice angedeutet (noch offen).

Upgrade **„Dauerzug“**: Taste gedrückt halten statt wiederholt drücken.

**Steuerung (Platzhalter, Eingabe-Aktionen in project.godot):** WASD laufen, Shift rennen, Maus umsehen, E Kabelende greifen, Leertaste/Linksklick ziehen bzw. wickeln, Q loslassen (Fortschritt geht verloren), Esc Maus freigeben. Mit Kabel am Arm eine Rolle anvisieren + E = einhängen; Knoten mit E lösen (3 Drücke). Tab öffnet das Tablet (Upgrades kaufen, Spiel läuft weiter); N sagt „Nein“ zu C.O.R.D.s Bestellfrage; gekaufte Rollen werden vor der Figur aufgestellt.

**Wichtige Kabel (entschieden in M6, angepasst in M6.5):** genau 20 in der ganzen Zone, zufällig verteilt, leuchten und tragen ein Etikett (Port + Dienst). Man rollt sie normal auf; statt Geld entsteht ein beschriftetes Knäuel, das man zum Server-Schrank trägt und mit E einsteckt (Q legt es ab). Ports werden der Reihe nach vergeben. Reaktivierte Dienste schalten Upgrades frei (`data/services.json`, Feld `unlocks`).

**Testoptionen:** `--nosave` (ohne Spielstand starten/speichern), `--savefile=<pfad>`, `--dump` (Zustand ausgeben), weitere in `world.gd` → `_apply_test_args`.

**Logik-Test:** `godot --headless res://tests/logic_test.tscn` muss „ALLE TESTS OK“ ausgeben.

**Technischer Hinweis:** In `.tscn`-Dateien Drehungen als `rotation = Vector3(...)` schreiben, nicht als Transform3D-Matrix; Godot speichert die Matrix zeilenweise, das führt leicht zu gespiegelten Drehungen.

### Startwerte für das Balancing

Ursprünglich aus dem Prototyp, nach M3 angepasst. Maßgeblich ist `data/balancing.json`.

| Wert | Start | Upgrade |
| --- | --- | --- |
| Kabellänge (Spiel-Länge) | 15–30 m | – |
| Geld pro Meter | 0,50 € (wird in M5 neu austariert) | Kupferhändler ×1,35 |
| Handzug per Hand (Arm) | 0,25 m pro Tastendruck | Festerer Griff ×1,5, Kosten 10 € × 1,9^Stufe |
| Handkurbel | 0,75 m pro Tastendruck | Kauf als Upgrade, 8 € |
| Dauerzug | – | Halten = 4 Züge/s, 30 € |
| Motorrolle | 0,25 m/s | Stärkere Motoren ×1,4, Kosten 40 € × 2,2^Stufe |
| Weitere Motorrolle | – | Kosten 15 € × 1,8^Anzahl, max. 8 |
| Knoten pro Kabel | 0–2, bei 20–85 % der Länge | – |

Die Spiel-Länge ist von der sichtbaren Bahn im Haufen (ca. 15–20 m) entkoppelt.

Alle Werte gehören in Datendateien (Godot-Resources oder JSON), nicht in den Code.

### Architektur

- **Daten getrennt von Darstellung:** Spielzustand (Kabel, Rollen, Geld, Schrank) als reine Daten; Szenen lesen ihn nur aus
- **Deterministisch:** Zufall nur über einen Seed, damit Haufen reproduzierbar sind (wichtig für Speichern und späteren Koop)
- **Signale statt direkter Abhängigkeiten**, z. B. `cable_completed`, `knot_hit`, `order_requested`
- Vorschlag für die Ordnerstruktur:

```
/scenes      Spielwelt, Spieler, Rolle, Schrank, UI
/scripts     cable/, reel/, economy/, cord/, save/
/data        Balancing-Werte, Upgrade-Definitionen
/assets      Platzhalter-Modelle und -Materialien
```

## Arbeitsweise

- In kleinen, spielbaren Schritten arbeiten; nach jedem Schritt kurz sagen, wie ich es testen kann
- Bei größeren Entscheidungen (Engine-Details, Steuerung, Architekturänderungen) vorher fragen
- Code-Bezeichner auf Englisch, Kommentare und Texte im Spiel auf Deutsch
- Platzhaltergrafik ist ausdrücklich in Ordnung; der Zielstil (Spielzeug-Look, rundliche Figuren, glänzende Kabel) kommt später

## Meilensteine für den Vertical Slice

1. ✅ Godot-Projekt anlegen, Ordnerstruktur, leere Testszene mit Boden und Kamera
2. ✅ Ein einzelnes Kabel als Tube-Mesh aus einer zufälligen Kurve erzeugen
3. ✅ Kabel an eine Rolle hängen und per Taste ziehen, inklusive Aufwickeln
4. ✅ Haufen mit 20 Kabeln, Spielfigur, Anvisieren, Kabelende greifen und per Hand um den Arm wickeln
5. ✅ Geld, Knoten, Handkurbel als erstes Upgrade, Motorrolle
6. ✅ Upgrade-Menü (inkl. Dauerzug), Server-Schrank mit 20 Ports, wichtige Kabel
6.5 ✅ Ganze Zone voller Kabel auf einmal: großer Kabelberg, 6 Haufen und Streukabel (ca. 525 Kabel, `data/zone.json`), genau 20 wichtige Kabel zufällig verteilt
7. ✅ C.O.R.D.-Platzhalter und Bestellfalle (erste Frage nach 30 s, dann alle 45–90 s, 6 s Zeit für „Nein“, sonst fallen 100 Kabel neben den Spieler)
8. ✅ Speichern und Laden (JSON unter user://savegame.json; automatisch alle 30 s und beim Schließen, F5 speichern, F9 laden, „Neues Spiel“ im Tablet; gespeichert werden nur Seeds + veränderlicher Zustand)

Engine: Godot 4.7 mit GDScript (bestätigt).
