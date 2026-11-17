# Knot My Problem

Arbeitstitel: **Knot My Problem** (Alternative: *Wire We Here?*). Interner Name: Kabelsalat.
Ziel ist ein 3D-Incremental-Game mit offener Welt für Steam, später mit Koop für 2–4 Spieler.
Das vollständige Game Design Document liegt hier: https://claude.ai/artifact/1AGe969RxsVRD93hecZe8e
Repository: https://github.com/Julszify/Wire-We-Here (öffentlich, Branch `main`)

## Worum es geht

Drei Chefs der fiktiven „Wolkig AG“ ersetzen am Stammtisch die IT-Abteilung durch eine schnell zusammengebastelte KI namens **C.O.R.D.** (Cable Ordering & Repair Daemon). C.O.R.D. bestellt bei jedem defekten Kabel Ersatz, tauscht aber nie etwas aus. Die Kabelberge wachsen, bis die Cloud weltweit ausfällt. Der Spieler ist der gefeuerte IT-Admin, der das Chaos beseitigen soll.

Kernschleife: Kabelende finden → per Hand, Handkurbel oder Motorrolle aufwickeln → Knoten lösen → Geld. Gewöhnliche Kabel bringen Geld, wichtige Kabel gehören an feste Ports im Serverraum und reaktivieren Dienste (2000 Ports, 218 Dienste).

## Aktueller Stand

Der Vertical Slice (`v0.1-vertical-slice`, Frage: **Macht Ziehen und Aufrollen Spaß?**) ist längst zu einer begehbaren Stadt gewachsen. Spielbar ist:

- **Hinterhof** der Wolkig AG als Tutorial-Zone mit ca. 525 Kabeln (`data/zone.json`), Serverraum und Ausstattung
- **Stadt** (ca. 2 × 2 km, zehn Viertel) mit Gelände, Gebäuden im Spielzeug-Look und rund **195.000 Kabeln** (etwa 100 gewöhnliche je wichtigem); jedes Viertel hat einen Zaun und davor einen Kabelberg als Sperre
- **Werkzeug-Kette:** per Hand um den Arm → Handkurbel → Motorrollen → Kabeltrommel-Wagen → Kabelsauger → Haufen-Winden → Abräum-Drohnen; Rollen und Winden lassen sich umstellen
- **Knoten**, **Geld** pro Meter, **Tablet** (Tab) im Spielzeug-Look mit vier Reitern: Werkzeuge (29 Upgrades), Serverraum (Ausbau), Kosmetik, Auftrag
- **Geld-Senken fürs späte Spiel:** Serverraum-Ausbau (fünf Linien, sichtbar im Raum, mit Boni), Kosmetik (Farben für Figur, C.O.R.D., Drohnen, Wagen; Effekte), **Neuer Auftrag** (Prestige nach dem Finale: alles zurück, Ruf als dauerhafter Bonus)
- **Serverraum** mit zehn Schränken und 2000 Ports; wichtige Kabel werden zu Knäueln, die man in der Tasche sammelt und einsteckt; alle 218 Dienste haben eine Wirkung
- **Spielfigur** (Tripo3D, Bewegungen per Code) und **C.O.R.D.** mit Bestellfalle (ohne „Nein“ fallen 100 Kabel vom Himmel)
- **Bewegung:** laufen, rennen, springen, Seilbahn zur Basis, Wegweiser zum Serverraum
- **Speichern und Laden** als JSON

- **Wichtige Kabel finden:** Fortschritt je Viertel (HUD und Tablet), Kabel-Detektor (warm/kalt, mit Peilantenne Richtung), Drohnen holen wichtige Kabel zuerst
- **Finale im Wolkig-Turm:** Aufzug (fährt, wenn alle anderen Schränke voll sind) zu Etage 40 und aufs Dach; dort die 150 Turm-Kabel und C.O.R.D.s Kern; sind alle 2000 Ports belegt, schaltet E ihn ab (Abspann, C.O.R.D. schläft, danach freies Spiel)

- **Intro** beim neuen Spiel (`scripts/story/intro_scene.gd`): Stammtisch im „Goldenen Router“ (die drei Chefs bauen C.O.R.D. per Bierdeckel-Prompt), „Drei Monate später“ über den Kabelbergen am Turm, Anruf beim Admin („Knot my problem.“); überspringbar

- **Startmenü** (`scenes/main_menu.tscn`, Hauptszene des Projekts): Weiterspielen, Neues Spiel, Mehrspieler, Einstellungen, Beenden; Hintergrund mit Kabelhaufen und C.O.R.D.
- **Mehrspieler (Koop, 2–4)** über IP und Port (ENet): Host rechnet alles, Clients schicken Absichten; gemeinsame Kasse, Ports, Werkzeuge, Finale und neuer Auftrag

Noch nicht enthalten: Steam-Anbindung (Lobbys, Einladungen), weitere Story-Szenen (Chefs in der Stadt, Party und Pointe im Finale), Sound.

## Nächste Schritte (Ideen, noch nicht entschieden)

1. **Spieltest der neuen Werkzeuge und des Finales:** Laut Verlaufs-Rechnung dauert das ganze Spiel ca. 5–5,5 Stunden, ab etwa 3 Stunden ist alles gekauft. Die Sperren sind dann in unter einer Minute weg; die Zeit bestimmt das Finden wichtiger Kabel.
2. **Geld-Senken prüfen:** Ausbau und Kosmetik binden zusammen ca. 100 Mio. €; im ersten Auftrag bleiben am Ende trotzdem ca. 260 Mio. € übrig. Der eigentliche Kreislauf ist der neue Auftrag (zweiter Durchgang mit 18 Ruf laut Verlaufs-Rechnung ca. 4 Stunden).
3. **Story ausbauen:** C.O.R.D.-Durchsagen als Running Gag, Chefs in der Stadt, Finale mit Party und Pointe, Aufzugfahrt sichtbar machen.
4. **Klettern, Leitern:** Höhe in der Stadt nutzen.
5. **Optik und Ton:** Flimmern dichter Haufen in 50–100 m, eigene runde Schrift statt Systemschrift, Sound.
6. **Mehrspieler testen und ausbauen:** echter Test mit mehreren Rechnern und über das Internet (Portfreigabe), Steam-Lobbys über GodotSteam (die Spiellogik bleibt), Seilbahn und Aufzug bei Clients im echten Spiel prüfen.

## Technik

### Engine

**Godot 4.7 mit GDScript** (bestätigt). Szenen und Ressourcen sind Textdateien; das erleichtert die Arbeit mit Claude Code.
Starten: Projekt in Godot öffnen, F5 (startet das Startmenü). Direkt in die Welt: `godot res://scenes/world.tscn`. Kommandozeile: `/Applications/Godot.app/Contents/MacOS/Godot`.

### Kabel-Simulation (wichtigste Regel)

**Keine echte Seilphysik.** Jedes Kabel ist eine feste Kurve aus Punkten (zentripetale Catmull-Rom, gleichmäßig nach Bogenlänge abgetastet). Beim Ziehen gleitet das Kabel entlang dieser Bahn:

