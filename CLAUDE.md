# Knot My Problem

Arbeitstitel: **Knot My Problem** (Alternative: *Wire We Here?*). Interner Name: Kabelsalat.
Ziel ist ein 3D-Incremental-Game mit offener Welt für Steam, später mit Koop für 2–4 Spieler.
Das vollständige Game Design Document liegt hier: https://claude.ai/artifact/1AGe969RxsVRD93hecZe8e
Repository: https://github.com/Julszify/Wire-We-Here (öffentlich, Branch `main`)

## Worum es geht

Drei Chefs der fiktiven „Wolkig AG“ ersetzen am Stammtisch die IT-Abteilung durch eine schnell zusammengebastelte KI namens **C.O.R.D.** (Cable Ordering & Repair Daemon). C.O.R.D. bestellt bei jedem defekten Kabel Ersatz, tauscht aber nie etwas aus. Die Kabelberge wachsen, bis die Cloud weltweit ausfällt. Der Spieler ist der gefeuerte IT-Admin, der das Chaos beseitigen soll.

Kernschleife: Kabelende finden → per Hand, Handkurbel oder Motorrolle aufwickeln → Knoten lösen → Geld. Gewöhnliche Kabel bringen Geld, wichtige Kabel gehören an feste Ports im Server-Schrank und reaktivieren Dienste (im fertigen Spiel 2000, im Slice 20).

## Aktueller Stand: Vertical Slice fertig (`v0.1-vertical-slice`)

Der Slice soll eine Frage beantworten: **Macht Ziehen und Aufrollen Spaß?** Er ist vollständig spielbar:

- **Zone „Schubladen-Ebene“** mit ca. 525 Kabeln auf einmal: großer Kabelberg (220), 6 Haufen, 70 Streukabel quer über den Boden (`data/zone.json`)
- **Spielfigur** in Third-Person; Fadenkreuz wird beim Anvisieren eines Kabelendes zur Hand
- **Werkzeug-Kette:** per Hand um den Arm wickeln → Handkurbel → Motorrollen (siehe unten)
- **Knoten:** Kabel stoppen an festen Stellen, 3× E löst sie
- **Geld** pro Meter mit schwebendem Betrag; **Tablet** (Tab) mit 6 Upgrades
- **Server-Schrank** mit 20 Ports; 20 wichtige Kabel leuchten, tragen ein Etikett und werden zu Knäueln, die man einsteckt; Dienste schalten Upgrades frei
- **C.O.R.D.** folgt dem Spieler und stellt die Bestellfalle (ohne „Nein“ fallen 100 Kabel vom Himmel)
- **Speichern und Laden** als JSON

Noch nicht enthalten und bewusst offen: Koop, Steam-Anbindung, weitere Zonen, Prestige, Story-Zwischensequenzen, finale Grafik, Sound. Die Architektur ist auf Koop vorbereitet (siehe unten).

## Nächste Schritte (Ideen, noch nicht entschieden)

1. **Spieltest auswerten:** Fühlt sich das Wickeln per Hand gut mühsam oder frustrierend an? Wann werden Kurbel und Motorrolle gekauft? Ist C.O.R.D.s Takt lustig oder nervig? Danach Balancing in `data/balancing.json` anpassen.
2. **Vierte Werkzeug-Stufe** festlegen (Vorschlag: Kabeltrommel-Wagen, den man mitzieht und der mehrere Kabel gleichzeitig aufnimmt).
3. **Wirkung für die übrigen 16 Dienste** (bisher nur grüne Lampe), z. B. Port 20 „C.O.R.D.-Abschaltknopf“.
4. **Optik:** Kabelenden am Rand des großen Bergs unregelmäßiger verteilen; Knäuel am Arm kompakter (wirkt eher wie ein Trichter); Zielstil Spielzeug-Look.
5. **Koop vorbereiten:** CableSystem, Economy, ServiceRack und CordLogic laufen später beim Host; Clients bekommen Zustand und senden Absichten.

## Technik

### Engine

**Godot 4.7 mit GDScript** (bestätigt). Szenen und Ressourcen sind Textdateien; das erleichtert die Arbeit mit Claude Code.
Starten: Projekt in Godot öffnen, F5. Kommandozeile: `/Applications/Godot.app/Contents/MacOS/Godot`.

