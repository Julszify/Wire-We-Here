class_name PlayerAnimator
extends RefCounted
## Stellt die Knochen der geriggten Spielfigur per Code (keine Animationsdateien).
## Die Figur meldet jeden Frame ihren Zustand (Tempo, Kabel am Arm, Leine, Seilbahn, Tragen, Kurbeln …)
## und löst kurze Bewegungen aus (`trigger`): Wickelzug, Knoten-Ruck, Einstecken, Aufheben.
##
## Richtungen und Drehungen gelten im Modell-Raum: +Z vorn, +X links, +Y oben.
## Drehung um +X positiv = nach vorn neigen, um +Y positiv = nach links drehen, um +Z positiv = nach rechts neigen.

## Kurzname -> Knochen im Mixamo-Skelett
const BONES := { "hips": "mixamorig_Hips", "spine": "mixamorig_Spine", "spine1": "mixamorig_Spine1",
	"spine2": "mixamorig_Spine2", "neck": "mixamorig_Neck", "head": "mixamorig_Head",
	"leg_l": "mixamorig_LeftUpLeg", "leg_r": "mixamorig_RightUpLeg",
	"shin_l": "mixamorig_LeftLeg", "shin_r": "mixamorig_RightLeg",
	"foot_l": "mixamorig_LeftFoot", "foot_r": "mixamorig_RightFoot",
	"sh_l": "mixamorig_LeftShoulder", "sh_r": "mixamorig_RightShoulder",
	"arm_l": "mixamorig_LeftArm", "arm_r": "mixamorig_RightArm",
	"fore_l": "mixamorig_LeftForeArm", "fore_r": "mixamorig_RightForeArm" }

# --- Gangbild ---
const STRIDE_RAD_PER_M := 2.4      # Schrittphase je gelaufenem Meter (Gehen)
const LEG_SWING_WALK := 0.42       # Beinausschlag (Bogenmaß)
const LEG_SWING_RUN := 0.7
const KNEE_WALK := 0.55            # Kniebeuge beim Vorschwingen
const KNEE_RUN := 1.25
const BOB_WALK := 0.035            # Hüfte auf und ab (Meter, Modell-Raum vor Skalierung der Figur)
const BOB_RUN := 0.06
const LEAN_WALK := 0.05            # Oberkörper nach vorn
const LEAN_RUN := 0.26
const ELBOW_WALK := 0.35
const ELBOW_RUN := 1.45            # beim Rennen pumpen die Unterarme angewinkelt
# --- Stand ---
const BREATH_HZ := 0.28
const IDLE_LOOK_AFTER_S := 4.0     # so lange still stehen, bis die Figur sich umschaut

# Zustand (setzt die Figur jeden Frame)
var speed := 0.0                   # Tempo über Grund, m/s (vorwärts positiv, rückwärts negativ)
var walk_speed := 4.0
var sprint_speed := 7.0
var on_floor := true
var turn_rate := 0.0               # Drehung des Körpers, rad/s (links positiv)
var holding := false               # Kabel am linken Unterarm
var riding := false                # an der Seilbahn
var carrying := false              # Rolle in der rechten Hand
var straining := false             # zieht gegen die Leine
var crank_dir := Vector3.ZERO      # Richtung zum Kurbelgriff (Modell-Raum), solange gekurbelt wird
var look_yaw := 0.0                # Kamera relativ zum Körper
var look_pitch := 0.0

var _skel: Skeleton3D
var _rig: Node3D
var _rig_base_y := 0.0
var _to_skel := Basis()
var _bone: Dictionary = {}

var _t := 0.0
var _phase := 0.0
var _move := 0.0                   # 0 = steht, 1 = läuft (geglättet)
var _run := 0.0                    # 0 = gehen, 1 = rennen (geglättet)
var _lean_side := 0.0
var _strain := 0.0
var _crank := 0.0
var _crank_target := Vector3.FORWARD
var _carry := 0.0
var _hold := 0.0
var _ride := 0.0
var _idle_t := 0.0
var _glance := Vector2.ZERO        # Umschauen im Stand (Gieren, Nicken)
var _glance_target := Vector2.ZERO
var _glance_t := 0.0
var _head := Vector2.ZERO