- Fortschritt `p = gezogene_meter / kabel_laenge` (0 bis 1)
- Der Teil im Haufen ist die Bahn von Index 0 (eingehängtes Ende) bis `(1 - p) * N`; das hintere Ende wandert also durch den Haufen nach vorne
- Vom eingehängten Ende führt ein Verbindungsstück zum Aufwickler: locker liegt es leicht geschlängelt am Boden und hebt sich erst auf dem letzten Stück; beim Ziehen strafft es sich zur geraden Linie, am Knoten bleibt es gespannt und zittert (Spannung nur in der Darstellung, `CableView.update_tension`, Werte in `balancing.json` → `connector`)
- Auf der Rolle liegt eine Spirale (Helix) Lage für Lage, Kabel an Kabel, und das Kabel läuft tangential ein; am Arm läuft die Wicklung wie auf einer Spule um den Unterarm (Ellbogen bis Hand und zurück, Lage für Lage dicker). Sichtbare Länge `p * min(bahnlaenge, 18 m)`, am Arm höchstens 6,5 m
- Die drei Teile werden zu einem Pfad verbunden und als Tube-Mesh gerendert; nur aktive Kabel werden pro Frame neu erzeugt
- **Ruhende Kabel blockweise:** Kabel im Haufen zeichnet `CableBatch` (bis 256 Kabel je Mesh, `scripts/cable/cable_batch.gd`): die CPU legt nur Mittellinien ab, die Röhre formt `assets/shaders/cable_batch.gdshader`; drei Detailstufen (nah mit vereinfachten Steckern aus `plugs_lod.glb`, mittel, fern; Werte in `balancing.json` → `cable_batch`). Nahe Kabel werfen ihren Schatten über die mittlere Stufe. Gegriffene oder fertige Kabel blendet eine kleine Textur aus (ein Pixel je Kabel); ein eigenes `CableView` bekommen nur gegriffene, wichtige und gelieferte Kabel. `CableBatcher` erzeugt Kabel und Meshes im WorkerThreadPool und baut nahe/mittlere Stufe nach Kamera-Entfernung nach. Kabelenden liegen in einem Raster (`CableSystem.cables_near`), damit Anvisieren bei 20.000+ Kabeln je Viertel schnell bleibt.

Gründe: günstig für tausende Kabel, stabil, und der Zustand eines Kabels besteht nur aus wenigen Werten (Kabel-ID, Rolle, gezogene Meter, Knoten-Status). Das ist später leicht übers Netzwerk zu synchronisieren.
Die Spiel-Länge eines Kabels (15–30 m, bestimmt Geld und Knoten) ist von der sichtbaren Bahn im Haufen entkoppelt.

Der ursprüngliche Browser-Prototyp liegt unter `reference/kabelsalat-3d.html` (three.js).

### Modelle aus Blender

Blender 5.3 liegt unter `/Applications/Blender.app/Contents/MacOS/Blender`. Modelle entstehen per Python-Skript in `tools/blender/` (reproduzierbar, Aufruf steht jeweils oben im Skript); `tools/` ist per `.gdignore` vom Godot-Import ausgenommen.

- **C.O.R.D.:** `assets/models/cord/tripo/cord_tripo.glb` (Tripo3D, eine Textur). `CordView` verkleinert es auf 0,8 m und legt ein eigenes Leuchtband über das Band in der Textur (`TRIPO_BAND_Y`/`TRIPO_BAND_H`), das cyan leuchtet und bei der Bestellfrage rot blinkt. Es neigt sich in Flugrichtung, zappelt bei der Frage, ist nach einem „Nein“ beleidigt (sinkt, dreht sich weg, Band gedimmt) und dreht sich nach einer Bestellung vor Freude (`CordView.react()`). Fehlt die Datei, kommt der Blender-Entwurf:
- `cord_designs.py` → `assets/models/cord/` (C.O.R.D. = Server-Box; Leuchtteile heißen `CordRing` und blinken per Code)
- **Spielfigur:** `assets/models/player/tripo/admin_tripo.glb` (in Tripo3D erzeugt, Mixamo-Skelett, ca. 1 m hoch, schaut nach +Z). `player.gd` lädt es unter den Körper (180° gedreht, ×1,75); `PlayerAnimator` (`scripts/player/player_animator.gd`) stellt die Knochen per Code: Gehen und Rennen mit Knien, Hüfte, Oberkörper und Kopf (rückwärts laufen die Beine andersherum), Atmen und Umschauen im Stand, Kopf folgt der Kamera, Wickeln (rechte Hand kreist um den linken Unterarm), Ziehen gegen die Leine, Knoten-Ruck, Kurbeln (Hand folgt dem Griff, `ReelView.handle_point()`), Rolle tragen, Aufheben, Einstecken, Baumeln an der Seilbahn. Kurze Bewegungen löst `world.gd` über `Player.act()` aus. Achtung: Bei diesem Rig hängt der Oberarm fast ganz am Schulter-Knochen, deshalb werden Schulter und Arm gemeinsam ausgerichtet, und die Arme werden nur mäßig abgesenkt (steiler verschwinden sie im Bauch). `arm_transform()` liefert die Lage des linken Unterarm-Knochens für die Kabel-Wicklung. Fehlt die Datei, nimmt `player.gd` die Einzelteile aus `player_designs.py` (`MODEL_PARTS`). Animationsdateien gibt es keine; wegen des Mixamo-Skeletts ließen sich Mixamo-Animationen später verwenden.
- `player_designs.py` → `assets/models/player/` (Hoodie-Admin aus Einzelteilen, Rückfall-Figur); `player_toy_designs.py` → Entwürfe im Spielzeug-Stil (`assets/models/player/proposals/toy_*`)
- `plug_lod.py` → `assets/models/cable/plugs_lod.glb` (dieselben Stecker mit ca. 48 Dreiecken für die Blöcke ruhender Kabel)
- `plug_designs.py` → `assets/models/cable/plugs.glb` (fünf Steckertypen mit Vertex-Farben; `PlugMeshes` schreibt sie als zweite Fläche ins Kabel-Mesh, Typ und Kabeldicke über `cable.plugs` in `balancing.json`)
- **Ausstattung aus Tripo3D:** Bäume (4× rund, 2× Nadel, Herbst), Büsche, Blumenkübel, Felsen und zwei Laternen in `assets/models/props/tripo/`. Übernommen mit `tools/blender/import_tripo_props.py` (Polygonzahl auf 2.000–5.000 reduziert, UV-Grenzen erhalten, Normal Map entfernt, Texturen auf 1024 px). `YardProps.TRIPO` ordnet sie den Teilnamen zu (Höhe, Drehung, Leuchtkugel bei Laternen); ein MultiMesh je Variante, Variante per Standort. Fehlt eine Datei, gilt das Blender-Teil. Die Altstadt-Laterne (`LampOld`) steht in den Vororten Kirchberg und Westend.
- `prop_designs.py` → `assets/models/props/yard_props.glb` (Ausstattung des Hinterhofs: Bäume, Büsche, Pflanzkübel, Bank, Laterne, Paletten, Müllcontainer, Kabeltrommel, Lieferwagen, Zaunfeld). `YardProps` stellt sie laut `zone.json` → `props` auf (feste Stücke in `items`, Bäume und Büsche am Hofrand per Seed in `ring`), ein MultiMesh je Modell, Kollision als Kisten; Lieferungen landen nicht darauf.
- `building_kit.py` → `assets/models/buildings/kit.glb` (Gebäude-Bausatz: Dächer als Einheitsmodelle – Sattel-, Walm-, Mansard-, Flach- und Sheddach –, Markise, Ladenschild, dazu Aufbauten in echter Größe: Klimagerät, Wassertank, Antenne, Schüssel, Schornstein, Solarmodule, Lüfter, Oberlicht, Hubschrauberlandeplatz, Leuchtschild, Werbetafel, Flutlichtmast). Vertex-Alpha: 1,0 = wird je Gebäude eingefärbt, 0,8 = feste Farbe, 0,5 = leuchtet.
- `building_designs.py` → `assets/models/buildings/` (`houses.glb`: vier Wohnhäuser als Einheitsmodelle 1 × 1 × 1 m, Vorderseite +Z, Godot skaliert sie aufs Grundstück; `server_room.glb`: Hülle des Serverraums mit den Maßen aus `balancing.json` → `server_room`; Farben als Vertex-Farben)

