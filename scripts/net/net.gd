extends Node
## Autoload "Net": Mehrspieler über ENet (IP und Port), bis 4 Spieler. Der Host rechnet die ganze Spiellogik;
## Clients bauen dieselbe Stadt aus denselben Seeds, schicken nur Absichten und bekommen den Zustand.
##
## Ablauf beim Beitreten: Client verbindet → hello(Name, Version) → Host schickt welcome(Spielstand, gepackt)
## → Client lädt die Welt und wendet den Spielstand an → entered() → Host legt den Mitspieler an.
## Alle Spiel-Nachrichten laufen über dieses Autoload (der Pfad existiert immer) und werden an die gerade
## registrierte Welt weitergereicht (`world`).

signal status_changed(text: String)
signal peers_changed

enum Role { OFFLINE, HOST, CLIENT }

const VERSION := 1
const MAX_PLAYERS := 4

var role := Role.OFFLINE
## Spieler: Peer-ID -> { "name": String }
var peers: Dictionary = {}
## Client: Spielstand vom Host ist da, die Welt kann geladen werden
var ready_to_enter := false
## Client: Spielstand vom Host (für die Welt beim Laden)
var join_snapshot: Dictionary = {}
## Meldung fürs Hauptmenü (z. B. Verbindung verloren)
var last_message := ""
## Die laufende Welt (world.gd), registriert sich selbst
var world: Node = null


func _ready() -> void:
	status_changed.connect(func(t: String) -> void: print("NET: ", t))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


## Eigene Peer-ID (offline 1, damit Host und Einzelspieler gleich aussehen)
func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func player_name(id: int) -> String:
	return String(peers.get(id, {}).get("name", "Spieler %d" % id))


# ---------------------------------------------------------------- Verbinden