### Kabel-Simulation (wichtigste Regel)

**Keine echte Seilphysik.** Jedes Kabel ist eine feste Kurve aus Punkten (zentripetale Catmull-Rom, gleichmäßig nach Bogenlänge abgetastet). Beim Ziehen gleitet das Kabel entlang dieser Bahn:

- Fortschritt `p = gezogene_meter / kabel_laenge` (0 bis 1)
- Der Teil im Haufen ist die Bahn von Index 0 (eingehängtes Ende) bis `(1 - p) * N`; das hintere Ende wandert also durch den Haufen nach vorne
- Vom eingehängten Ende führt ein Verbindungsstück zum Aufwickler (zur Rolle leicht nach oben gebogen, zum Arm durchhängend)
- Auf der Rolle liegt eine Spirale (Helix) Lage für Lage, am Arm ovale Schlaufen zwischen Hand und Ellbogen; sichtbare Länge `p * min(bahnlaenge, 18 m)`
- Die drei Teile werden zu einem Pfad verbunden und als Tube-Mesh gerendert; nur aktive Kabel werden pro Frame neu erzeugt

Gründe: günstig für tausende Kabel, stabil, und der Zustand eines Kabels besteht nur aus wenigen Werten (Kabel-ID, Rolle, gezogene Meter, Knoten-Status). Das ist später leicht übers Netzwerk zu synchronisieren.
Die Spiel-Länge eines Kabels (15–30 m, bestimmt Geld und Knoten) ist von der sichtbaren Bahn im Haufen entkoppelt.

Der ursprüngliche Browser-Prototyp liegt unter `reference/kabelsalat-3d.html` (three.js).

### Modelle aus Blender

Blender 5.3 liegt unter `/Applications/Blender.app/Contents/MacOS/Blender`. Modelle entstehen per Python-Skript in `tools/blender/` (reproduzierbar, Aufruf steht jeweils oben im Skript); `tools/` ist per `.gdignore` vom Godot-Import ausgenommen.

- `cord_designs.py` → `assets/models/cord/` (C.O.R.D. = Server-Box; Leuchtteile heißen `CordRing` und blinken per Code)
- `player_designs.py` → `assets/models/player/` (Hoodie-Admin; sieben Teile mit Ursprung im Gelenk, `player.gd` hängt sie an die Gelenk-Nodes, siehe `MODEL_PARTS`)
- `plug_designs.py` → `assets/models/cable/plugs.glb` (fünf Steckertypen mit Vertex-Farben; `PlugMeshes` schreibt sie als zweite Fläche ins Kabel-Mesh, Typ und Kabeldicke über `cable.plugs` in `balancing.json`)

Kabel und Haufen bleiben prozedural (siehe oben); Blender liefert nur feste Teile. Nach neuen `class_name`-Skripten einmal `godot --headless --import` ausführen, sonst kennt die Kommandozeile die Klasse nicht.

### Begehbare Welt (im Aufbau)

Konzept im GDD, Abschnitt „Welt und offene Map“: offene Kleinstadt, ca. 2 × 2 km, Basis im Wolkig-Hinterhof, zehn Viertel, viel Höhe.

- **Gelände:** Addon Terrain3D 1.1.0 (`addons/terrain_3d`, MIT, läuft mit Godot 4.7). `CityTerrain` erzeugt es aus `WorldLayout.height()`; die Höhenkarte wird in `user://city_height_<hash>.res` zwischengespeichert (erstes Mal ca. 7 s, danach unter 0,1 s). Ändert sich `height()`, `HEIGHT_VERSION` in `city_terrain.gd` erhöhen.
- **Layout als Daten:** `data/world.json` (Viertel als Rechtecke mit Bodenhöhe und Rampenbreite, Hügel, Küste, Krater, Hafenbecken, Landmarken, Startpunkt); `scripts/world/world_layout.gd` liest es.
- **Vorschau:** `scenes/city_preview.tscn` (F6), Optionen `--viertel=<id>`, `--at=<x>,<z>`, `--orbit=<grad>`, `--overview` (Luftbild), `--tour` (FPS je Viertel). Enthält einen Absturz-Schutz (unter das Gelände gerutscht → wieder hochsetzen).
- Die Hauptszene `world.tscn` nutzt die Stadt noch nicht; Bauplan: Blockout der Viertel per Blender, Landmarken, Startbereich in den Hinterhof, Sperren, dann Springen/Klettern, zuletzt Laden pro Viertel.

