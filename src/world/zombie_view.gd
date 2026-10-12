class_name ZombieView
extends Node3D
## Keeps one ZombieBody per zombie in the horde: adds bodies for new zombies, frees cleared corpses.

var sim: SimWorld
var player: Node3D
var _bodies: Dictionary = {}  # id -> ZombieBody


func setup(p_sim: SimWorld, p_player: Node3D) -> void:
	sim = p_sim
	player = p_player
	sync()


func body_for(id: int) -> ZombieBody:
	return _bodies.get(id)


func _physics_process(_delta: float) -> void:
	sync()


func sync() -> void:
	if sim == null:
		return
	for id: int in sim.horde.zombies:
		if not _bodies.has(id):
			var body := ZombieBody.new()
			body.setup(sim.horde.zombies[id], player)
			add_child(body)
			_bodies[id] = body
	for id: int in _bodies.keys():
		if not sim.horde.zombies.has(id):
			_bodies[id].queue_free()
			_bodies.erase(id)