Kabel und Haufen bleiben prozedural (siehe oben); Blender liefert nur feste Teile. Nach neuen `class_name`-Skripten einmal `godot --headless --import` ausführen, sonst kennt die Kommandozeile die Klasse nicht.

### Begehbare Welt (im Aufbau)

Konzept im GDD, Abschnitt „Welt und offene Map“: offene Kleinstadt, ca. 2 × 2 km, Basis im Wolkig-Hinterhof, zehn Viertel, viel Höhe.

- **Gelände:** Addon Terrain3D 1.1.0 (`addons/terrain_3d`, MIT, läuft mit Godot 4.7). `CityTerrain` erzeugt es aus `WorldLayout.height()`; die Höhenkarte wird in `user://city_height_<hash>.res` zwischengespeichert (erstes Mal ca. 7 s, danach unter 0,1 s). Ändert sich `height()`, `HEIGHT_VERSION` in `city_terrain.gd` erhöhen.
- **Layout als Daten:** `data/world.json` (Viertel als Rechtecke mit Bodenhöhe und Rampenbreite, Hügel, Küste, Krater, Hafenbecken, Landmarken, Startpunkt); `scripts/world/world_layout.gd` liest es.
- **Vorschau:** `scenes/city_preview.tscn` (F6), Optionen `--viertel=<id>`, `--at=<x>,<z>`, `--orbit=<grad>`, `--overview` (Luftbild), `--cam=<x>,<z>,<Höhe>,<Ziel-x>,<Ziel-z>` (freie Kamera), `--tour` (FPS je Viertel). Enthält einen Absturz-Schutz (unter das Gelände gerutscht → wieder hochsetzen).
- **Boden:** sieben kachelbare Bodentexturen (Gras, Pflaster, Platten, Beton, Sand, Kies, Fels) in `assets/textures/terrain/`. Quelle sind Midjourney-Bilder in `tools/textures/midjourney/ground_<name>.png`; `scripts/debug/import_ground_images.gd` macht daraus Farbe mit Höhe und Normalen (`godot --headless -s res://scripts/debug/import_ground_images.gd`). Maßstab (`uv_scale`) und Tönung (`tint`) je Boden in `world.json` → `ground.textures`. Rückfall ohne Bilder: `scripts/debug/make_terrain_textures.gd` (prozedural). Welcher Boden wo liegt, bestimmt `WorldLayout.ground_at()` (Viertel laut `ground` in `world.json`, Rampen weich zu Gras, Krater Kies, Küste Sand, an steilen Hängen Fels); `CityTerrain.build_maps()` schreibt daraus die Terrain3D-Steuerkarte (zwischengespeichert zusammen mit der Höhenkarte, `MAPS_VERSION`).
- **Blockout:** `CityBlockout` erzeugt beim Start Straßenraster, Hauptstraßen und ca. 800 graue Gebäude mit Kollision aus den `blockout`-Regeln je Viertel in `world.json` (Godot statt Blender, weil nur Godot die Geländehöhen kennt). Viertel mit `"models": "houses"` (bisher das Wohnviertel) bekommen statt der Kisten Hausmodelle aus Blender: ein MultiMesh je Modell, Haustür zur Straße, Kollision bleibt die Kiste.
- **Spielzeug-Look:** `ToonLook` (`scripts/world/toon_look.gd`) stellt alle StandardMaterial3D auf Toon-Schattierung um (auch später hinzugefügte Nodes) und hängt die Umrisslinien (`assets/shaders/outline.gdshader`, Nachbearbeitung vor der Kamera: Kanten aus Tiefe und Normalen, blendet ab ca. 40–140 m aus) an die Kamera. Eigene Shader setzen `render_mode diffuse_toon, specular_toon`.
- **Gebäude-Bausatz:** Jedes Viertel mit `blockout.kit` in `world.json` bekommt einen Fassadenstil im Blockout-Shader (Büro, Altstadt mit Fensterläden und Schaufenstern, Läden mit Schilderstreifen, Halle mit Rolltoren, Rechenzentrum, Hochhaus) und Teile aus `kit.glb`: Dach je Gebäude (gewichtet aus `roofs`, Farbe aus `roof_palette`), Aufbauten auf Flachdächern (`props`), Markisen, Ladenschilder, Leuchtschilder, Schornsteine, Landeplätze. `CityBlockout._decorate()` verteilt sie per Seed, je Teil ein MultiMesh (`kit.gdshader`, Farbe als Instanz-Zusatzdaten). Stadion mit Flutlichtmasten, Wolkig-Turm mit Glasfassade, Antenne und Landeplatz. Wohnviertel behält seine Hausmodelle.
- **Fassaden- und Dachtexturen:** Midjourney-Bilder in `assets/textures/buildings/` (Originale in `tools/textures/midjourney/`). `CityBlockout.FACADE_TEXTURES` legt je Fassadenstil Bild und Kachelgröße in Metern fest (eine Kachel = Fensterachse × Geschoss, `*_ground` = Erdgeschoss, `rolltor` = Hallentor); der Blockout-Shader färbt helle, kaum bunte Stellen mit der Gebäudefarbe, Glas und Holz bleiben. `ROOF_TEXTURES` gibt Bausatz-Dächern eine Textur (Weltkoordinaten, Reihen parallel zum First, mit Dachfarbe eingefärbt, `kit.gdshader`). Fehlt ein Bild, zeichnet der Shader wie bisher selbst.
- **Aussehen:** `CityLook` (`scripts/world/city_look.gd`) stellt Himmel, Sonne, Dunst, Leuchten und Farben für Hauptszene und Vorschau ein. Shader liegen in `assets/shaders/`: `sky_clouds` (Himmel mit stehenden Wolken), `blockout` (ein Material für die ganze Stadt: Fensterraster, Sockel und Dach auf Gebäuden, Mittellinien und Gehwege auf Straßen; die Art der Fläche steckt im Alpha-Wert der Vertex-Farbe, siehe Kommentar im Shader), `sea` (Wellen). Gebäudefarben je Viertel: `blockout.palette` in `world.json`.
- **Hauptszene:** `world.gd` baut die Stadt als `CityWorld` und verschiebt sie so, dass der Wolkig-Hinterhof (`backyard` in `world.json`, 130 × 130 m frei) bei (0, 0, 0) liegt. Die bisherige Zone (Haufen, Schrank, Lieferungen in `floor_size_m`) behält dadurch ihre Koordinaten; Spielstände bleiben gültig. Absturz-Schutz wie in der Vorschau.
- **Kabel in der Stadt:** `CableUnit` (Viertel mit `cables` und Sperren aus `barriers` in `world.json`) hat feste Kabel-ID-Bereiche ab 1.000.000 (je 100.000), der Hinterhof bleibt die immer geladene Zone (IDs ab 0). `world.gd` lädt Einheiten näher als `streaming.load_m` (Kabel und Meshes entstehen blockweise in Threads über `CableBatcher.load_async`) und entlädt sie ab `unload_m`, außer ein Kabel hängt an Rolle oder Arm; veränderte Zustände entladener Kabel liegen in `_stored_states` und im Spielstand. Straßenkabel sind eigene Mini-Haufen (`HeapData.Kind.STREET`). Viertel haben einen Zaun (`wall`) mit Lücken (`exits`); in der Lücke liegt die Sperre, deren Blockade fällt, wenn `clear_fraction` abgetragen ist. Testoptionen: `--clearbarrier`, `--streamtest`; `--dumpafter` beendet Godot nicht, dafür `--quit-after <frames>` vor dem `--` angeben.
- **Kabelmenge 1:100:** Jedes Viertel hat etwa 100 gewöhnliche Kabel je wichtigem (zusammen ca. 195.000 Kabel; der Hinterhof bleibt Tutorial). `cables` in `world.json`: Haufen auf Kreuzungen (`crossing_heaps`), auf Straßenabschnitten (`segment_heaps`), feste große Berge (`extra_heaps`), Straßenkabel. Stadion, Hafen, Krater und Turm haben nur feste Berge (rund ums Stadion, am Kai, im Kraterring, am Wolkig-Turm auf dem Campus mit `section: turm`). Berge über 9 m Radius: Kabel winden sich in kleineren Bereichen (`heap.local_radius_m`). Jedes Viertel hat einen Zaun mit Lücken und davor einen Kabelberg als Sperre (`clear_fraction` 0,5 bei den neuen). `--unitstats` gibt die Zahlen je Einheit aus.
- **Story:** `IntroScene` spielt beim ersten Start und nach „Neues Spiel“ (mit `--nosave` nur mit `--intro`, `--intro=<Nr>` springt zu einer Einstellung). Die Kneipe ist ein kleines Set unter der Karte (`PUB_ORIGIN`, 300 m tief), eigene Kamera mit Umrisslinien, Untertitel mit Sprechernamen, schwarze Balken; Leertaste, Enter oder Esc überspringen. Die Chefs (`scripts/story/chef_view.gd`, `ChefView`): Tripo-Modelle mit Mixamo-Skelett in `assets/models/chefs/tripo/chef_<grossspurig|jasager|zahlen>.glb` (auf 20.000 Dreiecke reduziert); der `PlayerAnimator` holt die Arme aus der T-Pose, lässt sie atmen, beim Reden gestikulieren und beim Lachen zurücklehnen. Fehlt eine Datei, gibt es Platzhalter aus Grundformen. Kneipen-Ausstattung aus Tripo3D in `assets/models/props/pub/tripo/` (Zapfanlage, Zapfhahn, Bierkrug, Barhocker, Musikbox, Garderobe, Dartscheibe), auf echte Größe skaliert in `IntroScene._prop()`. Der Bierdeckel mit dem Prompt ist ein Midjourney-Bild (`assets/textures/story/bierdeckel.png`, Original in `tools/textures/midjourney/`, unbeleuchtet auf einer Pappscheibe, `IntroScene._coaster()`). Beim Anruf hält der Admin ein Smartphone (`Player.set_phone()`, folgt dem Hand-Knochen, Testoption `--phone`).
- **Wolkig-Turm** (`tower_finale` und `sites` in `world.json`, `scripts/world/tower_finale.gd`): umlaufende Plattform auf Etage 40 (120 m) mit Geländer, unsichtbare Wand am Dachrand, Aufzug mit drei Halten (Häuschen mit Tür: rot gesperrt, grün frei), C.O.R.D.s Kern auf dem Dach. Die Turm-Kabel sind eine eigene Einheit `turm_oben` (Haufen mit `lift_m`, 2.400 Kabel, darunter die 150 wichtigen); die Berge am Fuß des Turms sind nur noch gewöhnliche Kabel. Boden in der Höhe (Knäuel, Rollen) findet `world.gd` → `_ground_spot` per Strahl. Testoptionen `--turmopen`, `--tower=<0|1|2>`, `--finale`.
- **Plan der 2000 wichtigen Kabel:** `important_plan` und `important_cables` je Viertel in `world.json`. `RackPlan` (`scripts/rack/rack_plan.gd`) leitet daraus alles ab: Ports 0–1999 über zehn Schränke, die ersten 20 (Campus) sind Einzel-Dienste, der Rest Reihen à 10 Ports (eine volle Reihe = ein Dienst; zusammen 218 Dienste). Alle 2000 liegen im Spiel: Hinterhof (20 Einzel-Dienste), Sperre vor dem Wohnviertel (`important_section: campus`, 30 Kabel = 3 Reihen), danach je Viertel die Kabel seines Schranks; die Turm-Kabel liegen oben im Turm (Etage 40 und Dach, `sites` → `turm_oben`). `CableUnit` verteilt die Ports per Seed auf die Kabel.
- **Altstadt:** Zaun mit Lücke zum Wohnviertel, davor auf der Hauptstraße der zweite Kabelberg (`sperre_altstadt`, `offset_m` positiv = Berg außerhalb, Blockade dahinter in der Altstadt). Kabel auf Kreuzungen und Straßen, dazu ein großer Haufen auf dem Marktplatz (`extra_heaps`); 150 wichtige Kabel für 15 Reihen. Einheiten haben feste Nummern (`unit` in `world.json`), damit Kabel-IDs alter Spielstände gleich bleiben.
- **Seilbahn zur Basis** (`ziplines` in `world.json`, `scripts/world/zipline.gd`): Strecken aus Punkten [x, z, Höhe über Boden] vom äußeren Ende zur Basis, erster und letzter Punkt sind Stationen. Freigeschaltet durch Dienste mit `special` `zipline_wohnviertel` (Wohnviertel-Reihe „Seilbahn-Leitstand“) bzw. `zipline_altstadt` (Altstadt-Reihe „Stadtwerke-Portal“). E an einer Station fährt; von der Altstadt geht es über `continues` ohne Halt weiter bis zur Basis. Die Bahn fährt an, beschleunigt bis 42 m/s (rennen: 7 m/s) und bremst vor der Endstation. Werte in `balancing.json` → `zipline`.
- **Umland** (`countryside` in `world.json`, `CityBlockout._build_countryside`): Bebauung ohne Kabel zwischen den Vierteln, direkt auf dem Gelände: Häuser (Blender-Modelle, zur Straße gedreht) und Scheunen (Kiste mit Bausatz-Dach) an den Hauptstraßen, verstreute Höfe auf der Wiese und sieben kleine Vororte mit eigenen Straßen und Zufahrt (Sonnenhang, Kirchberg, Lindenau, Nordheide, Westend, Seeblick, Am Ostrand). Abstand zu Vierteln, Sperren, Seilbahnen, Meer und Krater; steile Stellen bleiben frei. Zusammen ca. 300 Gebäude. Dazu die Ausstattung des Hinterhofs (Tripo-Bäume, Büsche, Felsen, Laternen, Blumenkübel, Bänke, Paletten, Kabeltrommeln, Lieferwagen): Bäume und Büsche an den Häusern, Lager an Scheunen, Laternen und Bänke in den Vororten (Kirchberg und Westend mit Altstadt-Laterne), Alleen an Landstraßen, Wäldchen mit Felsen auf der Wiese (Nadelbäume an den Hügeln); ca. 1.800 Stücke über `YardProps.add_items()` in Kacheln, ab 380 m ausgeblendet (`countryside.props`).
- **Oberfläche im Spielzeug-Look** (`scripts/ui/ui_theme.gd`, `UiTheme`): alle Farben, Flächen (runde Ecken, dicker Rand unten, weicher Schatten), Pillen-Knöpfe und Schrift an einer Stelle. Schrift ist eine `SystemFont` mit Liste (Nunito, Varela Round, Arial Rounded MT Bold …); eine eigene Schriftdatei liegt noch nicht im Projekt. Anzeige (`world.gd` → `_style_hud`): Statuskarte oben links, Geld als gelbe Pille, „Tab Tablet“ als Taste, Hinweis unten als dunkle Pille, Meldungen als helle Sprechblase darüber (`_toast`, lange Meldungen brechen bei 900 px um). C.O.R.D.-Frage, Detektor, Wegweiser, schwebender Text und Abspann nutzen dasselbe Theme.
- **Wegweiser:** Sind Knäuel in der Tasche und der Serverraum mehr als 30 m entfernt, zeigt oben ein Pfeil Richtung und Entfernung (`scripts/ui/waypoint.gd`).