# Kurze Bewegungen: Wert läuft 0 -> 1 -> 0
var wind := 0.0                    # Wickelzug (wird per Tween von der Figur gesetzt)
var _wind_phase := 0.0
var _tug_t := -1.0
var _reach_t := -1.0
var _pickup_t := -1.0
const TUG_S := 0.4
const REACH_S := 0.7
const PICKUP_S := 0.6


## Skelett vorbereiten; false, wenn ein Knochen fehlt
func setup(skel: Skeleton3D, rig: Node3D, to_skel: Basis) -> bool:
	_skel = skel
	_rig = rig
	_rig_base_y = rig.position.y
	_to_skel = to_skel
	for key: String in BONES:
		var idx := skel.find_bone(String(BONES[key]))
		if idx < 0:
			push_warning("Figur-Skelett: Knochen %s fehlt" % BONES[key])
			return false
		_bone[key] = idx
	return true


func bone(key: String) -> int:
	return int(_bone[key])


## Kurze Bewegung auslösen: "wind" (Wickelzug), "tug" (Knoten-Ruck), "reach" (Einstecken), "pickup" (Aufheben)
func trigger(kind: String) -> void:
	match kind:
		"wind":
			_wind_phase += PI * 0.75
		"tug":
			_tug_t = 0.0
		"reach":
			_reach_t = 0.0
		"pickup":
			_pickup_t = 0.0


func update(delta: float) -> void:
	_t += delta
	var k := 1.0 - exp(-10.0 * delta)
	var abs_speed := absf(speed)
	var target_move := clampf(abs_speed / walk_speed, 0.0, 1.0) if on_floor else _move
	_move = lerpf(_move, target_move, k)
	var run_target := clampf((abs_speed - walk_speed) / maxf(sprint_speed - walk_speed, 0.1), 0.0, 1.0)
	_run = lerpf(_run, run_target, k)
	if on_floor:
		# Beim Rennen werden die Schritte länger statt nur schneller
		_phase += delta * speed * STRIDE_RAD_PER_M / (1.0 + _run * 0.45)
	_lean_side = lerpf(_lean_side, clampf(turn_rate * 0.05, -0.18, 0.18) * _move, k)
	_strain = lerpf(_strain, 1.0 if straining else 0.0, k)
	_crank = lerpf(_crank, 1.0 if crank_dir != Vector3.ZERO else 0.0, 1.0 - exp(-14.0 * delta))
	if crank_dir != Vector3.ZERO:
		_crank_target = crank_dir
	_carry = lerpf(_carry, 1.0 if carrying else 0.0, k)
	_hold = lerpf(_hold, 1.0 if holding else 0.0, 1.0 - exp(-16.0 * delta))
	_ride = lerpf(_ride, 1.0 if riding else 0.0, k)
	for key in ["_tug_t", "_reach_t", "_pickup_t"]:
		var v: float = get(key)
		if v >= 0.0:
			set(key, v + delta)
	if _tug_t > TUG_S:
		_tug_t = -1.0
	if _reach_t > REACH_S:
		_reach_t = -1.0
	if _pickup_t > PICKUP_S:
		_pickup_t = -1.0
	_update_look(delta)
	_pose()


## Kopf: folgt der Kamera; wer lange still steht, schaut sich um
func _update_look(delta: float) -> void:
	var busy := _move > 0.1 or holding or carrying or _crank > 0.1 or riding
	_idle_t = 0.0 if busy else _idle_t + delta
	var want := Vector2(look_yaw, look_pitch)
	if absf(look_yaw) > 1.9:
		want.x = 0.0  # Kamera schaut von vorn: nicht über die Schulter verrenken
	want.x = clampf(want.x, -0.9, 0.9)
	want.y = clampf(want.y, -0.35, 0.45)
	if _idle_t > IDLE_LOOK_AFTER_S:
		_glance_t -= delta
		if _glance_t <= 0.0:
			_glance_t = randf_range(1.6, 3.4)
			_glance_target = Vector2(randf_range(-0.8, 0.8), randf_range(-0.15, 0.25)) if randf() < 0.75 else Vector2.ZERO
	else:
		_glance_target = Vector2.ZERO
	_glance = _glance.lerp(_glance_target, 1.0 - exp(-3.0 * delta))
	_head = _head.lerp(want + _glance, 1.0 - exp(-6.0 * delta))


