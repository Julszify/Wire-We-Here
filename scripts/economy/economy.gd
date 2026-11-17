class_name Economy
extends Node
## Geld verdienen und Upgrades kaufen. Alle Preise und Faktoren aus balancing.json.

signal money_changed(money: float)
signal upgrade_bought(upgrade_id: String, level: int)
## Kosmetik gekauft oder angelegt (Platz, Stück)
signal look_changed(slot: String, item_id: String)

var state := GameState.new()
var _unlockers: Dictionary = {}  # Upgrade-ID -> Dienst, der es freischaltet
## Boni der laufenden Dienste (RackPlan.bonuses); wird von außen gesetzt, wenn sich Dienste ändern
var bonuses: Dictionary = {}


func _ready() -> void:
	state.money = float(Balancing.economy.get("starting_money", 0.0))


## Bezahlung für ein fertig aufgerolltes Kabel. Gibt den Betrag zurück.
## `factor` < 1 z. B. für wichtige Kabel, die zusätzlich einen Dienst reaktivieren.
func pay_for_cable(length_m: float, factor: float = 1.0) -> float:
	var per_meter: float = float(Balancing.economy["money_per_meter"]) * factor
	per_meter *= factor("copper") * bonus("money")
	var amount := length_m * per_meter
	state.money += amount
	state.total_earned += amount
	money_changed.emit(state.money)
	return amount


func cost(upgrade_id: String) -> float:
	var u: Dictionary = Balancing.upgrades[upgrade_id]
	return float(u["base_cost"]) * pow(float(u.get("cost_growth", 1.0)), state.level(upgrade_id))


func is_maxed(upgrade_id: String) -> bool:
	var u: Dictionary = Balancing.upgrades[upgrade_id]
	return u.has("max_count") and state.level(upgrade_id) >= int(u["max_count"])


## Gesperrt, solange ein Dienst, der dieses Upgrade freischaltet, noch nicht läuft.
func is_locked(upgrade_id: String) -> bool:
	return locked_by(upgrade_id) >= 0


## Dienst, der das Upgrade noch sperrt, oder -1.
func locked_by(upgrade_id: String) -> int:
	if _unlockers.is_empty():
		for service in RackPlan.total_services():
			var u := RackPlan.service_unlocks(service)
			if u != "":
				_unlockers[u] = service
	if _unlockers.has(upgrade_id) and not RackPlan.service_active(state, int(_unlockers[upgrade_id])):
		return int(_unlockers[upgrade_id])
	return -1


## Bonus aus laufenden Diensten (Faktor; bei additiven Boni die Summe)
func bonus(key: String) -> float:
	return float(bonuses.get(key, 0.0 if RackPlan.ADDITIVE.has(key) else 1.0))


func refresh_bonuses() -> void:
	bonuses = RackPlan.bonuses(state)
	# Serverraum-Ausbau: jede Stufe wirkt wie ein weiterer Dienst-Bonus ("bonus" je Stufe in balancing.json)
	for id in Balancing.room_order:
		var lvl := state.level(String(id))
		var b: Dictionary = Balancing.upgrades.get(String(id), {}).get("bonus", {})
		for key: String in b:
			_merge_bonus(key, float(b[key]), lvl)
	# Ruf aus früheren Aufträgen: mehr Geld und schnelleres Ziehen; C.O.R.D. bestellt mit jedem Auftrag eifriger
	var pr: Dictionary = Balancing.prestige
	if state.reputation > 0:
		var r := float(state.reputation)
		_merge_bonus("money", 1.0 + float(pr.get("money_per_point", 0.1)) * r, 1)
		var speed := 1.0 + float(pr.get("speed_per_point", 0.05)) * r
		_merge_bonus("press", speed, 1)
		_merge_bonus("motor", speed, 1)
	if state.prestige_count > 0:
		_merge_bonus("order_count", pow(float(pr.get("cord_order_growth", 1.15)), state.prestige_count), 1)
		_merge_bonus("ask_interval", pow(float(pr.get("cord_interval_factor", 0.9)), state.prestige_count), 1)


## Bonus `value` `times`-mal einrechnen (Faktor multipliziert, additive Schlüssel addiert)
func _merge_bonus(key: String, value: float, times: int) -> void:
	if times <= 0:
		return
	if RackPlan.ADDITIVE.has(key):
		bonuses[key] = float(bonuses.get(key, 0.0)) + value * times
	else:
		bonuses[key] = float(bonuses.get(key, 1.0)) * pow(value, times)


# ---------------------------------------------------------------- Neuer Auftrag (Prestige)

## Ruf-Punkte, die ein neuer Auftrag jetzt brächte (aus dem Verdienst dieses Auftrags)
func reputation_gain() -> int:
	var pr: Dictionary = Balancing.prestige
	return floori(float(pr.get("points_per_sqrt_million", 1.0)) * sqrt(state.total_earned / 1000000.0))


