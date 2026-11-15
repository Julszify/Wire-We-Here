extends Node
## Grober Spielverlauf als Rechnung (kein echter Spieltest!): spielt Hinterhof, Sperre und Wohnviertel
## mit einem einfachen Modell-Spieler durch und zeigt, wann was passiert. Hilft beim Einstellen von
## data/balancing.json, ersetzt aber nicht das Gefühl beim Spielen.
##   godot --headless res://tests/balance_sim.tscn
## Annahmen über den Spieler stehen in ASSUME und werden mit ausgegeben.

const ASSUME := {
	"klicks_pro_s": 5.0,          # Hämmern mit der Maus
	"greifen_s": 3.0,             # Kabelende suchen und greifen
	"zur_kurbel_s": 4.0,          # Kabel zur Handkurbel tragen und einhängen
	"zur_rolle_s": 6.0,           # Kabel zu einer Motorrolle tragen und einhängen
	"knoten_s": 2.0,              # Knoten am eigenen Kabel (Reaktion + Drücke)
	"knoten_rolle_s": 6.0,        # Knoten an einer Rolle: hinlaufen, zielen, lösen
	"nein_quote": 0.85,           # Anteil der Bestellfragen, die der Spieler rechtzeitig ablehnt
	"weg_serverraum_hof_m": 30.0, # mittlerer Weg vom Kabel zum Serverraum im Hinterhof (einfach)
	"weg_sperre_m": 95.0,         # Sperre -> Serverraum
	"weg_wohnviertel_m": 400.0,   # Mitte Wohnviertel -> Serverraum
	"weg_altstadt_m": 780.0,      # Mitte Altstadt -> Serverraum
	"weg_zur_station_m": 180.0,   # mittlerer Fußweg zur nächsten Seilbahn-Station im Viertel
	"seil_wohnviertel_m": 250.0,  # Seilbahn Wohnviertel -> Basis (Fahrstrecke)
	"seil_altstadt_m": 650.0,     # Seilbahn Altstadt -> Basis (über das Wohnviertel)
}

## Längste Dauer einer Phase in der Rechnung (danach Abbruch mit Hinweis)
const MAX_PHASE_S := 8.0 * 3600.0

var t := 0.0
var eco: Economy
var rack: ServiceRack
var log: Array[String] = []
var reels_free_at: Array[float] = []   # Motorrollen: Zeit, zu der sie wieder frei sind
var pending: Array = []                # [Zeit, Kabel] von Motorrollen, noch nicht gutgeschrieben
var bag: Array[int] = []
var rng := RandomNumberGenerator.new()
var next_ask := 0.0
var orders := 0
var declined := 0
var _open_important := 0              # wichtige Kabel der laufenden Phase, die noch nicht abgeliefert sind
var tools_here := true                 # Kurbel und Rollen sind in Reichweite (Hof; an der Sperre umgestellt)
var wagon_free_at: Array[float] = []   # Plätze des Kabeltrommel-Wagens (folgt dem Spieler überallhin)
var phase := "hof"


