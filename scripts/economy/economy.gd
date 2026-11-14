class_name Economy
extends Node
## Geld verdienen und Upgrades kaufen. Alle Preise und Faktoren aus balancing.json.

signal money_changed(money: float)
signal upgrade_bought(upgrade_id: String, level: int)

var state := GameState.new()


func _ready() -> void:
	state.money = float(Balancing.economy.get("starting_money", 0.0))


## Bezahlung für ein fertig aufgerolltes Kabel. Gibt den Betrag zurück.
## `factor` < 1 z. B. für wichtige Kabel, die zusätzlich einen Dienst reaktivieren.
func pay_for_cable(length_m: float, factor: float = 1.0) -> float:
	var per_meter: float = float(Balancing.economy["money_per_meter"]) * factor
	per_meter *= factor("copper")
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


## Port des Dienstes, der das Upgrade noch sperrt, oder -1.
func locked_by(upgrade_id: String) -> int:
	for port in Balancing.services.size():
		if String(Balancing.services[port].get("unlocks", "")) == upgrade_id and not state.active_ports.has(port):
			return port
	return -1


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
