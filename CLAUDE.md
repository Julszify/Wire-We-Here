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
- **Serverraum** (begehbare Halle im Hinterhof) mit zehn Schränken und 2000 Ports; wichtige Kabel leuchten, tragen ein Etikett und werden zu Knäueln, die man in der Tasche sammelt und im Serverraum einsteckt; Dienste schalten Upgrades frei oder wirken dauerhaft
- **C.O.R.D.** folgt dem Spieler und stellt die Bestellfalle (ohne „Nein“ fallen 100 Kabel vom Himmel)
- **Speichern und Laden** als JSON

Noch nicht enthalten und bewusst offen: Koop, Steam-Anbindung, weitere Zonen, Prestige, Story-Zwischensequenzen, finale Grafik, Sound. Die Architektur ist auf Koop vorbereitet (siehe unten).

## Nächste Schritte (Ideen, noch nicht entschieden)

1. **Echten Spieltest auswerten:** Fühlt sich das Wickeln per Hand gut mühsam oder frustrierend an? Ist C.O.R.D.s Takt lustig oder nervig? Die Verlaufs-Rechnung (`tests/balance_sim.tscn`) zeigt nur Zeiten, kein Spielgefühl. Danach Balancing in `data/balancing.json` anpassen.
2. **Vierte Werkzeug-Stufe** festlegen (Vorschlag: Kabeltrommel-Wagen, den man mitzieht und der mehrere Kabel gleichzeitig aufnimmt). Wichtig für die Stadt: Kurbel und Motorrollen stehen fest, wo sie gekauft wurden; im Wohnviertel wickelt man bisher nur per Hand.
3. **Balancing:** Werkzeuge sind angeglichen (Hand voll aufgerüstet ca. 10 m/s, Motorrolle ca. 20 m/s, jeweils plus Dienst-Boni). Laut Verlaufs-Rechnung bestimmen jetzt Greifen und Laufwege die Spielzeit, nicht mehr das Wickeln. Geld-Senken fehlen: nach gut 1,5 Stunden ist alles gekauft.
4. **Optik:** Knäuel am Arm kompakter (wirkt eher wie ein Trichter; die fertigen Knäuel sind schon ordentliche Kabelringe); echte Gebäudemodelle für weitere Viertel; Anzeige (HUD) im Spielzeug-Look.
5. **Koop vorbereiten:** CableSystem, Economy, ServiceRack und CordLogic laufen später beim Host; Clients bekommen Zustand und senden Absichten.

## Technik

### Engine

**Godot 4.7 mit GDScript** (bestätigt). Szenen und Ressourcen sind Textdateien; das erleichtert die Arbeit mit Claude Code.
Starten: Projekt in Godot öffnen, F5. Kommandozeile: `/Applications/Godot.app/Contents/MacOS/Godot`.

### Kabel-Simulation (wichtigste Regel)

**Keine echte Seilphysik.** Jedes Kabel ist eine feste Kurve aus Punkten (zentripetale Catmull-Rom, gleichmäßig nach Bogenlänge abgetastet). Beim Ziehen gleitet das Kabel entlang dieser Bahn:

- Fortschritt `p = gezogene_meter / kabel_laenge` (0 bis 1)
- Der Teil im Haufen ist die Bahn von Index 0 (eingehängtes Ende) bis `(1 - p) * N`; das hintere Ende wandert also durch den Haufen nach vorne
- Vom eingehängten Ende führt ein Verbindungsstück zum Aufwickler: locker liegt es leicht geschlängelt am Boden und hebt sich erst auf dem letzten Stück; beim Ziehen strafft es sich zur geraden Linie, am Knoten bleibt es gespannt und zittert (Spannung nur in der Darstellung, `CableView.update_tension`, Werte in `balancing.json` → `connector`)
- Auf der Rolle liegt eine Spirale (Helix) Lage für Lage, Kabel an Kabel, und das Kabel läuft tangential ein; am Arm läuft die Wicklung wie auf einer Spule um den Unterarm (Ellbogen bis Hand und zurück, Lage für Lage dicker). Sichtbare Länge `p * min(bahnlaenge, 18 m)`, am Arm höchstens 6,5 m
- Die drei Teile werden zu einem Pfad verbunden und als Tube-Mesh gerendert; nur aktive Kabel werden pro Frame neu erzeugt

