class_name CableBatcher
extends Node3D
## Verwaltet die Blöcke ruhender Kabel (CableBatch): anlegen, entfernen, Kabel aus- und einblenden,
## Detailstufen nach Kamera-Entfernung nachbauen. Schwere Arbeit (Kabel aus Seeds erzeugen, Meshes
## berechnen) läuft im WorkerThreadPool; der Hauptthread übernimmt nur fertige Ergebnisse.

var camera: Camera3D
var _batches: Array[CableBatch] = []
var _of: Dictionary = {}             # Kabel-ID -> CableBatch
var _jobs: Array[Dictionary] = []
var _check_t := 0.0
var prof_us := 0                     # Leistungstest: Rechenzeit in _process (Mikrosekunden, aufsummiert)


func _ready() -> void:
	PlugMeshes.preload_model()  # Stecker-Modell auf dem Hauptthread laden, Threads lesen es nur


## Beim Beenden auf laufende Aufträge warten (sie lesen Balancing, das danach freigegeben wird)
func _exit_tree() -> void:
	for job in _jobs:
		WorkerThreadPool.wait_for_task_completion(job["task"])
	_jobs.clear()


func batch_count() -> int:
	return _batches.size()


## Für Leistungstests: wie viele Blöcke haben welche Stufe gebaut, wie viele Kabel, Ausdehnung
func stats() -> String:
	var n := [0, 0, 0]
	var cables := 0
	var ext := 0.0
	for b in _batches:
		for lod in 3:
			if b.lod_ready[lod]:
				n[lod] += 1
		cables += b.cables.size()
		ext = maxf(ext, b.extent)
	return "nah=%d mittel=%d fern=%d kabel_in_bloecken=%d max_ausdehnung=%.0f auftraege=%d" % [n[0], n[1], n[2], cables, ext, _jobs.size()]


func has(cable_id: int) -> bool:
	return _of.has(cable_id)


func set_hidden(cable_id: int, hidden: bool) -> void:
	var b: CableBatch = _of.get(cable_id)
	if b:
		b.set_hidden(cable_id, hidden)


## Sofort (Hauptthread): Block aus fertigen Kabeln, ferne Stufe gleich gebaut
func add_now(owner_key: String, list: Array[CableData], origin: Vector3, extent: float) -> CableBatch:
	var b := _make(owner_key, list, origin, extent)
	b.apply_lod(CableBatch.Lod.FAR, CableBatch.build_arrays(CableBatch.snapshot(list), origin, CableBatch.Lod.FAR))
	return b


## Alle Blöcke eines Besitzers entfernen (Einheit entladen, Zone neu erzeugt); laufende Aufträge verfallen
func remove_owner(owner_key: String) -> void:
	for b in _batches.duplicate():
		if b.key != owner_key:
			continue
		for c in b.cables:
			if _of.get(c.id) == b:
				_of.erase(c.id)
		_batches.erase(b)
		b.queue_free()
	for job in _jobs:
		if job["key"] == owner_key:
			job["cancelled"] = true


## Kabel einer Einheit in Threads erzeugen. plans: aus CableBatch.plan(); make(index) -> CableData;
## skip: Kabel-IDs, die fehlen sollen (fertig aufgerollt). done(batch, normale, wichtige) läuft auf dem
## Hauptthread, sobald ein Block fertig ist. now = warten, bis alles da ist (Spielstart, Laden).
func load_async(owner_key: String, plans: Array, make: Callable, skip: Dictionary, done: Callable, now: bool) -> void:
	var mine: Array[Dictionary] = []
	for pl: Dictionary in plans:
		var job := { "kind": "unit", "key": owner_key, "plan": pl, "make": make, "skip": skip, "done": done,
			"cancelled": false }
		job["task"] = WorkerThreadPool.add_task(_run_unit_job.bind(job), false, "Kabel erzeugen")
		mine.append(job)
	if now:
		for job in mine:
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_finish(job)
	else:
		_jobs.append_array(mine)


## Wartet auf alle laufenden Aufträge eines Besitzers und übernimmt sie (z. B. wenn ein Spielstand
## Kabel einer gerade ladenden Einheit braucht)
func finish_owner(owner_key: String) -> void:
	for job in _jobs.duplicate():
		if job["key"] == owner_key:
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_jobs.erase(job)
			if not job["cancelled"]:
				_finish(job)