### Werkzeug-Kette und Eingabe

Der Fortschritt soll sich spürbar beschleunigen, das ist der Reiz:

1. **Per Hand (Start):** Die Figur wickelt das Kabel zwischen Hand und Ellbogen um den Arm. Eine Taste muss **wiederholt gedrückt** werden; das ist absichtlich mühsam. Solange ein Kabel am Arm hängt, hält eine Leine (6 m) die Figur beim Haufen.
2. **Handkurbel (erstes Upgrade):** aufstellbare Rolle mit Kurbel, deutlich mehr Meter pro Tastendruck.
3. **Motorrolle:** zieht automatisch; mehrere kaufbar.
4. **Mehr:** noch offen (siehe „Nächste Schritte“).

Upgrade **„Dauerzug“**: Taste gedrückt halten statt wiederholt drücken.

**Steuerung (Eingabe-Aktionen in project.godot):** WASD laufen, Shift rennen, Maus umsehen, Esc Maus freigeben.
E: Kabelende greifen, Kabel vom Arm an anvisierte Rolle hängen, Knoten lösen (3 Drücke), Knäuel aufheben bzw. in den Schrank stecken.
Leertaste/Linksklick: wickeln bzw. kurbeln. Q: Kabel loslassen (Fortschritt geht verloren) bzw. Knäuel ablegen.
Tab: Tablet (Spiel läuft weiter). N: „Nein“ zu C.O.R.D.s Bestellfrage. F5 speichern, F9 laden.

**Wichtige Kabel:** genau 20 in der Zone, zufällig verteilt (eins pro Port), leuchten und tragen ein Etikett (Port + Dienst). Man rollt sie normal auf; sie bringen den halben Meterpreis und werden zu einem beschrifteten Knäuel, das man zum Server-Schrank trägt und mit E einsteckt. Reaktivierte Dienste schalten Upgrades frei (`data/services.json`, Feld `unlocks`): Port 1 Festerer Griff, Port 2 Dauerzug, Port 3 Stärkere Motoren, Port 5 Kupferhändler.

**C.O.R.D.:** erste Bestellfrage nach 30 s, danach alle 45–90 s; 6 s Zeit für N, sonst fallen 100 Kabel als neuer Haufen in Blickrichtung neben den Spieler.

**Speichern:** `user://savegame.json` (macOS: `~/Library/Application Support/Godot/app_userdata/Knot My Problem/`), automatisch alle 30 s und beim Schließen. Gespeichert werden nur Seeds und veränderlicher Zustand; Kabelformen entstehen beim Laden neu. Datei hat eine Versionsnummer; kaputte oder fremde Versionen werden ignoriert. „Neues Spiel“ im Tablet löscht den Stand.

### Startwerte für das Balancing

Maßgeblich ist `data/balancing.json` (alle Werte dort, nicht im Code).

| Wert | Start | Upgrade |
| --- | --- | --- |
| Kabellänge (Spiel-Länge) | 15–30 m | – |
| Geld pro Meter | 0,50 € (wichtige Kabel: halber Preis) | Kupferhändler ×1,35, Kosten 60 € × 2,3^Stufe |
| Handzug per Hand (Arm) | 0,25 m pro Tastendruck | Festerer Griff ×1,5, Kosten 10 € × 1,9^Stufe |
| Handkurbel | 0,75 m pro Tastendruck | Kauf 8 €, einmalig |
| Dauerzug | – | Halten = 4 Züge/s, 30 €, einmalig |
| Motorrolle | 0,25 m/s | Stärkere Motoren ×1,4, Kosten 40 € × 2,2^Stufe |
| Weitere Motorrolle | – | Kosten 15 € × 1,8^Anzahl, max. 8 |
| Knoten pro Kabel | 0–2, bei 20–85 % der Länge | – |

### Architektur