### Startmenü und Einstellungen

- **Startmenü** (`scripts/ui/main_menu.gd`, `MainMenu`): eigene kleine Szene (drei Kabelhaufen, Bäume und Ausstattung über `YardProps.add_items`, C.O.R.D. fliegt Achten, Kamera kreist). Weiterspielen erscheint nur mit Spielstand; „Neues Spiel“ fragt bei vorhandenem Stand nach und setzt `SaveGame.force_new` (Intro spielt). Mehrspieler-Feld: Name, „Spiel hosten“ (Port aus den Einstellungen), Adresse und „Beitreten“. Aus der Welt zurück über das Tablet („Hauptmenü“, speichert vorher). Testoptionen im Menü: `--autojoin=<IP>`, `--runfor=<s>`.
- **Einstellungen** (Autoload `Settings`, `scripts/core/settings.gd`, Datei `user://settings.cfg`): Mausempfindlichkeit (Faktor auf `player.mouse_sensitivity`), Maus umkehren, Vollbild, Grafikstufe (Niedrig/Mittel/Hoch: Schatten aus/90 m/160 m in `CityLook.setup_sun`, Bildschärfe 75 %, Sichtweite der Umland-Bäume ×0,6/0,8/1), Lautstärke (Master-Bus, Ton gibt es noch nicht), Spielername, letzte Adresse, Port (24680), eigenes Aussehen als Mitspieler.