func host(port: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	peers = { 1: { "name": _own_name() } }
	peers_changed.emit()
	status_changed.emit("Du hostest auf Port %d." % port)
	return OK


func join(address: String, port: int) -> Error:
	leave()
	if address.strip_edges() == "":
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	ready_to_enter = false
	join_snapshot = {}
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	peers.clear()
	ready_to_enter = false
	join_snapshot = {}


func _own_name() -> String:
	var n := String(Settings.player_name).strip_edges()
	return n.substr(0, 20) if n != "" else "Admin"


## Großzügige Zeitgrenze: beim Neuaufbau der Stadt (neuer Auftrag) blockieren Host und Client einige Sekunden
func _long_timeout(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var p := enet.get_peer(id)
	if p:
		p.set_timeout(64, 45000, 90000)


func _on_connected() -> void:
	_long_timeout(1)
	status_changed.emit("Verbunden – warte auf den Spielstand des Hosts …")
	_hello.rpc_id(1, _own_name(), VERSION)


func _on_failed() -> void:
	leave()
	status_changed.emit("Verbindung fehlgeschlagen. Adresse, Port und Freigabe prüfen.")


func _on_server_lost() -> void:
	leave()
	last_message = "Die Verbindung zum Host ist abgebrochen."
	status_changed.emit(last_message)
	if world:
		world.call_deferred("net_back_to_menu")


func _on_peer_connected(id: int) -> void:
	if is_host():
		_long_timeout(id)  # Der Client meldet sich dann mit hello


func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	var n := player_name(id)
	peers.erase(id)
	peers_changed.emit()
	if is_host():
		_peers_update.rpc(peers)
		if world:
			world.net_player_left(id, n)


# ---------------------------------------------------------------- Handschlag

@rpc("any_peer", "reliable")
func _hello(name_value: String, version: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != VERSION:
		_refuse.rpc_id(id, "Andere Spielversion (Host %d, du %d)." % [VERSION, version])
		return
	if peers.size() >= MAX_PLAYERS:
		_refuse.rpc_id(id, "Das Spiel ist voll (%d Spieler)." % MAX_PLAYERS)
		return
	peers[id] = { "name": name_value.strip_edges().substr(0, 20) if name_value.strip_edges() != "" else "Admin" }
	peers_changed.emit()
	_peers_update.rpc(peers)
	if world:
		send_welcome(id)


## Host: Spielstand an einen Client (oder alle, id = 0) schicken; die Welt liefert ihn
func send_welcome(id: int) -> void:
	if world == null:
		return
	var data: PackedByteArray = pack(world.net_snapshot_for_join())
	if id == 0:
		for pid: int in _connected():
			_welcome.rpc_id(pid, data, peers)
	else:
		_welcome.rpc_id(id, data, peers)


@rpc("authority", "reliable")
func _welcome(data: PackedByteArray, all_peers: Dictionary) -> void:
	peers = all_peers
	join_snapshot = unpack(data)
	ready_to_enter = true
	peers_changed.emit()
	status_changed.emit("Spielstand erhalten – die Stadt wird aufgebaut …")
	# Schon in einer Welt (z. B. der Host hat einen neuen Auftrag begonnen): neu laden
	if world:
		world.call_deferred("net_reload_world")


@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	leave()
	last_message = reason
	status_changed.emit(reason)


@rpc("authority", "reliable")
func _peers_update(all_peers: Dictionary) -> void:
	peers = all_peers
	peers_changed.emit()


# ---------------------------------------------------------------- Spiel-Nachrichten

## Client → Host: Absicht (greifen, ziehen, kaufen …)
func send_intent(kind: String, args: Dictionary = {}) -> void:
	if is_client():
		_intent.rpc_id(1, kind, args)


@rpc("any_peer", "reliable")
func _intent(kind: String, args: Dictionary) -> void:
	if is_host() and world and peers.has(multiplayer.get_remote_sender_id()):
		world.net_intent(multiplayer.get_remote_sender_id(), kind, args)


## Host → Clients (to = 0: alle): Ereignis
func send_event(kind: String, args: Dictionary = {}, to: int = 0) -> void:
	if not is_host():
		return
	if to == 0:
		for pid: int in _connected():
			_event.rpc_id(pid, kind, args)
	elif to != 1 and _connected().has(to):
		_event.rpc_id(to, kind, args)


@rpc("authority", "reliable")
func _event(kind: String, args: Dictionary) -> void:
	if world:
		world.net_event(kind, args)


## Host → Clients: laufender Zustand (Rollen, Kabel, Geld …), darf verloren gehen
func send_snapshot(data: Dictionary) -> void:
	if not is_host():
		return
	# Gepackt; passt es nicht in ein Paket, lieber zuverlässig (sonst geht es oft verloren)
	var packed := pack(data)
	for pid: int in _connected():
		if packed.size() < 1200:
			_snapshot.rpc_id(pid, packed)
		else:
			_snapshot_big.rpc_id(pid, packed)


@rpc("authority", "unreliable_ordered")
func _snapshot(data: PackedByteArray) -> void:
	if world:
		world.net_snapshot(unpack(data))


@rpc("authority", "reliable")
func _snapshot_big(data: PackedByteArray) -> void:
	if world:
		world.net_snapshot(unpack(data))


## Eigene Figur (Lage, Bewegung) an alle anderen; der Host leitet weiter
func send_player_state(state: Array) -> void:
	if is_client():
		_pstate_up.rpc_id(1, state)
	elif is_host():
		for pid: int in _connected():
			_pstate_down.rpc_id(pid, 1, state)


@rpc("any_peer", "unreliable_ordered")
func _pstate_up(state: Array) -> void:
	if not is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	if world:
		world.net_player_state(from, state)
	for pid: int in _connected():
		if pid != from:
			_pstate_down.rpc_id(pid, from, state)


@rpc("authority", "unreliable_ordered")
func _pstate_down(id: int, state: Array) -> void:
	if world and id != local_id():
		world.net_player_state(id, state)


## Host: Clients, die verbunden sind und sich angemeldet haben
func _connected() -> Array[int]:
	var out: Array[int] = []
	var live := multiplayer.get_peers()
	for pid: int in peers:
		if pid != 1 and live.has(pid):
			out.append(pid)
	return out


# ---------------------------------------------------------------- Packen

static func pack(d: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(d)
	var out := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var head := PackedByteArray()
	head.resize(4)
	head.encode_u32(0, raw.size())
	return head + out


static func unpack(data: PackedByteArray) -> Dictionary:
	if data.size() < 4:
		return {}
	var size := data.decode_u32(0)
	var raw := data.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var v: Variant = bytes_to_var(raw)
	return v if typeof(v) == TYPE_DICTIONARY else {}
