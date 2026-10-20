class_name NetSession
extends Node
## Co-op B: the house-network link (Godot's own ENet; nothing third-party). One per process, under the tree's root so
## it outlives the scene reloads a game start does (`NetSession.current`). The host opens PORT, says so with a UDP
## beacon on BEACON_PORT every second (a joiner's title screen lists it: no typing), hands each joiner a slot
## (`rpc_hello` -> `rpc_welcome`), the world as a save (`rpc_snapshot`: the joiner writes it to JOIN_FILE and reloads
## the scene as a load) and then NetSync refreshes at REFRESH_HZ (`rpc_refresh`). A joiner sends its position up at
## STATE_HZ (`rpc_player_state`); the host trusts it. Host and joiner both `attach` the SimWorld main.gd built.
## Pure link; the words and the world are main.gd's and NetSync's.

const PORT := 40611
const BEACON_PORT := 40612
const REFRESH_HZ := 10.0
const STATE_HZ := 20.0
const BEACON_EVERY := 1.0
const GAME_TAG := "noise-floor"
const JOIN_FILE := "user://net_join.json"
const MAX_PEERS := 4
const JOIN_TIMEOUT := 8.0  # seconds a joiner waits for a welcome before it says nobody answered (ENet's own wait is longer)

static var current: NetSession  # this process's link, if any

signal welcomed(slot: int)
signal snapshot_arrived
signal games_changed
signal link_failed(why: String)

var role := ""  # "host", "joiner" or ""
var player_name := ""
var sim: SimWorld  # the host's live world, or the joiner's copy (main.gd attaches it)
var sync: NetSync  # host side
var local_slot := -1  # joiner: my slot in the host's players
var peers: Dictionary = {}  # host: peer id -> slot
var games: Dictionary = {}  # joiner's title screen: "address:port" -> {name, address, port, version, seen}
var status := ""
var snapshot_ready := false
var beacon_address := "255.255.255.255"  # tests point it at 127.0.0.1
var counts := {"refreshes_sent": 0, "refreshes_got": 0, "states_got": 0, "beacons_got": 0}
var _peer: ENetMultiplayerPeer
var _beacon: PacketPeerUDP
var _listen: PacketPeerUDP
var _refresh_t := 0.0
var _state_t := 0.0
var _beacon_t := 0.0
var _port := PORT
var _address := ""
var _join_t := 0.0  # joiner: seconds waiting for the welcome; -1 once it's given up


## The process's link, made under `root` the first time (outside the scene, so a reload keeps it).
static func start(root: Node) -> NetSession:
	if current != null and is_instance_valid(current):
		return current
	var n := NetSession.new()
	n.name = "NetSession"
	root.add_child(n)
	current = n
	return n


static func is_joiner() -> bool:
	return current != null and is_instance_valid(current) and current.role == "joiner"


static func is_host() -> bool:
	return current != null and is_instance_valid(current) and current.role == "host"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the link runs while a menu pauses the tree
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Couldn't reach the host"))
	multiplayer.server_disconnected.connect(func() -> void: _fail("The host closed the game"))


## Opens the port and starts the beacon. Returns "" or why not.
func host(p_name: String, port: int = PORT) -> String:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PEERS)
	if err != OK:
		_peer = null
		return "Couldn't open port %d (%s)" % [port, error_string(err)]
	multiplayer.multiplayer_peer = _peer
	role = "host"
	player_name = p_name
	_port = port
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address(beacon_address, BEACON_PORT)
	status = "Hosting on port %d" % port
	return ""


## Connects to a host. The slot, the world and the refreshes follow (welcomed, snapshot_arrived). Returns "" or why not.
func join(address: String, port: int, p_name: String) -> String:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return "Couldn't start joining %s (%s)" % [address, error_string(err)]
	multiplayer.multiplayer_peer = _peer
	role = "joiner"
	player_name = p_name
	_address = address
	_join_t = 0.0
	status = "Connecting to %s..." % address
	return ""


## Hears hosts' beacons on this network (the join screen). Returns "" or why not.
func listen() -> String:
	if _listen != null:
		return ""
	_listen = PacketPeerUDP.new()
	var err := _listen.bind(BEACON_PORT, "0.0.0.0")
	if err != OK:
		_listen = null
		return "Couldn't listen for games (%s)" % error_string(err)
	return ""


func stop_listening() -> void:
	if _listen != null:
		_listen.close()
		_listen = null


## The world this link talks about: the host's live sim (refreshes come from it) or the joiner's copy (they go into it).
func attach(p_sim: SimWorld) -> void:
	sim = p_sim
	sync = NetSync.new(sim) if role == "host" else null
	if role == "host" and player_name != "" and not sim.players.is_empty():
		sim.players[0].name = player_name  # the host's slot carries the host's name (over its head on the other screen)


func close() -> void:
	role = ""
	stop_listening()
	if _beacon != null:
		_beacon.close()
		_beacon = null
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	sim = null
	sync = null
	peers.clear()
	local_slot = -1
	snapshot_ready = false
	status = ""
	if current == self:
		current = null