### Mehrspieler

Koop für 2–4 Spieler über ENet (IP und Port, UDP). **Der Host rechnet alles**, Clients erzeugen dieselbe Stadt aus denselben Seeds und rechnen nichts selbst.

- **`Net`** (Autoload, `scripts/net/net.gd`): Verbinden, Handschlag und alle Nachrichten. Ablauf: Client verbindet → `hello(Name, Version)` → Host schickt `welcome` (Spielstand aus `_collect_save`, mit zstd gepackt) → Client lädt die Welt mit diesem Stand → `entered` → Host legt die Figur an. Alle Spiel-Nachrichten laufen über das Autoload und werden an die registrierte Welt (`Net.world`) gereicht: `send_intent` (Client → Host, zuverlässig), `send_event` (Host → Clients, zuverlässig), `send_snapshot` (Host → Clients, 10-mal pro Sekunde, gepackt; über 1.200 Byte zuverlässig), `send_player_state` (jede Figur 20-mal pro Sekunde, Host leitet weiter). ENet-Zeitgrenze 45–90 s, weil der Neuaufbau der Stadt einige Sekunden blockiert. Version in `Net.VERSION`.
- **Spieler-Kontext** (`PlayerCtx`, `scripts/net/player_ctx.gd`): Figur, Arm, Tasche, getragene Rolle, Seilbahnfahrt, Sauger-Plätze, Aussehen. `world.gd` hat `_me` (eigene Figur), `_players` (Peer-ID → Kontext) und `_actor`; die alten Namen `_player`, `_arm_reel`, `_bag`, `_carried_reel`, `_ride`, `_cranking_reel` sind Eigenschaften, die auf `_actor` zeigen. Der Host führt Absichten eines Mitspielers mit `_act_as(ctx, …)` aus, dadurch läuft derselbe Code wie im Einzelspieler. `_show_message` geht an den aktuellen `_actor` (Mitspieler bekommen sie übers Netz), `_announce` an alle, `_float` und `_fx` zeigen schwebenden Text bzw. Effekte bei allen.
- **Absichten** (`_request` → offline/Host sofort `_do_intent`, Client `Net.send_intent`): `interact` (alles Anvisierte als IDs, der Host prüft Abstand und Zustand), `pull`, `release`, `buy`, `wear`, `decline`, `snooze`, `recall`. Aufzug und Seilbahn rechnet jeder für die eigene Figur (Host schickt `elevator` bzw. `ride` zurück).
- **Zustand an Clients:** Snapshot mit allen Aufwicklern (Lage, Besitzer, Kabel, Träger), eingehängten Kabeln (Meter, Knoten, umgedreht), Wagen, Drohnen, Geld, C.O.R.D.-Phase; der Client gleicht ab (`net_snapshot`: `CableSystem.force_hook`, Loslassen nach 0,6 s ohne Meldung). Ereignisse: `done` (Kabel fertig, Bezahlung, Ort), `items` (alle Knäuel mit Tasche bzw. Boden), `econ` (ganzer `GameState`), `zone`, `order`, `cord`, `finale`, `looks`, `joined`, `left`, `msg`, `float`, `fx`. Clients: `CableSystem.authority` und `MassTools.authority` aus, C.O.R.D. aus, kein Speichern, kein Intro.
- **Mitspieler-Figuren:** `Player.remote` (keine Eingabe, Kamera, Physik; `net_state` / `apply_net_state` gleiten weich nach), Name darüber. Der Host gibt jedem Mitspieler einen eigenen Arm (IDs ab 950.000) und eigene Sauger-Plätze; Clients übernehmen ihren Arm aus dem Snapshot. Der Wagen folgt dem, der ihn zuletzt angekoppelt bzw. gekauft hat.
- **Gemeinsam:** Kasse, Upgrades, Ports, Ausbau, Kosmetik-Käufe, Finale. Pro Figur: Tasche, Arm, Sauger, Aussehen von Hoodie, Hose, Kopfhörer, Schuhe (Clients speichern es in `Settings.looks`). Nur der Host speichert und kann „Neuer Auftrag“ bzw. „Neues Spiel“; beim neuen Auftrag schickt er allen den neuen Stand, sie laden mit.
- **Geht ein Mitspieler,** lässt der Host dessen Kabel los, legt Knäuel und Rolle ab und meldet es allen. Verliert ein Client den Host, landet er im Hauptmenü mit Hinweis.
- **Testen mit zwei Instanzen:** Host `godot --headless res://scenes/world.tscn -- --nosave --host --runfor=75`, nach ca. 15 s Client `godot --headless res://scenes/main_menu.tscn -- --nosave --autojoin=127.0.0.1 --network --runfor=40` (`--network` greift, zieht und löst Knoten übers Netz und kauft eine Kurbel; `--network=important` rollt ein wichtiges Kabel auf und steckt es ein). Weitere: `--newjobafter=<s>` (Host nimmt einen neuen Auftrag an), `--netlog` (Host gibt Absichten aus), `--shot=<pfad>` (Bild bei `--runfor`-Ende). Achtung: `--headless` rechnet ungebremst, deshalb zeitbasiert mit `--runfor` statt `--quit-after`.