Gründe: günstig für tausende Kabel, stabil, und der Zustand eines Kabels besteht nur aus wenigen Werten (Kabel-ID, Rolle, gezogene Meter, Knoten-Status). Das ist später leicht übers Netzwerk zu synchronisieren.
Die Spiel-Länge eines Kabels (15–30 m, bestimmt Geld und Knoten) ist von der sichtbaren Bahn im Haufen entkoppelt.

Der ursprüngliche Browser-Prototyp liegt unter `reference/kabelsalat-3d.html` (three.js).

### Modelle aus Blender

Blender 5.3 liegt unter `/Applications/Blender.app/Contents/MacOS/Blender`. Modelle entstehen per Python-Skript in `tools/blender/` (reproduzierbar, Aufruf steht jeweils oben im Skript); `tools/` ist per `.gdignore` vom Godot-Import ausgenommen.

- **C.O.R.D.:** `assets/models/cord/tripo/cord_tripo.glb` (Tripo3D, eine Textur). `CordView` verkleinert es auf 0,8 m und legt ein eigenes Leuchtband über das Band in der Textur (`TRIPO_BAND_Y`/`TRIPO_BAND_H`), das cyan leuchtet und bei der Bestellfrage rot blinkt. Fehlt die Datei, kommt der Blender-Entwurf:
- `cord_designs.py` → `assets/models/cord/` (C.O.R.D. = Server-Box; Leuchtteile heißen `CordRing` und blinken per Code)
- **Spielfigur:** `assets/models/player/tripo/admin_tripo.glb` (in Tripo3D erzeugt, Mixamo-Skelett, ca. 1 m hoch, schaut nach +Z). `player.gd` lädt es unter den Körper (180° gedreht, ×1,75) und stellt die Knochen per Code (`_pose_rig`): Beine und Arme schwingen beim Laufen, mit Kabel zeigt der linke Unterarm nach vorn, an der Seilbahn gehen die Arme hoch. Achtung: Bei diesem Rig hängt der Oberarm fast ganz am Schulter-Knochen, deshalb werden Schulter und Arm gemeinsam ausgerichtet, und die Arme werden nur mäßig abgesenkt (steiler verschwinden sie im Bauch). `arm_transform()` liefert die Lage des linken Unterarm-Knochens für die Kabel-Wicklung. Fehlt die Datei, nimmt `player.gd` die Einzelteile aus `player_designs.py` (`MODEL_PARTS`). Animationen gibt es noch keine; wegen des Mixamo-Skeletts ließen sich Mixamo-Animationen später verwenden.
- `player_designs.py` → `assets/models/player/` (Hoodie-Admin aus Einzelteilen, Rückfall-Figur); `player_toy_designs.py` → Entwürfe im Spielzeug-Stil (`assets/models/player/proposals/toy_*`)
- `plug_designs.py` → `assets/models/cable/plugs.glb` (fünf Steckertypen mit Vertex-Farben; `PlugMeshes` schreibt sie als zweite Fläche ins Kabel-Mesh, Typ und Kabeldicke über `cable.plugs` in `balancing.json`)
- **Ausstattung aus Tripo3D:** Bäume (4× rund, 2× Nadel, Herbst), Büsche, Blumenkübel, Felsen und zwei Laternen in `assets/models/props/tripo/`. Übernommen mit `tools/blender/import_tripo_props.py` (Polygonzahl auf 2.000–5.000 reduziert, UV-Grenzen erhalten, Normal Map entfernt, Texturen auf 1024 px). `YardProps.TRIPO` ordnet sie den Teilnamen zu (Höhe, Drehung, Leuchtkugel bei Laternen); ein MultiMesh je Variante, Variante per Standort. Fehlt eine Datei, gilt das Blender-Teil. Die Altstadt-Laterne (`LampOld`) ist noch nirgends aufgestellt.
- `prop_designs.py` → `assets/models/props/yard_props.glb` (Ausstattung des Hinterhofs: Bäume, Büsche, Pflanzkübel, Bank, Laterne, Paletten, Müllcontainer, Kabeltrommel, Lieferwagen, Zaunfeld). `YardProps` stellt sie laut `zone.json` → `props` auf (feste Stücke in `items`, Bäume und Büsche am Hofrand per Seed in `ring`), ein MultiMesh je Modell, Kollision als Kisten; Lieferungen landen nicht darauf.
- `building_kit.py` → `assets/models/buildings/kit.glb` (Gebäude-Bausatz: Dächer als Einheitsmodelle – Sattel-, Walm-, Mansard-, Flach- und Sheddach –, Markise, Ladenschild, dazu Aufbauten in echter Größe: Klimagerät, Wassertank, Antenne, Schüssel, Schornstein, Solarmodule, Lüfter, Oberlicht, Hubschrauberlandeplatz, Leuchtschild, Werbetafel, Flutlichtmast). Vertex-Alpha: 1,0 = wird je Gebäude eingefärbt, 0,8 = feste Farbe, 0,5 = leuchtet.
- `building_designs.py` → `assets/models/buildings/` (`houses.glb`: vier Wohnhäuser als Einheitsmodelle 1 × 1 × 1 m, Vorderseite +Z, Godot skaliert sie aufs Grundstück; `server_room.glb`: Hülle des Serverraums mit den Maßen aus `balancing.json` → `server_room`; Farben als Vertex-Farben)

