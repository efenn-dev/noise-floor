class_name PeerView
extends Node3D
## Co-op B: the other players, drawn where the sim says they are (SimWorld.players, all but `local`): a capsule in a
## friendly blue with a nose for which way they look and their name over their head, eased toward each refresh.
## Hidden while that player is dead. A survivor body comes in Phase D. No rules live here.

const HEIGHT := 1.8
const RADIUS := 0.35
const EASE := 12.0
const COLOR := Color(0.3, 0.55, 0.95)

var sim: SimWorld
var bodies: Dictionary = {}  # slot -> Node3D


func _init(p_sim: SimWorld) -> void:
	sim = p_sim
	name = "PeerView"


func _process(delta: float) -> void:
	if sim == null:
		return
	for i in sim.players.size():
		if i == sim.local:
			continue
		var s: PlayerSlot = sim.players[i]
		var body: Node3D = bodies.get(i)
		if body == null:
			body = _make(s.name)
			body.position = s.pos
			bodies[i] = body
		body.visible = not s.stats.dead
		var k := clampf(EASE * delta, 0.0, 1.0)
		body.position = body.position.lerp(s.pos, k) if body.position.distance_to(s.pos) < 8.0 else s.pos
		var f := Vector3(s.facing.x, 0, s.facing.z)
		if f.length_squared() > 1e-4:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(-f.x, -f.z), k)
	for i: int in bodies.keys():
		if i >= sim.players.size() or i == sim.local:
			bodies[i].queue_free()
			bodies.erase(i)


func _make(p_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Peer_" + p_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	mesh.mesh = cap
	mesh.position.y = HEIGHT / 2.0
	mesh.material_override = mat
	root.add_child(mesh)
	var nose := MeshInstance3D.new()  # which way they look
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.3)
	nose.mesh = box
	nose.position = Vector3(0, HEIGHT - 0.3, -RADIUS - 0.1)
	nose.material_override = mat
	root.add_child(nose)
	var tag := Label3D.new()
	tag.text = p_name
	tag.font_size = 48
	tag.pixel_size = 0.005
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.outline_size = 10
	tag.position.y = HEIGHT + 0.35
	root.add_child(tag)
	add_child(root)
	return root