func _ready() -> void:
	rng.seed = 1
	eco = Economy.new()
	add_child(eco)
	rack = ServiceRack.new(eco.state)
	rack.service_activated.connect(_on_service)
	next_ask = float(Balancing.cord["first_ask_s"])
	print("ANNAHMEN ", JSON.stringify(ASSUME))

	# 1. Hinterhof: echte Zone aus zone.json
	var ports: Array[int] = []
	for p in RackPlan.tutorial_count():
		ports.append(p)
	var yard := ZoneData.from_config(int(Balancing.zone.get("seed", 1234))).create_cables(0, ports)
	_shuffle(yard)
	_work(yard, func() -> bool: return rack.active_count() >= RackPlan.tutorial_count(), float(ASSUME["weg_serverraum_hof_m"]), true)
	_mark("Alle 20 Einzel-Dienste online (%d Kabel aufgerollt, %d Lieferungen angenommen, %d abgelehnt)" % [_done(yard), orders, declined])

	# 2. Sperre direkt neben dem Hof: Kurbel und Motorrollen werden hinübergetragen (je Rolle einmal hin und zurück)
	phase = "sperre"
	var carry_s := 2.0 * float(ASSUME["weg_sperre_m"]) / float(Balancing.player["sprint_speed_m_per_s"])
	t += carry_s * (reels_free_at.size() + eco.state.level("crank"))
	_mark("Kurbel und %d Motorrollen zur Sperre getragen" % reels_free_at.size())
	var cfg: Dictionary = Balancing.world["barriers"][0]
	var barrier := _cables(int(cfg["count"]), RackPlan.row_ports("campus"), 500000)
	var need := int(ceil(barrier.size() * float(cfg["clear_fraction"])))
	var t0 := t
	_work(barrier, func() -> bool: return _done(barrier) >= need, float(ASSUME["weg_sperre_m"]), false)
	_mark("Sperre abgetragen (%d von %d Kabeln) nach %s an der Sperre" % [need, barrier.size(), _dur(t - t0)])

	# 3. Wohnviertel: Kurbel und Rollen bleiben an der Sperre, nur der Wagen kommt mit
	tools_here = false
	phase = "wohnviertel"
	var wcfg: Dictionary = {}
	for d: Dictionary in Balancing.world["districts"]:
		if d["id"] == "wohnviertel":
			wcfg = d["cables"]
	var count := int(wcfg["crossing_heaps"]) * (int(wcfg["heap_count"][0]) + int(wcfg["heap_count"][1])) / 2 + int(wcfg["street_cables"])
	var wohn := _cables(count, RackPlan.row_ports("wohnviertel"), 600000)
	t0 = t
	var w0 := rack.active_count()
	_work(wohn, func() -> bool: return rack.active_count() - w0 >= 100, float(ASSUME["weg_wohnviertel_m"]), false)
	_mark("Alle 100 Wohnviertel-Ports belegt (%d von %d Kabeln aufgerollt) nach %s im Viertel" % [_done(wohn), wohn.size(), _dur(t - t0)])

	# 4. Sperre vor der Altstadt und Altstadt
	phase = "altstadt"
	var acfg: Dictionary = Balancing.world["barriers"][1]
	var barrier2 := _cables(int(acfg["count"]), [], 800000)
	var need2 := int(ceil(barrier2.size() * float(acfg["clear_fraction"])))
	t0 = t
	_work(barrier2, func() -> bool: return _done(barrier2) >= need2, float(ASSUME["weg_altstadt_m"]), false)
	_mark("Sperre vor der Altstadt abgetragen (%d Kabel) nach %s" % [need2, _dur(t - t0)])
	var alt_cfg: Dictionary = {}
	for d: Dictionary in Balancing.world["districts"]:
		if d["id"] == "altstadt":
			alt_cfg = d["cables"]
	var acount := int(alt_cfg["crossing_heaps"]) * (int(alt_cfg["heap_count"][0]) + int(alt_cfg["heap_count"][1])) / 2 \
		+ int(alt_cfg["street_cables"])
	for e: Dictionary in alt_cfg.get("extra_heaps", []):
		acount += int(e["count"])
	var alt := _cables(acount, RackPlan.row_ports("altstadt"), 900000)
	t0 = t
	var a0 := rack.active_count()
	_work(alt, func() -> bool: return rack.active_count() - a0 >= 150, float(ASSUME["weg_altstadt_m"]), false)
	_mark("Alle 150 Altstadt-Ports belegt (%d von %d Kabeln aufgerollt) nach %s in der Altstadt" % [_done(alt), alt.size(), _dur(t - t0)])

	print("\nVERLAUF")
	for line in log:
		print(line)
	print("\nENDE  Geld %s · verdient %s · Dienste %d · Upgrades %s" % [Economy.format_money(eco.state.money),
		Economy.format_money(eco.state.total_earned), rack.active_services(), JSON.stringify(eco.state.upgrades)])
	get_tree().quit()


# ---------------------------------------------------------------- Modell