Kabel und Haufen bleiben prozedural (siehe oben); Blender liefert nur feste Teile. Nach neuen `class_name`-Skripten einmal `godot --headless --import` ausführen, sonst kennt die Kommandozeile die Klasse nicht.

### Begehbare Welt (im Aufbau)

Konzept im GDD, Abschnitt „Welt und offene Map“: offene Kleinstadt, ca. 2 × 2 km, Basis im Wolkig-Hinterhof, zehn Viertel, viel Höhe.

- **Gelände:** Addon Terrain3D 1.1.0 (`addons/terrain_3d`, MIT, läuft mit Godot 4.7). `CityTerrain` erzeugt es aus `WorldLayout.height()`; die Höhenkarte wird in `user://city_height_<hash>.res` zwischengespeichert (erstes Mal ca. 7 s, danach unter 0,1 s). Ändert sich `height()`, `HEIGHT_VERSION` in `city_terrain.gd` erhöhen.
- **Layout als Daten:** `data/world.json` (Viertel als Rechtecke mit Bodenhöhe und Rampenbreite, Hügel, Küste, Krater, Hafenbecken, Landmarken, Startpunkt); `scripts/world/world_layout.gd` liest es.
- **Vorschau:** `scenes/city_preview.tscn` (F6), Optionen `--viertel=<id>`, `--at=<x>,<z>`, `--orbit=<grad>`, `--overview` (Luftbild), `--cam=<x>,<z>,<Höhe>,<Ziel-x>,<Ziel-z>` (freie Kamera), `--tour` (FPS je Viertel). Enthält einen Absturz-Schutz (unter das Gelände gerutscht → wieder hochsetzen).
- **Boden:** sieben kachelbare Bodentexturen (Gras, Pflaster, Platten, Beton, Sand, Kies, Fels) in `assets/textures/terrain/`, erzeugt von `scripts/debug/make_terrain_textures.gd` (`godot --headless -s res://scripts/debug/make_terrain_textures.gd`). Welcher Boden wo liegt, bestimmt `WorldLayout.ground_at()` (Viertel laut `ground` in `world.json`, Rampen weich zu Gras, Krater Kies, Küste Sand, an steilen Hängen Fels); `CityTerrain.build_maps()` schreibt daraus die Terrain3D-Steuerkarte (zwischengespeichert zusammen mit der Höhenkarte, `MAPS_VERSION`).
- **Blockout:** `CityBlockout` erzeugt beim Start Straßenraster, Hauptstraßen und ca. 800 graue Gebäude mit Kollision aus den `blockout`-Regeln je Viertel in `world.json` (Godot statt Blender, weil nur Godot die Geländehöhen kennt). Viertel mit `"models": "houses"` (bisher das Wohnviertel) bekommen statt der Kisten Hausmodelle aus Blender: ein MultiMesh je Modell, Haustür zur Straße, Kollision bleibt die Kiste.
- **Spielzeug-Look:** `ToonLook` (`scripts/world/toon_look.gd`) stellt alle StandardMaterial3D auf Toon-Schattierung um (auch später hinzugefügte Nodes) und hängt die Umrisslinien (`assets/shaders/outline.gdshader`, Nachbearbeitung vor der Kamera: Kanten aus Tiefe und Normalen, blendet ab ca. 40–140 m aus) an die Kamera. Eigene Shader setzen `render_mode diffuse_toon, specular_toon`.
- **Gebäude-Bausatz:** Jedes Viertel mit `blockout.kit` in `world.json` bekommt einen Fassadenstil im Blockout-Shader (Büro, Altstadt mit Fensterläden und Schaufenstern, Läden mit Schilderstreifen, Halle mit Rolltoren, Rechenzentrum, Hochhaus) und Teile aus `kit.glb`: Dach je Gebäude (gewichtet aus `roofs`, Farbe aus `roof_palette`), Aufbauten auf Flachdächern (`props`), Markisen, Ladenschilder, Leuchtschilder, Schornsteine, Landeplätze. `CityBlockout._decorate()` verteilt sie per Seed, je Teil ein MultiMesh (`kit.gdshader`, Farbe als Instanz-Zusatzdaten). Stadion mit Flutlichtmasten, Wolkig-Turm mit Glasfassade, Antenne und Landeplatz. Wohnviertel behält seine Hausmodelle.
- **Aussehen:** `CityLook` (`scripts/world/city_look.gd`) stellt Himmel, Sonne, Dunst, Leuchten und Farben für Hauptszene und Vorschau ein. Shader liegen in `assets/shaders/`: `sky_clouds` (Himmel mit stehenden Wolken), `blockout` (ein Material für die ganze Stadt: Fensterraster, Sockel und Dach auf Gebäuden, Mittellinien und Gehwege auf Straßen; die Art der Fläche steckt im Alpha-Wert der Vertex-Farbe, siehe Kommentar im Shader), `sea` (Wellen). Gebäudefarben je Viertel: `blockout.palette` in `world.json`.
- **Hauptszene:** `world.gd` baut die Stadt als `CityWorld` und verschiebt sie so, dass der Wolkig-Hinterhof (`backyard` in `world.json`, 130 × 130 m frei) bei (0, 0, 0) liegt. Die bisherige Zone (Haufen, Schrank, Lieferungen in `floor_size_m`) behält dadurch ihre Koordinaten; Spielstände bleiben gültig. Absturz-Schutz wie in der Vorschau.
- **Kabel in der Stadt:** `CableUnit` (Viertel mit `cables` und Sperren aus `barriers` in `world.json`) hat feste Kabel-ID-Bereiche ab 1.000.000 (je 100.000), der Hinterhof bleibt die immer geladene Zone (IDs ab 0). `world.gd` lädt Einheiten näher als `streaming.load_m` über eine Warteschlange (`cables_per_frame`) und entlädt sie ab `unload_m`, außer ein Kabel hängt an Rolle oder Arm; veränderte Zustände entladener Kabel liegen in `_stored_states` und im Spielstand. Wohnviertel: Haufen auf Kreuzungen, Straßenkabel (`HeapData.Kind.STREET`). Campus hat einen Zaun (`wall`) mit Lücke zum Wohnviertel; dort liegt die Sperre, deren Blockade fällt, wenn `clear_fraction` abgetragen ist. Testoptionen: `--clearbarrier`, `--streamtest`; `--dumpafter` beendet Godot nicht, dafür `--quit-after <frames>` vor dem `--` angeben.
- **Plan der 2000 wichtigen Kabel:** `important_plan` und `important_cables` je Viertel in `world.json`. `RackPlan` (`scripts/rack/rack_plan.gd`) leitet daraus alles ab: Ports 0–1999 über zehn Schränke, die ersten 20 (Campus) sind Einzel-Dienste, der Rest Reihen à 10 Ports (eine volle Reihe = ein Dienst; zusammen 218 Dienste). Wichtige Kabel liegen bisher im Hinterhof (20 Einzel-Dienste), in der Sperre (`important_section: campus`, 30 Kabel = 3 Reihen) und im Wohnviertel (100 Kabel = 10 Reihen); `CableUnit` verteilt die Ports per Seed auf die Kabel. Die übrigen Viertel haben Schränke, aber noch keine Kabel.
- **Altstadt:** Zaun mit Lücke zum Wohnviertel, davor auf der Hauptstraße der zweite Kabelberg (`sperre_altstadt`, `offset_m` positiv = Berg außerhalb, Blockade dahinter in der Altstadt). Kabel auf Kreuzungen und Straßen, dazu ein großer Haufen auf dem Marktplatz (`extra_heaps`); 150 wichtige Kabel für 15 Reihen. Einheiten haben feste Nummern (`unit` in `world.json`), damit Kabel-IDs alter Spielstände gleich bleiben.
- **Seilbahn zur Basis** (`ziplines` in `world.json`, `scripts/world/zipline.gd`): Strecken aus Punkten [x, z, Höhe über Boden] vom äußeren Ende zur Basis, erster und letzter Punkt sind Stationen. Freigeschaltet durch Dienste mit `special` `zipline_wohnviertel` (Wohnviertel-Reihe „Seilbahn-Leitstand“) bzw. `zipline_altstadt` (Altstadt-Reihe „Stadtwerke-Portal“). E an einer Station fährt; von der Altstadt geht es über `continues` ohne Halt weiter bis zur Basis. Werte in `balancing.json` → `zipline`.
- **Wegweiser:** Sind Knäuel in der Tasche und der Serverraum mehr als 30 m entfernt, zeigt oben ein Pfeil Richtung und Entfernung (`scripts/ui/waypoint.gd`).
- **Nächste Schritte laut Bauplan:** Kabel für die übrigen Viertel, Leitern/Aufzüge, Klettern.

