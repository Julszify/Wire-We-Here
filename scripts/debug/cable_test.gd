extends Node3D
## Testaufbau für Meilenstein 3: ein Kabel an der Handkurbel ziehen und aufwickeln.
## Linksklick: kurbeln (Aktion "pull") · N: nächstes Kabel · B: vorheriges · L: Balancing-JSON neu laden
## Kommandozeile (zum Testen): godot -- --seed=5 --pull=2.5

@export var start_seed: int = 1
@export var reel_position := Vector3(4.5, 0.0, 0.0)

var _seed: int
var _next_id := 0
var _system: CableSystem
var _reel: ReelData
var _reel_view: ReelView
var _cable: CableData
var _cable_view: CableView
var _dirty := false
var _fading: CableView
var _fade_t := 0.0
var _label: Label


func _ready() -> void:
	_seed = start_seed
	var pre_pull := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--pull="):
			pre_pull = float(arg.trim_prefix("--pull="))

	_system = CableSystem.new()
	add_child(_system)
	_system.cable_pulled.connect(_on_cable_pulled)
	_system.cable_completed.connect(_on_cable_completed)

	_reel = ReelData.new(0, ReelData.Kind.HAND, reel_position)
	_system.add_reel(_reel)
	_reel_view = ReelView.new()
	add_child(_reel_view)
	_reel_view.setup(_reel)

	_build_label()
	_spawn()
	if pre_pull > 0.0:
		_system.pull(_reel, pre_pull)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pull", false):
		_system.press(_reel)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_N:
				_seed += 1
				_spawn()
			KEY_B:
				_seed -= 1
				_spawn()
			KEY_L:
				Balancing.reload()
				_spawn()


func _process(delta: float) -> void:
	if _dirty and _cable_view != null:
		_dirty = false
		_reel_view.set_phase(_cable_view.show_on_reel(_reel.position))
	if _fading != null:
		_fade_t += delta / float(Balancing.reel["done_fade_s"])
		_fading.set_fade(1.0 - _fade_t)
		if _fade_t >= 1.0:
			_fading.queue_free()
			_fading = null
			_seed += 1
			_spawn()
	_update_label()


func _spawn() -> void:
	# Altes Kabel entfernen (auch wenn es noch hängt)
	if _cable != null:
		if _cable.state == CableData.State.HOOKED:
			_reel.cable_id = -1
		_system.remove_cable(_cable.id)
	if _cable_view != null and _cable_view != _fading:
		_cable_view.queue_free()

	_cable = CableData.from_seed(_next_id, _seed, Vector3.ZERO)
	_next_id += 1
	_system.add_cable(_cable)
	_cable_view = CableView.new()
	add_child(_cable_view)
	_cable_view.setup(_cable)
	_system.hook(_cable, _reel)
	_dirty = true


func _on_cable_pulled(cable: CableData, _reel_data: ReelData, _meters: float) -> void:
	if cable == _cable:
		_dirty = true


func _on_cable_completed(cable: CableData, _reel_data: ReelData) -> void:
	if cable != _cable:
		return
	# Letzten Stand zeigen, dann ausblenden und nächstes Kabel holen
	_reel_view.set_phase(_cable_view.show_on_reel(_reel.position))
	_dirty = false
	_fading = _cable_view
	_fade_t = 0.0
	_system.remove_cable(cable.id)
	_cable = null
	_cable_view = null


func _build_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


func _update_label() -> void:
	var line := "Kabel fertig!"
	if _cable != null:
		line = "Seed %d   ·   %.1f von %.1f m gezogen   ·   Knoten %d (noch ohne Wirkung)" % [
			_seed, _cable.pulled_m, _cable.length_m, _cable.knots_m.size()]
	_label.text = line + "\nLinksklick = kurbeln   N = nächstes Kabel   B = vorheriges   L = Balancing neu laden"