func _process(delta: float) -> void:
	if role == "host":
		_beacon_t += delta
		if _beacon != null and _beacon_t >= BEACON_EVERY:
			_beacon_t = 0.0
			_beacon.put_packet(JSON.stringify({"game": GAME_TAG, "name": player_name, "port": _port,
					"version": GameSession.version_line()}).to_utf8_buffer())
		if sim != null and sync != null and not peers.is_empty():
			_refresh_t += delta
			if _refresh_t >= 1.0 / REFRESH_HZ:
				var d := sync.refresh(_refresh_t)
				_refresh_t = 0.0
				rpc("rpc_refresh", pack(d))
				counts["refreshes_sent"] += 1
	elif role == "joiner":
		if local_slot < 0 and _join_t >= 0.0:
			_join_t += delta
			if _join_t > JOIN_TIMEOUT:
				_join_t = -1.0
				_fail("Nobody answered at %s: is the host's game running?" % _address)
		if sim != null and local_slot >= 0 and local_slot < sim.players.size():
			_state_t += delta
			if _state_t >= 1.0 / STATE_HZ:
				_state_t = 0.0
				var st := NetSync.player_state(sim, local_slot)
				rpc_id(1, "rpc_player_state", st[0], st[1], st[2], st[3])
	if _listen != null:
		while _listen.get_available_packet_count() > 0:
			var bytes := _listen.get_packet()
			var from := _listen.get_packet_ip()
			var info: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if info is Dictionary and str(info.get("game", "")) == GAME_TAG:
				var port := int(info.get("port", PORT))
				var key := "%s:%d" % [from, port]
				var fresh := not games.has(key)
				games[key] = {"name": str(info.get("name", "a game")), "address": from, "port": port,
						"version": str(info.get("version", "")), "seen": Time.get_ticks_msec()}
				counts["beacons_got"] += 1
				if fresh:
					games_changed.emit()


func _on_connected() -> void:
	status = "Connected: asking for a place..."
	rpc_id(1, "rpc_hello", player_name)


func _on_peer_left(id: int) -> void:
	if role == "host" and peers.has(id):
		var slot := int(peers[id])
		peers.erase(id)
		if sim != null and slot < sim.players.size():
			sim.add_message("%s left the game" % sim.players[slot].name, 5.0)


func _fail(why: String) -> void:
	if role == "":
		return
	status = why
	link_failed.emit(why)


## A joiner says who it is; the host gives it a slot (its old one by name, if free), the world, and tells everyone.
@rpc("any_peer", "call_remote", "reliable")
func rpc_hello(p_name: String) -> void:
	if role != "host" or sim == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var slot := _slot_for(p_name)
	peers[id] = slot
	rpc_id(id, "rpc_welcome", slot)
	rpc_id(id, "rpc_snapshot", pack(NetSync.snapshot(sim)))
	sim.add_message("%s joined the game" % p_name, 5.0)


func _slot_for(p_name: String) -> int:
	for i in range(1, sim.players.size()):
		if sim.players[i].name == p_name and not peers.values().has(i):
			return i
	var i := sim.add_player(p_name)
	var host_slot: PlayerSlot = sim.players[0]  # a newcomer arrives at the host's right hand, not on top of them
	var right := host_slot.facing.cross(Vector3.UP)
	if right.length_squared() < 1e-4:
		right = Vector3.RIGHT
	sim.players[i].pos = host_slot.pos + right.normalized() * 1.6
	sim.players[i].spawn_point = host_slot.spawn_point
	return i


@rpc("authority", "call_remote", "reliable")
func rpc_welcome(slot: int) -> void:
	local_slot = slot
	status = "In (slot %d). Loading the world..." % slot
	welcomed.emit(slot)


@rpc("authority", "call_remote", "reliable")
func rpc_snapshot(bytes: PackedByteArray) -> void:
	var d: Variant = unpack(bytes)
	if not d is Dictionary:
		_fail("The world didn't arrive whole")
		return
	var why := SaveGame.write_dict(d, JOIN_FILE)
	if why != "":
		_fail(why)
		return
	snapshot_ready = true
	status = "World received"
	snapshot_arrived.emit()


@rpc("authority", "call_remote", "reliable")  # a refresh is a few KB: over ENet's MTU, so reliable (fragmented) rather than lost
func rpc_refresh(bytes: PackedByteArray) -> void:
	if role != "joiner" or sim == null:
		return
	var d: Variant = unpack(bytes)
	if d is Dictionary:
		NetSync.apply_refresh(sim, d, local_slot)
		counts["refreshes_got"] += 1


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_player_state(pos: Vector3, facing: Vector3, lit: bool, sneaking: bool) -> void:
	if role != "host" or sim == null:
		return
	var slot := int(peers.get(multiplayer.get_remote_sender_id(), -1))
	if slot > 0:
		NetSync.apply_player_state(sim, slot, pos, facing, lit, sneaking)
		counts["states_got"] += 1


## Dictionaries go as compressed Variant bytes (no objects in them; DEFLATE, which decompresses without a size).
static func pack(d: Dictionary) -> PackedByteArray:
	return var_to_bytes(d).compress(FileAccess.COMPRESSION_DEFLATE)


static func unpack(bytes: PackedByteArray) -> Variant:
	var raw := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	return bytes_to_var(raw)