### Werkzeug-Kette und Eingabe

Der Fortschritt soll sich spürbar beschleunigen, das ist der Reiz:

1. **Per Hand (Start):** Die Figur wickelt das Kabel zwischen Hand und Ellbogen um den Arm. Eine Taste muss **wiederholt gedrückt** werden; das ist absichtlich mühsam. Solange ein Kabel am Arm hängt, hält eine Leine (6 m) die Figur beim Haufen.
2. **Handkurbel (erstes Upgrade):** aufstellbare Rolle mit Kurbel, deutlich mehr Meter pro Tastendruck.
3. **Motorrolle:** zieht automatisch; mehrere kaufbar.
4. **Kabeltrommel-Wagen** (250 €, einmalig): rollt dem Spieler hinterher, parkt beim Einhängen und zieht drei Kabel gleichzeitig wie Motorrollen (Stärkere Motoren wirkt mit). Sind alle Plätze fertig, koppelt er sich wieder an, sobald der Spieler in der Nähe ist; E am Wagen parkt bzw. koppelt (mit eingehängten Kabeln nach Bestätigung, die Kabel gehen dann los). `WagonData`/`WagonView`, Plätze sind `ReelData` mit `Kind.WAGON`, Werte in `balancing.json` → `wagon`.

**Umstellen:** Leere Handkurbeln und Motorrollen hebt man mit E auf und stellt sie mit E oder Q woanders ab (auch in der Stadt). Getragen blockiert die Rolle den Arm.