### Werkzeug-Kette und Eingabe

Der Fortschritt soll sich spürbar beschleunigen, das ist der Reiz:

1. **Per Hand (Start):** Die Figur wickelt das Kabel zwischen Hand und Ellbogen um den Arm. Eine Taste muss **wiederholt gedrückt** werden; das ist absichtlich mühsam. Solange ein Kabel am Arm hängt, hält eine Leine (6 m) die Figur beim Haufen.
2. **Handkurbel (erstes Upgrade):** aufstellbare Rolle mit Kurbel, deutlich mehr Meter pro Tastendruck.
3. **Motorrolle:** zieht automatisch; mehrere kaufbar.
4. **Kabeltrommel-Wagen** (250 €, einmalig): rollt dem Spieler hinterher, parkt beim Einhängen und zieht drei Kabel gleichzeitig wie Motorrollen (Stärkere Motoren wirkt mit). Sind alle Plätze fertig, koppelt er sich wieder an, sobald der Spieler in der Nähe ist; E am Wagen parkt bzw. koppelt (mit eingehängten Kabeln nach Bestätigung, die Kabel gehen dann los). `WagonData`/`WagonView`, Plätze sind `ReelData` mit `Kind.WAGON`, Werte in `balancing.json` → `wagon`.

5. **Kabelsauger** (1.500 €, `vacuum`): Handgerät. Linksklick halten bei freiem Arm (und ohne belegte Kurbel in Reichweite) saugt die nächsten Kabelenden vor der Figur ein, mehrere gleichzeitig (Start 3, Upgrade „Breitere Düse“ +2 und mehr Reichweite, „Zyklon-Kammer“ +3, „Saugkraft“ ×1,5; „Sauger-Dauerbetrieb“: Linksklick schaltet ihn an und aus). Kabel laufen weiter, auch wenn man loslässt; wichtige Knäuel kommen in die Tasche. Plätze sind `ReelData` mit `Kind.VACUUM` an der Düse vor der Figur.
6. **Haufen-Winde** (4.000 € × 1,7^Anzahl, max. 6, `winch`): wird aufgestellt und hängt selbst das nächste Kabelende im Umkreis von 10 m ein, auch wenn der Spieler weg ist (ihre Umgebung bleibt geladen). Mit E aufheben und umstellen (ein laufendes Kabel rutscht dann zurück). Upgrade „Windenmotor“ ×1,5.
7. **Abräum-Drohnen** (15.000 € × 1,9^Anzahl, max. 8, `drone`): fliegen in Reisehöhe zu Kabelenden im Umkreis von 45 m um ihren Einsatzort, rollen sie schwebend ab, sammeln liegende Knäuel ein und bringen bis zu drei davon selbst in den Serverraum. Einsatzort = Ort beim ersten Kauf, im Tablet „Drohnen zu mir rufen“. Upgrade „Drohnen-Turbo“ ×1,5 (Ziehen und Fliegen).

Sauger, Winde und Drohne ziehen mit eigenem Tempo (`ReelData.speed_factor` aus ihren Upgrades × Dienst-Bonus Motoren, nicht „Stärkere Motoren“) und lösen Knoten nach `auto_untie_s` selbst (`CableSystem._process`). Logik in `scripts/core/mass_tools.gd` (`MassTools`), Drohne `scripts/reel/drone_view.gd`, Werte in `balancing.json` → `vacuum`, `winch`, `drone`. Sauger- und Drohnen-Plätze werden nicht gespeichert (IDs ab 900.000), Winden schon, der Einsatzort der Drohnen auch.

**Umstellen:** Leere Handkurbeln und Motorrollen hebt man mit E auf und stellt sie mit E oder Q woanders ab (auch in der Stadt). Getragen blockiert die Rolle den Arm.

Upgrade **„Dauerzug“**: Taste gedrückt halten statt wiederholt drücken.

**Steuerung (Eingabe-Aktionen in project.godot):** WASD laufen, Shift rennen, Leertaste springen, Maus umsehen, Esc Maus freigeben.
E: Kabelende greifen (beide Enden eines Kabels sind greifbar; am hinteren Ende gegriffen, dreht `CableData.reverse()` die Bahn um), Kabel vom Arm an anvisierte Rolle hängen, Knoten lösen (3 Drücke), Knäuel aufheben bzw. im Serverraum alle Knäuel aus der Tasche einstecken.
Linksklick: wickeln bzw. kurbeln (die Leertaste springt immer). Q: Kabel loslassen (Fortschritt geht verloren) bzw. ein Knäuel aus der Tasche ablegen.
Tab: Tablet (Spiel läuft weiter). N: „Nein“ zu C.O.R.D.s Bestellfrage. F5 speichern, F9 laden.

**Springen:** Sprunghöhe, Schwerkraft-Faktor, Beschleunigung am Boden und in der Luft, Sprung-Puffer und Coyote-Zeit stehen in `balancing.json` → `player`.

**Wichtige Kabel finden:** Oben links steht der Fortschritt des Viertels, in dem man steht („Gamer-Viertel: 37 von 200 …“), im Tablet alle Viertel. Upgrade **Kabel-Detektor** (300 €): Anzeige unten rechts pulsiert schneller und wird rot, je näher das nächste wichtige Kabel ist (`scripts/ui/detector.gd`, Reichweite `balancing.json` → `detector`); **Peilantenne** (2.500 €) zeigt Richtung und Entfernung. Geladene wichtige Kabel führt `CableSystem.important`.

**Wichtige Kabel:** leuchten und tragen ein Etikett (Port bzw. Schrank und Reihe + Dienst). Man rollt sie normal auf; sie bringen den halben Meterpreis und werden zu einem Knäuel. Knäuel wandern in die **Tasche** (Start 3 Plätze, Upgrade „Größere Tasche“ +2 je Stufe, dazu Dienst-Boni) und hängen sichtbar am Rücken; ist die Tasche voll oder wird ein Kabel an einer Rolle fertig, liegt das Knäuel am Boden. Im **Serverraum** (Halle im Hinterhof, `balancing.json` → `server_room`) steckt E vor einem beliebigen Schrank alle Knäuel auf einmal ein. Jeder Port ist ein Lämpchen (rot leer, grün belegt, hell = Dienst läuft).