## Arbeitet Kabel ab, bis `stop` wahr ist oder alle fertig sind. `way_m` = Weg zum Serverraum.
## Jedes dritte Kabel ist ein wichtiges, solange es welche gibt (der Spieler sucht die leuchtenden).
func _work(cables: Array[CableData], stop: Callable, way_m: float, cord_active: bool) -> void:
	var t_start := t
	var step := 0
	_open_important = 0
	for x in cables:
		if x.is_important() and x.state != CableData.State.DONE:
			_open_important += 1
	while not stop.call():
		if t - t_start > MAX_PHASE_S:
			_mark("ABBRUCH nach %s" % _dur(MAX_PHASE_S))
			break
		var c: CableData = null
		var fallback: CableData = null
		var want_important := step % 3 == 2
		for x in cables:
			if x.state == CableData.State.DONE:
				continue
			if fallback == null:
				fallback = x
			if x.is_important() == want_important:
				c = x
				break
		if c == null:
			c = fallback
		if c == null:
			break
		step += 1
		c.state = CableData.State.DONE
		# Vernünftiger Spieler: Wagen nur, wenn Wickeln per Hand länger dauern würde als das Einhängen
		var slot := _free_wagon_slot() if _hand_seconds(c) > float(ASSUME["greifen_s"]) + 2.0 else -1
		if slot >= 0:
			# Am Wagen einhängen: steht direkt am Haufen, kurze Wege, drei Plätze
			t += float(ASSUME["greifen_s"]) + 2.0 + c.knots_m.size() * float(ASSUME["knoten_rolle_s"]) * 0.6
			var wrate := float(Balancing.wagon["pull_speed_m_per_s"]) * eco.factor("motor") * eco.bonus("motor")
			wagon_free_at[slot] = t + c.length_m / wrate
			pending.append([wagon_free_at[slot], c])
			_collect(way_m)
			_shop()
			if cord_active:
				_cord(cables)
			continue
		var motor := _free_reel() if tools_here and _hand_seconds(c) > float(ASSUME["greifen_s"]) + float(ASSUME["zur_rolle_s"]) else -1
		if motor >= 0:
			# An eine Motorrolle hängen: kostet den Spieler nur Wege, die Rolle zieht allein
			t += float(ASSUME["greifen_s"]) + float(ASSUME["zur_rolle_s"]) + c.knots_m.size() * float(ASSUME["knoten_rolle_s"])
			var rate := float(Balancing.motor_reel["pull_speed_m_per_s"]) * eco.factor("motor") * eco.bonus("motor")
			reels_free_at[motor] = t + c.length_m / rate
			pending.append([reels_free_at[motor], c])
		else:
			var crank := tools_here and eco.state.level("crank") > 0
			var tool: Dictionary = Balancing.hand_crank if crank else Balancing.hand_wrap
			var mult := eco.factor("grip") * eco.bonus("press")
			var presses := float(ASSUME["klicks_pro_s"])
			if eco.state.level("auto_pull") > 0:
				presses = float(Balancing.upgrades["auto_pull"]["presses_per_second"])
			var rate := minf(presses * float(tool["pull_per_press_m"]) * mult, float(tool["feed_speed_m_per_s"]) * mult)
			var knot_s := float(ASSUME["knoten_s"]) * float(maxi(1, int(Balancing.knot["untie_presses"]) + int(eco.bonus("knot_presses")))) / float(Balancing.knot["untie_presses"])
			t += float(ASSUME["greifen_s"]) + (float(ASSUME["zur_kurbel_s"]) if crank else 0.0) + c.length_m / rate + c.knots_m.size() * knot_s
			_finish(c, way_m)
		_collect(way_m)
		_shop()
		if cord_active:
			_cord(cables)
		# Keine gewöhnlichen Kabel mehr, aber noch Knäuel in der Tasche: abliefern
		if not bag.is_empty() and _done(cables) == cables.size():
			_deliver(way_m)
	# Rest: warten, bis die Rollen fertig sind, dann Tasche leeren
	for p in pending:
		t = maxf(t, float(p[0]))
	_collect(way_m)
	if not bag.is_empty():
		_deliver(way_m)


func _done(cables: Array[CableData]) -> int:
	var n := 0
	for c in cables:
		if c.state == CableData.State.DONE:
			n += 1
	return n


## So lange bräuchte der Spieler, das Kabel selbst per Hand (oder an der Kurbel) zu wickeln
func _hand_seconds(c: CableData) -> float:
	var crank := tools_here and eco.state.level("crank") > 0
	var tool: Dictionary = Balancing.hand_crank if crank else Balancing.hand_wrap
	var mult := eco.factor("grip") * eco.bonus("press")
	var presses := float(ASSUME["klicks_pro_s"])
	if eco.state.level("auto_pull") > 0:
		presses = float(Balancing.upgrades["auto_pull"]["presses_per_second"])
	var rate := minf(presses * float(tool["pull_per_press_m"]) * mult, float(tool["feed_speed_m_per_s"]) * mult)
	return c.length_m / rate


func _free_wagon_slot() -> int:
	for k in wagon_free_at.size():
		if wagon_free_at[k] <= t:
			return k
	return -1


func _free_reel() -> int:
	for k in reels_free_at.size():
		if reels_free_at[k] <= t:
			return k
	return -1