Upgrade **„Dauerzug“**: Taste gedrückt halten statt wiederholt drücken.

**Steuerung (Eingabe-Aktionen in project.godot):** WASD laufen, Shift rennen, Leertaste springen, Maus umsehen, Esc Maus freigeben.
E: Kabelende greifen (beide Enden eines Kabels sind greifbar; am hinteren Ende gegriffen, dreht `CableData.reverse()` die Bahn um), Kabel vom Arm an anvisierte Rolle hängen, Knoten lösen (3 Drücke), Knäuel aufheben bzw. im Serverraum alle Knäuel aus der Tasche einstecken.
Linksklick: wickeln bzw. kurbeln (die Leertaste springt immer). Q: Kabel loslassen (Fortschritt geht verloren) bzw. ein Knäuel aus der Tasche ablegen.
Tab: Tablet (Spiel läuft weiter). N: „Nein“ zu C.O.R.D.s Bestellfrage. F5 speichern, F9 laden.

**Springen:** Sprunghöhe, Schwerkraft-Faktor, Beschleunigung am Boden und in der Luft, Sprung-Puffer und Coyote-Zeit stehen in `balancing.json` → `player`.

**Wichtige Kabel:** leuchten und tragen ein Etikett (Port bzw. Schrank und Reihe + Dienst). Man rollt sie normal auf; sie bringen den halben Meterpreis und werden zu einem Knäuel. Knäuel wandern in die **Tasche** (Start 3 Plätze, Upgrade „Größere Tasche“ +2 je Stufe, dazu Dienst-Boni) und hängen sichtbar am Rücken; ist die Tasche voll oder wird ein Kabel an einer Rolle fertig, liegt das Knäuel am Boden. Im **Serverraum** (Halle im Hinterhof, `balancing.json` → `server_room`) steckt E vor einem beliebigen Schrank alle Knäuel auf einmal ein. Jeder Port ist ein Lämpchen (rot leer, grün belegt, hell = Dienst läuft).