**Dienste** (`data/services.json`): Jede der 198 Reihen hat eine Wirkung (neue Viertel: kleine Boni von 3–6 % im Wechsel und einmalige Auszahlungen; Lauftempo gedeckelt über `player.max_speed_factor`). `unlocks` schaltet ein Upgrade frei (Port 1 Festerer Griff, Port 2 Dauerzug, Port 3 Stärkere Motoren, Port 5 Kupferhändler, erste Campus-Reihe Größere Tasche), `bonus` wirkt dauerhaft (Geld, Handzug, Motoren, Lauftempo, Tasche, Knoten, C.O.R.D.s Takt und Bestellmenge), `payout` zahlt einmalig Geld, `special` ist eine Sonderfunktion. Port 20 „C.O.R.D.-Abschaltknopf“: Knopf im Tablet, C.O.R.D. schweigt 5 Minuten, danach 10 Minuten Wartezeit. Die Summe der Boni berechnet `RackPlan.bonuses()`, `world.gd` → `_apply_upgrades()` verteilt sie.

**Serverraum-Ausbau** (`room_order` und `room_*` in `balancing.json` → `upgrades`, Tablet-Reiter „Serverraum“): Neonbeleuchtung (Leisten an Decke und Schränken, Stufe 3 Farbwechsel; +5 % Geld je Stufe), Kühlung (Klimageräte auf dem Dach und an der Vorderwand, Stufe 4 Kaltluft-Gitter; Motoren +6 %), Kabelmanagement (Pritschen über den Schränken, Bündel, Kabel in die Schränke; Tasche +2, wichtige Kabel +20 %), Leitstand (Pult, Monitorwand, großer Lagebildschirm mit Live-Stand; Antwortzeit +1 s), Kaffeeecke (Bank, Pflanzen, Kaffeemaschine, Sofa; Handzug +15 %, Laufen +3 %). Jede Stufe wirkt wie ein Dienst-Bonus (`bonus` je Stufe, `Economy.refresh_bonuses`). Teile baut `ServerRoomView._refresh_extras` neu, wenn sich eine Stufe ändert. Testoption `--roomview` / `--roomview=back`.

**Kosmetik** (`cosmetics` in `balancing.json`, Tablet-Reiter „Kosmetik“): neun Plätze (Hoodie, Hose, Kopfhörer, Schuhe, C.O.R.D.-Leuchtband, C.O.R.D.-Lack, Drohnen-Lack, Wagen-Lack, Effekt), je Platz ein `*_standard` gratis. Gekauft wird einmal (`GameState.cosmetics`), angelegt je Platz (`GameState.looks`); `Economy.wear_cosmetic` kauft und legt an. Die Figur färbt `assets/shaders/outfit.gdshader` um: Teile werden an Farbton, Sättigung und Helligkeit der Tripo-Textur und an der Höhe am Körper erkannt (`Player.set_outfit`, nur wenn etwas angelegt ist). C.O.R.D.: `CordView.set_band` / `set_paint` (Lack multipliziert die Textur). Drohne und Wagen: `paint` als static var plus `set_paint`. Effekte (`CelebrationFx`, `scripts/ui/celebration_fx.gd`): Funken, Konfetti, Sterne, Regenbogen beim Fertigwerden eines Kabels (bis 40 m um die Figur) und beim Einstecken. `world.gd` → `_apply_looks`. Testoption `--look=<ids>` (kauft und legt an).

**Neuer Auftrag** (Prestige, `prestige` in `balancing.json`, Tablet-Reiter „Auftrag“): erst nach dem Finale. Ruf = `points_per_sqrt_million` × √(Verdienst dieses Auftrags in Mio. €). Je Ruf-Punkt +10 % Geld und +5 % Ziehen (Hand, Motoren, Werkzeuge); C.O.R.D. bestellt je Auftrag ×1,15 mehr und fragt öfter (×0,9 Pause). Ruf, Zahl der Aufträge und Kosmetik stehen in `GameState.meta_dict()` und bleiben; alles andere (Geld, Upgrades, Ausbau, Ports, Kabel, Finale) geht zurück. Ablauf: `world.gd` → `_start_new_job` legt die Meta-Daten in `SaveGame.carry_meta`, löscht den Spielstand (nur wenn gespeichert wird) und lädt die Szene neu; dort übernimmt `_ready` sie, zeigt statt des Intros eine Meldung und speichert sofort. „Neues Spiel“ löscht dagegen alles, auch Ruf und Kosmetik. Testoption `--newjob[=<Mio. €>]`. Verlaufs-Rechnung für einen weiteren Auftrag: `-- --ruf=<Punkte> [--auftrag=<Nr>]`.

**C.O.R.D.:** erste Bestellfrage nach 30 s, danach alle 45–90 s; 6 s Zeit für N, sonst fallen 100 Kabel als neuer Haufen in Blickrichtung neben den Spieler.

**Speichern:** `user://savegame.json` (macOS: `~/Library/Application Support/Godot/app_userdata/Knot My Problem/`), automatisch alle 30 s und beim Schließen. Gespeichert werden nur Seeds und veränderlicher Zustand; Kabelformen entstehen beim Laden neu. Datei hat eine Versionsnummer; kaputte oder fremde Versionen werden ignoriert. „Neues Spiel“ im Tablet löscht den Stand.

### Startwerte für das Balancing

Maßgeblich ist `data/balancing.json` (alle Werte dort, nicht im Code).

| Wert | Start | Upgrade |
| --- | --- | --- |
| Kabellänge (Spiel-Länge) | 15–30 m | – |
| Geld pro Meter | 0,50 € (wichtige Kabel: halber Preis) | Kupferhändler ×1,35, Kosten 60 € × 2,3^Stufe, max. 12 |
| Handzug per Hand (Arm) | 0,25 m pro Tastendruck | Festerer Griff ×1,414, Kosten 10 € × 1,9^Stufe, max. 6 (voll: ca. 10 m/s) |
| Handkurbel | 0,75 m pro Tastendruck | Kauf 8 €, einmalig |
| Dauerzug | – | Halten = 4 Züge/s, 30 €, einmalig |
| Motorrolle | 0,25 m/s | Stärkere Motoren ×1,73, Kosten 40 € × 2,2^Stufe, max. 8 (voll: ca. 20 m/s) |
| Kabeltrommel-Wagen | 3 Plätze à 0,25 m/s | 250 €, einmalig; Stärkere Motoren wirkt mit |
| Weitere Motorrolle | – | Kosten 15 € × 1,8^Anzahl, max. 8 |
| Knoten pro Kabel | 0–2, bei 20–85 % der Länge | – |
| Tasche für Knäuel | 3 Plätze | Größere Tasche +2, Kosten 40 € × 2^Stufe, max. 6 |
| Kabelsauger | 3 Kabel à 4 m/s, 3,5 m | 1.500 €; Saugkraft ×1,5 (2.500 € × 2,3^Stufe, max. 8), Breitere Düse +2 Kabel (4.000 € × 2,5^Stufe, max. 6), Zyklon-Kammer +3 Kabel (20.000 € × 2,8^Stufe, max. 4), Dauerbetrieb 6.000 € |
| Haufen-Winde | 6 m/s, 10 m Umkreis | 4.000 € × 2,2^Anzahl, max. 6; Windenmotor ×1,5 (6.000 € × 3^Stufe, max. 6) |
| Abräum-Drohne | 8 m/s, 45 m Umkreis, 3 Knäuel | 15.000 € × 2,4^Anzahl, max. 8; Drohnen-Turbo ×1,5 (25.000 € × 3,5^Stufe, max. 5) |
| Kabel-Detektor | – | 300 €; Peilantenne 2.500 € |
| Sprunghöhe | 1,25 m (Schwerkraft ×1,8) | – |
| Laufen / Rennen | 4 / 7 m/s | Laufschuhe ×1,1, Kosten 120 € × 2,6^Stufe, max. 5; Dienst-Boni bis ×1,6, zusammen höchstens ×2,2 |
| Seilbahn | 42 m/s (Anfahren 12 m/s², Bremsen 14 m/s²) | – |
| Serverraum-Ausbau | – | Neon 250 Tsd. € × 4^Stufe (3), Kühlung 400 Tsd. € × 3,5^Stufe (4), Kabelmanagement 600 Tsd. € × 4^Stufe (3), Leitstand 1 Mio. € × 4^Stufe (3), Kaffeeecke 150 Tsd. € × 4^Stufe (3) |
| Kosmetik | – | 80 Tsd. € bis 10 Mio. € je Stück, zusammen ca. 37 Mio. € |
| Neuer Auftrag | – | Ruf = √(Verdienst in Mio. €); je Punkt +10 % Geld, +5 % Ziehen; C.O.R.D. ×1,15 Bestellmenge je Auftrag |