## Neuer Auftrag möglich? (erst nach dem Finale)
func can_prestige() -> bool:
	return (state.finale_done or not bool(Balancing.prestige.get("requires_finale", true))) and reputation_gain() > 0


## Zustand für den neuen Auftrag: nur Ruf, Zahl der Aufträge und Kosmetik bleiben
func prestige_meta() -> Dictionary:
	var meta := state.meta_dict()
	meta["reputation"] = state.reputation + reputation_gain()
	meta["prestige_count"] = state.prestige_count + 1
	return meta


# ---------------------------------------------------------------- Kosmetik

static func cosmetic_def(item_id: String) -> Dictionary:
	for it: Dictionary in Balancing.cosmetics.get("items", []):
		if String(it["id"]) == item_id:
			return it
	return {}


static func cosmetic_items(slot: String) -> Array:
	return Balancing.cosmetics.get("items", []).filter(func(it: Dictionary) -> bool: return String(it["slot"]) == slot)


func owns_cosmetic(item_id: String) -> bool:
	return float(cosmetic_def(item_id).get("cost", 0.0)) <= 0.0 or state.cosmetics.has(item_id)


## Angelegtes Stück eines Platzes ("" = Grundausstattung)
func look(slot: String) -> String:
	return String(state.looks.get(slot, ""))


## Farbe des angelegten Stücks oder `fallback`
func look_color(slot: String, fallback: Color) -> Color:
	var def := cosmetic_def(look(slot))
	return Color.html(String(def["color"])) if def.has("color") else fallback


## Kaufen (falls nötig) und anlegen; false, wenn das Geld nicht reicht
func wear_cosmetic(item_id: String) -> bool:
	var def := cosmetic_def(item_id)
	if def.is_empty():
		return false
	if not owns_cosmetic(item_id):
		var price := float(def.get("cost", 0.0))
		if state.money < price - 1e-6:
			return false
		state.money -= price
		state.cosmetics.append(item_id)
		money_changed.emit(state.money)
	var slot := String(def["slot"])
	state.looks[slot] = item_id
	look_changed.emit(slot, item_id)
	return true


## Zahl der Knäuel, die in die Tasche passen
func bag_capacity() -> int:
	var per_level := int(Balancing.upgrades.get("bag", {}).get("effect_add", 0))
	return int(Balancing.bag.get("capacity", 3)) + per_level * state.level("bag") + int(bonus("bag"))


func can_buy(upgrade_id: String) -> bool:
	return not is_locked(upgrade_id) and not is_maxed(upgrade_id) and state.money >= cost(upgrade_id) - 1e-6


## Wirkungsfaktor eines Upgrades: effect_factor ^ Stufe (1.0 ohne Upgrade)
func factor(upgrade_id: String) -> float:
	var u: Dictionary = Balancing.upgrades.get(upgrade_id, {})
	return pow(float(u.get("effect_factor", 1.0)), state.level(upgrade_id))


func buy(upgrade_id: String) -> bool:
	if not can_buy(upgrade_id):
		return false
	state.money -= cost(upgrade_id)
	state.upgrades[upgrade_id] = state.level(upgrade_id) + 1
	money_changed.emit(state.money)
	upgrade_bought.emit(upgrade_id, state.level(upgrade_id))
	return true


func upgrade_description(upgrade_id: String) -> String:
	return String(Balancing.upgrades[upgrade_id].get("description", ""))


func upgrade_name(upgrade_id: String) -> String:
	return String(Balancing.upgrades[upgrade_id].get("name", upgrade_id))


## Deutsche Schreibweise: 1.234,50 €
static func format_money(value: float) -> String:
	var cents := roundi(value * 100.0)
	var rest := absi(cents) % 100
	var digits := str(floori(absi(cents) / 100.0))
	var grouped := ""
	while digits.length() > 3:
		grouped = "." + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	var prefix := "-" if cents < 0 else ""
	return "%s%s%s,%02d €" % [prefix, digits, grouped, rest]


## Kurz für Knöpfe: 950 € · 12,5 Tsd. € · 3,2 Mio. € · 1,4 Mrd. €
static func format_short(value: float) -> String:
	var units := [[1e9, "Mrd."], [1e6, "Mio."], [1e3, "Tsd."]]
	for u: Array in units:
		if absf(value) >= float(u[0]):
			var v := value / float(u[0])
			var txt := ("%.0f" % v) if v >= 100.0 else (("%.1f" % v) if v >= 10.0 else ("%.2f" % v))
			if txt.contains("."):
				txt = txt.rstrip("0").rstrip(".")
			return "%s %s €" % [txt.replace(".", ","), u[1]]
	return format_money(value) if value < 100.0 else "%d €" % roundi(value)