**Dienste** (`data/services.json`): `unlocks` schaltet ein Upgrade frei (Port 1 Festerer Griff, Port 2 Dauerzug, Port 3 Stärkere Motoren, Port 5 Kupferhändler, erste Campus-Reihe Größere Tasche), `bonus` wirkt dauerhaft (Geld, Handzug, Motoren, Lauftempo, Tasche, Knoten, C.O.R.D.s Takt und Bestellmenge), `payout` zahlt einmalig Geld, `special` ist eine Sonderfunktion. Port 20 „C.O.R.D.-Abschaltknopf“: Knopf im Tablet, C.O.R.D. schweigt 5 Minuten, danach 10 Minuten Wartezeit. Dienste ohne Eintrag heißen „<Viertel>, Reihe n“ und haben keine Wirkung. Die Summe der Boni berechnet `RackPlan.bonuses()`, `world.gd` → `_apply_upgrades()` verteilt sie.

**C.O.R.D.:** erste Bestellfrage nach 30 s, danach alle 45–90 s; 6 s Zeit für N, sonst fallen 100 Kabel als neuer Haufen in Blickrichtung neben den Spieler.

**Speichern:** `user://savegame.json` (macOS: `~/Library/Application Support/Godot/app_userdata/Knot My Problem/`), automatisch alle 30 s und beim Schließen. Gespeichert werden nur Seeds und veränderlicher Zustand; Kabelformen entstehen beim Laden neu. Datei hat eine Versionsnummer; kaputte oder fremde Versionen werden ignoriert. „Neues Spiel“ im Tablet löscht den Stand.

### Startwerte für das Balancing

Maßgeblich ist `data/balancing.json` (alle Werte dort, nicht im Code).

| Wert | Start | Upgrade |
| --- | --- | --- |
| Kabellänge (Spiel-Länge) | 15–30 m | – |
| Geld pro Meter | 0,50 € (wichtige Kabel: halber Preis) | Kupferhändler ×1,35, Kosten 60 € × 2,3^Stufe |
| Handzug per Hand (Arm) | 0,25 m pro Tastendruck | Festerer Griff ×1,414, Kosten 10 € × 1,9^Stufe, max. 6 (voll: ca. 10 m/s) |
| Handkurbel | 0,75 m pro Tastendruck | Kauf 8 €, einmalig |
| Dauerzug | – | Halten = 4 Züge/s, 30 €, einmalig |
| Motorrolle | 0,25 m/s | Stärkere Motoren ×1,73, Kosten 40 € × 2,2^Stufe, max. 8 (voll: ca. 20 m/s) |
| Kabeltrommel-Wagen | 3 Plätze à 0,25 m/s | 250 €, einmalig; Stärkere Motoren wirkt mit |
| Weitere Motorrolle | – | Kosten 15 € × 1,8^Anzahl, max. 8 |
| Knoten pro Kabel | 0–2, bei 20–85 % der Länge | – |
| Tasche für Knäuel | 3 Plätze | Größere Tasche +2, Kosten 40 € × 2^Stufe, max. 6 |
| Sprunghöhe | 1,25 m (Schwerkraft ×1,8) | – |

### Architektur