### Architektur

- **Daten getrennt von Darstellung:** Spielzustand als reine Daten (`*_data.gd`, `GameState`, `CoilItem`); Logik in Nodes ohne Grafik (`CableSystem`, `Economy`, `ServiceRack`, `CordLogic`); Darstellung in `*_view.gd`. `scripts/core/world.gd` verdrahtet alles.
- **Deterministisch:** Zufall nur über Seeds; Zone, Haufen, wichtige Kabel und C.O.R.D.-Timing sind reproduzierbar (Grundlage für Speichern und Koop).
- **Signale statt direkter Abhängigkeiten**, z. B. `cable_completed`, `knot_hit`, `service_activated`, `order_requested`.

```
/data        balancing.json (Werte), zone.json (Anordnung), services.json (Dienste je Port)
/data        world.json (Stadt, Viertel, Kabel, Sperren, Seilbahnen)
/scenes      main_menu.tscn (Startmenü, Hauptszene des Projekts), world.tscn (Spielwelt), city_preview.tscn (Stadt-Vorschau), player.tscn, reel_test.tscn
/scripts     cable/   Bahn, Tube-Mesh, Kabeldaten, Haufen, Zone, CableSystem, Blöcke ruhender Kabel (CableBatch/-Batcher)
             world/   Stadt-Layout, Gelände, Blockout, Kabel-Einheiten, Seilbahn, Hof-Ausstattung, Spielzeug-Look
             reel/    Aufwickler-Daten (Arm, Kurbel, Motor) und Rollen-Darstellung
             rack/    Serverraum (Port-Plan, Logik, Darstellung), Knäuel
             economy/ Geld und Upgrades
             cord/    C.O.R.D.-Logik und -Figur
             save/    Spielstand
             player/  Spielfigur, Animator, Anvisieren
             ui/      Theme (UiTheme), Startmenü, Fadenkreuz, Tablet, C.O.R.D.-Anzeige, Detektor, Wegweiser, schwebender Text, Effekte, Abspann
             net/     Mehrspieler: Net (Autoload), PlayerCtx
             core/    Balancing (Autoload), GameState, World
             debug/   Testkameras und -aufbauten
/tests       logic_test.tscn (automatischer Logik-Test), balance_sim.tscn (Verlaufs-Rechnung)
/reference   Browser-Prototyp
/assets      Modelle (Blender, Tripo3D), Texturen, Shader
/tools       Blender-Skripte, Original-Texturen (von Godot ignoriert)
```

### Testen

- **Logik-Test:** `godot --headless res://tests/logic_test.tscn` muss „ALLE TESTS OK“ ausgeben.
- **Verlaufs-Rechnung:** `godot --headless res://tests/balance_sim.tscn` spielt Hinterhof und erste Sperre Kabel für Kabel durch, danach alle Viertel bis zum Turm als Durchsatz-Modell (Werkzeuge bringen Geld, wichtige Kabel suchen mit bzw. ohne Detektor, Drohnen, Abliefern; Annahmen oben im Skript) und gibt aus, wann welcher Kauf und welcher Dienst kommt. Ersetzt keinen echten Spieltest.
- **Testoptionen** für die Hauptszene (nach `--`): `--nosave` (ohne Spielstand starten/speichern), `--savefile=<pfad>`, `--dump` / `--dumpafter=<frames>` (Zustand ausgeben), `--grab`, `--pull=<m>`, `--buy=<ids>`, `--hang`, `--order`, `--ask`, `--room` / `--room=in` (vor bzw. in den Serverraum), `--plugports=<von>-<bis>`, `--fillbag=<n>`, `--deliver`, `--jump`, `--snooze`, `--wagon` / `--wagon=fill`, `--carryreel`, `--vacuum` (Kabelsauger dauerhaft an, mit `--buy=vacuum`), `--zipline=<Strecken-ID>` / `--zipline=<ID>,ride`, `--closeup` (Kamera nah an der Figur), `--teleport=x,z` (wird zuerst ausgeführt, Kabel dort sofort geladen), `--perf` (alle 2 s Bildrate, Dreiecke, Detailstufen, Rechenzeit), `--unitstats`, `--intro` / `--intro=<Nr>` (Intro zeigen bzw. ab Einstellung Nr.), `--anim=<walk|run|back|strain|crank|tug|reach|pickup|wind|sulk|happy>` (Bewegung vorführen, Kamera mittig), `--rigdump` (Knochen der Figur ausgeben), `--tablet=<0..3>` (Tablet mit Reiter), `--look=<ids>`, `--roomview[=back]`, `--newjob[=<Mio. €>]` usw.; vollständige Liste in `world.gd` → `_apply_test_args`. Für Testläufe immer `--nosave` verwenden, sonst wird der echte Spielstand geladen.
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
- ✅ Figur und C.O.R.D. aus Tripo3D, Bewegungen der Figur per Code (PlayerAnimator), C.O.R.D. reagiert
- ✅ Boden-, Fassaden- und Dachtexturen aus Midjourney
- ✅ Kabel für alle Viertel im Verhältnis 1:100 (ca. 195.000), Blöcke ruhender Kabel mit Detailstufen und Threads, Zäune und Sperren für alle Viertel, Wirkung für alle 198 Reihen
- ✅ Werkzeuge für die Masse: Kabelsauger, Haufen-Winden, Abräum-Drohnen (mit Upgrades, Tablet scrollbar)
- ✅ Intro-Szene: Stammtisch im „Goldenen Router“, drei Monate später, Anruf beim Admin
- ✅ Fortschritt je Viertel, Kabel-Detektor mit Peilantenne, Drohnen holen wichtige Kabel zuerst, Turm-Finale mit Aufzug, Etage 40, Dach, C.O.R.D.s Kern und Abspann; Verlaufs-Rechnung für alle Viertel, späte Preise angehoben
- ✅ Umland (Häuser, Höfe, Vororte, Bäume), Laufschuhe, schnellere Seilbahn, mehr Sauger-Upgrades
- ✅ Geld-Senken: Serverraum-Ausbau, Kosmetik, Neuer Auftrag (Prestige); Anzeige und Tablet im Spielzeug-Look
- ✅ Startmenü mit Einstellungen; Koop für 2–4 Spieler über IP (Host rechnet, Clients schicken Absichten)