## Fertige Rollen-Kabel gutschreiben
func _collect(way_m: float) -> void:
	for p in pending.duplicate():
		if float(p[0]) <= t:
			pending.erase(p)
			_finish(p[1], way_m)


func _finish(c: CableData, way_m: float) -> void:
	if c.is_important():
		eco.pay_for_cable(c.length_m, minf(float(Balancing.economy["important_pay_factor"]) * eco.bonus("important_pay"), 1.0))
		bag.append(c.port_id)
		# Abliefern, wenn die Tasche voll ist oder das letzte wichtige Kabel dieser Runde drin steckt
		if bag.size() >= eco.bag_capacity() or bag.size() >= _open_important:
			_deliver(way_m)
	else:
		eco.pay_for_cable(c.length_m)


## Zum Serverraum und zurück
func _deliver(way_m: float) -> void:
	var speed := float(Balancing.player["sprint_speed_m_per_s"]) * eco.bonus("walk")
	var ride := float(Balancing.zipline["speed_m_per_s"])
	var seconds := 2.0 * way_m / speed
	# Seilbahn: hin zu Fuß bis zur Station, dann fahren (auch zurück)
	var to_station := float(ASSUME["weg_zur_station_m"]) / speed
	if phase == "wohnviertel" and RackPlan.has_special(eco.state, "zipline_wohnviertel"):
		seconds = minf(seconds, 2.0 * (to_station + float(ASSUME["seil_wohnviertel_m"]) / ride))
	if phase == "altstadt" and RackPlan.has_special(eco.state, "zipline_altstadt") \
			and RackPlan.has_special(eco.state, "zipline_wohnviertel"):
		seconds = minf(seconds, 2.0 * (to_station + float(ASSUME["seil_altstadt_m"]) / ride))
	t += seconds + 3.0
	for port in bag:
		rack.plug(port)
	_open_important -= bag.size()
	bag.clear()
	eco.refresh_bonuses()


func _on_service(service: int, service_name: String, unlocks: String) -> void:
	var def := RackPlan.service_def(service)
	eco.state.money += float(def.get("payout", 0.0))
	var what := ("schaltet „%s“ frei" % eco.upgrade_name(unlocks)) if unlocks != "" else String(def.get("effect", ""))
	_mark("Dienst %d: %s%s" % [rack.active_services(), service_name, (" – " + what) if what != "" else ""])


## Kauft, was gerade bezahlbar und nicht gesperrt ist (billigstes zuerst)
func _shop() -> void:
	while true:
		var best := ""
		for id: String in Balancing.tablet_order:
			if eco.can_buy(id) and (best == "" or eco.cost(id) < eco.cost(best)):
				best = id
		if best == "":
			return
		var price := eco.cost(best)
		eco.buy(best)
		if best == "extra_reel":
			reels_free_at.append(t)
		if best == "wagon":
			for k in int(Balancing.wagon["slots"]):
				wagon_free_at.append(t)
		_mark("Kauf: %s (Stufe %d) für %s" % [eco.upgrade_name(best), eco.state.level(best), Economy.format_money(price)])


## C.O.R.D.: fragt regelmäßig; manchmal verpasst der Spieler das Nein
func _cord(cables: Array[CableData]) -> void:
	var c: Dictionary = Balancing.cord
	while t >= next_ask:
		if rng.randf() < float(ASSUME["nein_quote"]):
			declined += 1
		else:
			orders += 1
			var n := maxi(1, roundi(float(c["order_count"]) * eco.bonus("order_count")))
			cables.append_array(_cables(n, [], 700000 + orders * 1000))
			_mark("C.O.R.D. bestellt %d Kabel" % n)
		next_ask += (float(c["ask_interval_min_s"]) + float(c["ask_interval_max_s"])) * 0.5 * eco.bonus("ask_interval") \
			+ float(c["answer_time_s"])


func _cables(count: int, ports: Array, seed_base: int) -> Array[CableData]:
	var out: Array[CableData] = []
	for k in count:
		out.append(CableData.from_seed(seed_base + k, seed_base + k, Vector3.ZERO))
	for k in mini(ports.size(), count):
		out[k * count / ports.size()].port_id = int(ports[k])
	_shuffle(out)
	return out


func _shuffle(list: Array[CableData]) -> void:
	for k in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp := list[k]
		list[k] = list[j]
		list[j] = tmp


func _mark(text: String) -> void:
	log.append("%8s  %9s  %s" % [_dur(t), Economy.format_money(eco.state.money), text])


func _dur(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