- **Daten getrennt von Darstellung:** Spielzustand als reine Daten (`*_data.gd`, `GameState`, `CoilItem`); Logik in Nodes ohne Grafik (`CableSystem`, `Economy`, `ServiceRack`, `CordLogic`); Darstellung in `*_view.gd`. `scripts/core/world.gd` verdrahtet alles.
- **Deterministisch:** Zufall nur über Seeds; Zone, Haufen, wichtige Kabel und C.O.R.D.-Timing sind reproduzierbar (Grundlage für Speichern und Koop).
- **Signale statt direkter Abhängigkeiten**, z. B. `cable_completed`, `knot_hit`, `service_activated`, `order_requested`.

```
/data        balancing.json (Werte), zone.json (Anordnung), services.json (Dienste je Port)
/scenes      world.tscn (Hauptszene), player.tscn, reel_test.tscn (Rollen-Testszene)
/scripts     cable/   Bahn, Tube-Mesh, Kabeldaten, Haufen, Zone, CableSystem
             reel/    Aufwickler-Daten (Arm, Kurbel, Motor) und Rollen-Darstellung
             rack/    Serverraum (Port-Plan, Logik, Darstellung), Knäuel
             economy/ Geld und Upgrades
             cord/    C.O.R.D.-Logik und -Figur
             save/    Spielstand
             player/  Spielfigur, Anvisieren
             ui/      Fadenkreuz, Tablet, C.O.R.D.-Anzeige, schwebender Text
             core/    Balancing (Autoload), GameState, World
             debug/   Testkameras und -aufbauten
/tests       logic_test.tscn (automatischer Logik-Test), balance_sim.tscn (Verlaufs-Rechnung)
/reference   Browser-Prototyp
/assets      Modelle aus Blender (GLB) und Bodentexturen
```

### Testen

- **Logik-Test:** `godot --headless res://tests/logic_test.tscn` muss „ALLE TESTS OK“ ausgeben.
- **Verlaufs-Rechnung:** `godot --headless res://tests/balance_sim.tscn` spielt Hinterhof, Sperre und Wohnviertel mit einem Modell-Spieler durch (Annahmen oben im Skript) und gibt aus, wann welcher Kauf und welcher Dienst kommt. Ersetzt keinen echten Spieltest.
- **Testoptionen** für die Hauptszene (nach `--`): `--nosave` (ohne Spielstand starten/speichern), `--savefile=<pfad>`, `--dump` / `--dumpafter=<frames>` (Zustand ausgeben), `--grab`, `--pull=<m>`, `--buy=<ids>`, `--hang`, `--order`, `--ask`, `--room` / `--room=in` (vor bzw. in den Serverraum), `--plugports=<von>-<bis>`, `--fillbag=<n>`, `--deliver`, `--jump`, `--snooze`, `--wagon` / `--wagon=fill`, `--carryreel`, `--zipline=<Strecken-ID>` / `--zipline=<ID>,ride`, `--closeup` (Kamera nah an der Figur), `--rigdump` (Knochen der Figur ausgeben) usw.; vollständige Liste in `world.gd` → `_apply_test_args`. Für Testläufe immer `--nosave` verwenden, sonst wird der echte Spielstand geladen.
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

## Verlauf danach

- ✅ Modelle aus Blender (C.O.R.D., Figur, Stecker), Stadt mit Gelände, Boden, Blockout, Kabel in Sperre und Wohnviertel
- ✅ Optik: Himmel, Licht, Fassaden, Straßenlinien, Meer, Kabelringe
- ✅ Aufrollen verfeinert (Wicklung um den Unterarm, lockeres und straffes Verbindungsstück, Trommeln mit Speichen)
- ✅ Spielzeug-Look (Toon-Schattierung, Umrisslinien) und Gebäude-Bausatz für alle Viertel
- ✅ Rollen umstellen, Kabeltrommel-Wagen, Wegweiser, Altstadt mit Sperre und 15 Diensten, Seilbahn zur Basis
- ✅ Springen; Serverraum mit 2000 Ports statt Schrank; Tasche für Knäuel; wichtige Kabel in Sperre und Wohnviertel; Wirkung für alle 20 Einzel-Dienste und 13 Reihen; Wohnhäuser und Serverraum aus Blender; Verlaufs-Rechnung