## 0 -> 1 -> 0 über die Dauer, mit schnellem Anstieg
static func _pulse(t: float, length: float, rise: float = 0.25) -> float:
	if t < 0.0:
		return 0.0
	var x := t / length
	if x < rise:
		return smoothstep(0.0, 1.0, x / rise)
	return 1.0 - smoothstep(0.0, 1.0, (x - rise) / (1.0 - rise))


func _pose() -> void:
	var m := _move
	var run := _run
	var s := sin(_phase)
	var c := cos(_phase)
	var tug := _pulse(_tug_t, TUG_S, 0.2)
	var reach := _pulse(_reach_t, REACH_S, 0.35)
	var pickup := _pulse(_pickup_t, PICKUP_S, 0.4)
	var breath := sin(_t * TAU * BREATH_HZ) * (1.0 - m)

	# --- Hüfte: wippt mit den Schritten, dreht und kippt leicht; beim Aufheben geht sie in die Knie ---
	var bob := -absf(s) * lerpf(BOB_WALK, BOB_RUN, run) * m + 0.012 * m
	bob -= pickup * 0.12 + _strain * 0.03 + tug * 0.03
	_rig.position.y = _rig_base_y + bob * _rig.scale.y
	var hips_yaw := s * 0.14 * m
	var hips_roll := c * 0.05 * m * (1.0 - run * 0.5)
	var hips := Basis(Vector3.UP, hips_yaw) * Basis(Vector3.BACK, hips_roll)
	_turn("hips", hips)

	# --- Oberkörper: nach vorn beim Laufen, zurück gegen die Leine, in die Kurve, atmen ---
	var lean := lerpf(LEAN_WALK, LEAN_RUN, run) * m
	lean += pickup * 0.55 + reach * 0.12 + wind * 0.08 + _crank * 0.12
	lean -= _strain * 0.32 + tug * 0.28
	lean += breath * 0.02
	var twist := -hips_yaw * 1.6 + _crank * sin(_crank_phase()) * 0.12
	var side := _lean_side - _carry * 0.12
	var spine := Basis(Vector3.UP, twist * 0.4) * Basis(Vector3.RIGHT, lean * 0.4) * Basis(Vector3.BACK, side * 0.5)
	var chest_local := Basis(Vector3.UP, twist * 0.6) * Basis(Vector3.RIGHT, lean * 0.6 + breath * 0.015) \
		* Basis(Vector3.BACK, side * 0.5)
	var spine_r := hips * spine
	var chest := spine_r * chest_local
	_turn("spine", hips * Basis(Vector3.UP, twist * 0.2) * Basis(Vector3.RIGHT, lean * 0.2))
	_turn("spine1", spine_r)
	_turn("spine2", chest)
	# Kopf bleibt eher aufrecht und schaut, wohin die Kamera schaut
	var head_pitch := -_head.y - lean * 0.6 + pickup * 0.4
	var head := chest * Basis(Vector3.UP, _head.x - twist * 0.6) * Basis(Vector3.RIGHT, head_pitch)
	_turn("neck", chest.slerp(head, 0.4))
	_turn("head", head)

	# --- Beine ---
	if _ride > 0.5:
		# Hängt an der Seilbahn: Beine baumeln
		var dangle := sin(_t * 1.7) * 0.15
		_leg("l", 1.0, hips, 0.2 + dangle, 0.5)
		_leg("r", -1.0, hips, 0.2 - dangle, 0.55)
	else:
		var swing := lerpf(LEG_SWING_WALK, LEG_SWING_RUN, run) * m
		var knee := lerpf(KNEE_WALK, KNEE_RUN, run) * m
		var dir_sign := 1.0 if speed >= 0.0 else -1.0
		var a_l := s * swing
		var b_l := maxf(0.0, c * dir_sign) * knee + 0.06 + pickup * 1.1 + _strain * 0.25
		var b_r := maxf(0.0, -c * dir_sign) * knee + 0.06 + pickup * 1.1 + _strain * 0.25
		# Gegen die Leine: Beine stemmen sich nach vorn
		var brace := _strain * 0.25 + tug * 0.15
		_leg("l", 1.0, hips, a_l + pickup * 0.55 + brace, b_l)
		_leg("r", -1.0, hips, -a_l + pickup * 0.55 + brace, b_r)

	# --- Arme ---
	var arm_swing := s * lerpf(0.55, 0.8, run) * m
	var elbow := lerpf(ELBOW_WALK, ELBOW_RUN, run) * m + 0.25 * (1.0 - m)
	if _ride > 0.5:
		for sd in [1.0, -1.0]:
			var up := Vector3(0.25 * sd, 1.0, 0.05)
			_arm(sd, chest, up, Vector3(-0.1 * sd, 1.0, 0.0))
		return

	# Rechter Arm: Schwingen, Kurbeln, Tragen, Wickeln, Ruck, Einstecken, Aufheben (gemischt nach Gewicht)
	var r_up := _swing_dir(-1.0, arm_swing, breath)
	var r_fore := _fore_dir(-1.0, arm_swing, elbow)
	if _hold > 0.01:
		# Die rechte Hand wickelt um den linken Unterarm: kreist vor dem Bauch
		var wp := _wind_phase + wind * 1.5
		var w_up := Vector3(0.3, -0.55, 0.78)
		var w_fore := Vector3(0.75 + 0.25 * cos(wp), 0.15 + 0.3 * sin(wp), 0.55)
		r_up = r_up.lerp(w_up, _hold * (0.55 + 0.45 * wind))
		r_fore = r_fore.lerp(w_fore, _hold * (0.55 + 0.45 * wind))
	if _carry > 0.01:
		r_up = r_up.lerp(Vector3(-0.45, -0.86, 0.25), _carry)
		r_fore = r_fore.lerp(Vector3(-0.35, -0.9, 0.25), _carry)
	if _crank > 0.01:
		# Hand folgt dem Griff (Richtung kommt von außen und kreist mit der Kurbel)
		var to_handle := (chest.inverse() * _crank_target).normalized()
		r_up = r_up.lerp((to_handle + Vector3(0, -0.35, 0)).normalized(), _crank)
		r_fore = r_fore.lerp(to_handle, _crank)
	if tug > 0.01:
		r_up = r_up.lerp(Vector3(-0.2, -0.3, 0.9), tug)
		r_fore = r_fore.lerp(Vector3(0.15, -0.1, 1.0), tug)
	if reach > 0.01:
		r_up = r_up.lerp(Vector3(-0.2, -0.05, 1.0), reach)
		r_fore = r_fore.lerp(Vector3(0.05, 0.05, 1.0), reach)
	if pickup > 0.01:
		r_up = r_up.lerp(Vector3(-0.15, -0.6, 0.8), pickup)
		r_fore = r_fore.lerp(Vector3(0.0, -0.8, 0.6), pickup)
	_arm(-1.0, chest, r_up, r_fore)

	# Linker Arm: mit Kabel waagerecht nach vorn (die Wicklung hängt daran), sonst wie rechts
	var l_up := _swing_dir(1.0, -arm_swing, breath)
	var l_fore := _fore_dir(1.0, -arm_swing, elbow)
	if _carry > 0.01:
		# Gegengewicht: linker Arm leicht abgespreizt
		l_up = l_up.lerp(Vector3(0.85, -0.5, 0.1), _carry)
		l_fore = l_fore.lerp(Vector3(0.7, -0.6, 0.3), _carry)
	if reach > 0.01:
		l_up = l_up.lerp(Vector3(0.2, -0.05, 1.0), reach)
		l_fore = l_fore.lerp(Vector3(-0.05, 0.05, 1.0), reach)
	if pickup > 0.01:
		l_up = l_up.lerp(Vector3(0.6, -0.7, 0.3), pickup)
		l_fore = l_fore.lerp(Vector3(0.4, -0.85, 0.3), pickup)
	if _hold > 0.01:
		# Gegen die Leine bzw. beim Ruck zieht der Arm zurück an den Körper
		var pull := maxf(_strain, tug)
		var h_up := Vector3(0.62, -0.75, 0.2 - pull * 0.25)
		var h_fore := Vector3(sin(deg_to_rad(30)), 0.08 + wind * 0.35 - pull * 0.1, cos(deg_to_rad(30)) - pull * 0.2)
		# Die Wicklung soll ruhig bleiben: Unterarm im Modell-Raum, nicht mit dem Oberkörper gedreht
		l_up = l_up.lerp(chest.inverse() * h_up, _hold)
		l_fore = l_fore.lerp(chest.inverse() * h_fore, _hold)
	_arm(1.0, chest, l_up, l_fore)