func is_loading(owner_key: String) -> bool:
	for job in _jobs:
		if job["key"] == owner_key and job["kind"] == "unit" and not job["cancelled"]:
			return true
	return false


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_jobs(delta)
	prof_us += Time.get_ticks_usec() - t0


func _process_jobs(delta: float) -> void:
	# Fertige Aufträge übernehmen (nicht zu viele auf einmal, damit es nicht ruckelt)
	var budget := int(Balancing.cable_batch.get("jobs_per_frame", 6))
	var i := 0
	while i < _jobs.size() and budget > 0:
		var job: Dictionary = _jobs[i]
		if not WorkerThreadPool.is_task_completed(job["task"]):
			i += 1
			continue
		WorkerThreadPool.wait_for_task_completion(job["task"])
		_jobs.remove_at(i)
		if not job["cancelled"]:
			_finish(job)
			budget -= 1
	_check_t -= delta
	if _check_t <= 0.0 and camera:
		_check_t = float(Balancing.cable_batch.get("check_s", 0.3))
		_update_lods()


## Nahe und mittlere Stufe bauen, wenn die Kamera näher kommt, und wieder freigeben, wenn sie sich entfernt
func _update_lods() -> void:
	var cfg: Array = Balancing.cable_batch["lods"]
	var cam := camera.global_position
	var submitted := 0
	var max_submit := int(Balancing.cable_batch.get("lod_jobs_per_check", 24))
	for b in _batches:
		var d := cam.distance_to(b.global_position)
		for lod in [CableBatch.Lod.NEAR, CableBatch.Lod.MID]:
			var build_m := float(cfg[lod]["build_m"]) + b.extent * (0.6 if lod == CableBatch.Lod.NEAR else 1.0)
			var free_m := float(cfg[lod]["free_m"]) + b.extent
			if d < build_m and not b.lod_ready[lod] and not b.lod_pending[lod] and submitted < max_submit:
				_submit_lod(b, lod)
				submitted += 1
			elif d > free_m and b.lod_ready[lod]:
				b.drop_lod(lod)
				b.update_ranges()


func _submit_lod(b: CableBatch, lod: int) -> void:
	b.lod_pending[lod] = true
	var job := { "kind": "lod", "key": b.key, "batch": b, "lod": lod, "src": CableBatch.snapshot(b.cables),
		"origin": b.position, "cancelled": false }
	job["task"] = WorkerThreadPool.add_task(_run_lod_job.bind(job), false, "Kabel-Mesh")
	_jobs.append(job)


func _make(owner_key: String, list: Array[CableData], origin: Vector3, extent: float) -> CableBatch:
	var b := CableBatch.new()
	add_child(b)
	b.setup(owner_key, list, origin, extent)
	_batches.append(b)
	for c in list:
		_of[c.id] = b
	return b


func _finish(job: Dictionary) -> void:
	if job["kind"] == "lod":
		var b: CableBatch = job["batch"]
		if is_instance_valid(b) and _batches.has(b):
			b.apply_lod(job["lod"], job["arrays"])
		return
	var pl: Dictionary = job["plan"]
	var normal: Array[CableData] = job["normal"]
	var b: CableBatch = null
	if not normal.is_empty():
		b = _make(job["key"], normal, pl["origin"], float(pl["extent"]))
		b.apply_lod(CableBatch.Lod.FAR, job["far"])
	(job["done"] as Callable).call(b, normal, job["important"] as Array[CableData])


# ---------------------------------------------------------------- in Threads

func _run_unit_job(job: Dictionary) -> void:
	var pl: Dictionary = job["plan"]
	var make: Callable = job["make"]
	var skip: Dictionary = job["skip"]
	var normal: Array[CableData] = []
	var important: Array[CableData] = []
	for i in (pl["indices"] as PackedInt32Array):
		var c: CableData = make.call(i)
		if c == null or skip.has(c.id):
			continue
		if c.is_important():
			important.append(c)
		else:
			normal.append(c)
	job["normal"] = normal
	job["important"] = important
	job["far"] = CableBatch.build_arrays(CableBatch.snapshot(normal), pl["origin"], CableBatch.Lod.FAR)


func _run_lod_job(job: Dictionary) -> void:
	job["arrays"] = CableBatch.build_arrays(job["src"], job["origin"], job["lod"])