- **Daten getrennt von Darstellung:** Spielzustand als reine Daten (`*_data.gd`, `GameState`, `CoilItem`); Logik in Nodes ohne Grafik (`CableSystem`, `Economy`, `ServiceRack`, `CordLogic`); Darstellung in `*_view.gd`. `scripts/core/world.gd` verdrahtet alles.
- **Deterministisch:** Zufall nur über Seeds; Zone, Haufen, wichtige Kabel und C.O.R.D.-Timing sind reproduzierbar (Grundlage für Speichern und Koop).
- **Signale statt direkter Abhängigkeiten**, z. B. `cable_completed`, `knot_hit`, `service_activated`, `order_requested`.

```
/data        balancing.json (Werte), zone.json (Anordnung), services.json (Dienste je Port)
/scenes      world.tscn (Hauptszene), player.tscn, reel_test.tscn (Rollen-Testszene)
/scripts     cable/   Bahn, Tube-Mesh, Kabeldaten, Haufen, Zone, CableSystem
             reel/    Aufwickler-Daten (Arm, Kurbel, Motor) und Rollen-Darstellung
             rack/    Server-Schrank, Knäuel
             economy/ Geld und Upgrades
             cord/    C.O.R.D.-Logik und -Figur
             save/    Spielstand
             player/  Spielfigur, Anvisieren
             ui/      Fadenkreuz, Tablet, C.O.R.D.-Anzeige, schwebender Text
             core/    Balancing (Autoload), GameState, World
             debug/   Testkameras und -aufbauten
/tests       logic_test.tscn (automatischer Logik-Test)
/reference   Browser-Prototyp
/assets      (noch leer) Platzhalter-Modelle und -Materialien
```

### Testen

- **Logik-Test:** `godot --headless res://tests/logic_test.tscn` muss „ALLE TESTS OK“ ausgeben.
- **Testoptionen** für die Hauptszene (nach `--`): `--nosave` (ohne Spielstand starten/speichern), `--savefile=<pfad>`, `--dump` / `--dumpafter=<frames>` (Zustand ausgeben), `--grab`, `--pull=<m>`, `--buy=<ids>`, `--hang`, `--order`, `--ask` usw.; vollständige Liste in `world.gd` → `_apply_test_args`. Für Testläufe immer `--nosave` verwenden, sonst wird der echte Spielstand geladen.
- **Bilder rendern:** `godot --write-movie <pfad>.png --quit-after 3 -- --nosave ...`

### Technische Hinweise

- In `.tscn`-Dateien Drehungen als `rotation = Vector3(...)` schreiben, nicht als Transform3D-Matrix; Godot speichert die Matrix zeilenweise, das führt leicht zu gespiegelten Drehungen.
- Controls, die per Code ganzflächig sein sollen: `set_anchors_and_offsets_preset`, nicht nur `set_anchors_preset`.
- In zsh werden Variablen nicht in Wörter aufgeteilt: Optionen aus einer Variablen mit `${=var}` übergeben.

## Arbeitsweise

- In kleinen, spielbaren Schritten arbeiten; nach jedem Schritt kurz sagen, wie ich es testen kann
- Bei größeren Entscheidungen (Engine-Details, Steuerung, Architekturänderungen) vorher fragen
- Code-Bezeichner auf Englisch, Kommentare und Texte im Spiel auf Deutsch
- Platzhaltergrafik ist ausdrücklich in Ordnung; der Zielstil (Spielzeug-Look, rundliche Figuren, glänzende Kabel) kommt später
- Committen und pushen erst nach Rückmeldung

## Verlauf des Vertical Slice

1. ✅ Godot-Projekt, Ordnerstruktur, Testszene
2. ✅ Ein Kabel als Tube-Mesh aus einer zufälligen Kurve
3. ✅ Kabel an Rolle ziehen und aufwickeln
4. ✅ Spielfigur, Haufen, Anvisieren, Wickeln per Hand um den Arm
5. ✅ Geld, Knoten, Handkurbel, Motorrolle
6. ✅ Tablet-Menü (inkl. Dauerzug), Server-Schrank mit 20 Ports, wichtige Kabel
6.5 ✅ Ganze Zone voller Kabel auf einmal (ca. 525)
7. ✅ C.O.R.D.-Platzhalter und Bestellfalle
8. ✅ Speichern und Laden als JSON
- ✅ Nach Spieltest: Leine nur bei Kabel am Arm (Weg zum Schrank war blockiert), wichtige Kabel bringen halben Meterpreis