## Phase der Kurbel aus der Richtung zum Griff (für das Mitschwingen des Oberkörpers)
func _crank_phase() -> float:
	return atan2(_crank_target.x, _crank_target.z) * 3.0


## Oberarm hängt seitlich und schwingt vor und zurück (Arme nur mäßig absenken, sonst im Bauch)
func _swing_dir(sd: float, a: float, breath: float) -> Vector3:
	return Vector3(0.6 * sd, -0.8 * cos(a) + breath * 0.03, 0.8 * sin(a))


func _fore_dir(sd: float, a: float, elbow: float) -> Vector3:
	return Vector3(0.35 * sd, -cos(a + elbow), sin(a + elbow) + 0.15)


## Arm stellen; Richtungen relativ zum Brustkorb. sd = +1 links, -1 rechts.
## Beim Tripo-Rig hängt der Oberarm fast ganz an der Schulter, daher Schulter und Arm gemeinsam.
func _arm(sd: float, chest: Basis, up_dir: Vector3, fore_dir: Vector3) -> void:
	var s := "l" if sd > 0.0 else "r"
	var up := chest * up_dir.normalized()
	_aim("sh_" + s, up)
	_aim("arm_" + s, up)
	_aim("fore_" + s, chest * fore_dir.normalized())


## Bein stellen: a = Ausschlag nach vorn, b = Kniebeuge (beides Bogenmaß)
func _leg(s: String, sd: float, hips: Basis, a: float, b: float) -> void:
	_aim("leg_" + s, hips * Vector3(0.05 * sd, -cos(a), sin(a)))
	_aim("shin_" + s, hips * Vector3(0.03 * sd, -cos(a - b), sin(a - b)))
	# Fuß bleibt flach; hinten (Abdruck) zeigt die Spitze etwas nach unten
	var push := clampf(-a, 0.0, 0.6)
	_aim("foot_" + s, hips * Vector3(0.25 * sd, -0.6 - push, 0.76 - push * 0.4))


## Knochen so drehen, dass seine Längsachse (Y) in `dir` zeigt (Modell-Raum)
func _aim(key: String, dir: Vector3) -> void:
	var b := int(_bone[key])
	var rest := _skel.get_bone_global_rest(b)
	var q := Quaternion(rest.basis.y.normalized(), (_to_skel * dir).normalized())
	_set_global(b, Basis(q) * rest.basis)


## Knochen aus der Ruhelage um `rot` drehen (Modell-Raum, absolut, nicht relativ zum Elternknochen)
func _turn(key: String, rot: Basis) -> void:
	var b := int(_bone[key])
	var rest := _skel.get_bone_global_rest(b)
	_set_global(b, (_to_skel * rot * _to_skel.inverse()) * rest.basis)


func _set_global(b: int, want: Basis) -> void:
	var parent := _skel.get_bone_parent(b)
	var parent_basis := _skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skel.set_bone_pose_rotation(b, Quaternion((parent_basis.inverse() * want).orthonormalized()))
