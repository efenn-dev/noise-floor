class_name ZombieHitboxes
extends RefCounted
## V33 (Emmitt: "better hitboxes"): a zombie's hit zones ride its animated bones, so a shot lands where it looks
## like it should: the head of a crawler on the floor, a runner's swinging arm, a gap between arm and body (a
## miss). Each zone is a box on its own bone (BoneAttachment3D + Area3D on Layers.HITBOX), fitted to the body
## mesh's own vertices for that bone, once per body variant. The movement capsule stays for walking into
## things; past RANGE metres from the player the zones switch off and the capsule's height lines decide.

## Bone -> the zone a hit on it counts as (the five bodies share this 17-bone skeleton).
const ZONES := {
	"Head": "head", "Neck": "torso", "Chest": "torso", "Spine": "torso", "Hips": "torso",
	"UpperArm.L": "arm", "LowerArm.L": "arm", "Hand.L": "arm",
	"UpperArm.R": "arm", "LowerArm.R": "arm", "Hand.R": "arm",
	"UpperLeg.L": "leg", "LowerLeg.L": "leg", "Foot.L": "leg",
	"UpperLeg.R": "leg", "LowerLeg.R": "leg", "Foot.R": "leg",
}
const RANGE := 45.0  # metres from the player within which a zombie's bone zones are on
const LOW := 0.04    # the box spans these fractions of its bone's vertices on each axis (drops stray ones)
const HIGH := 0.96
const MIN_VERTS := 12
const DEBUG_COLORS := {"head": Color(1, 0.15, 0.1, 0.35), "torso": Color(1, 0.8, 0.1, 0.25),
		"arm": Color(0.2, 0.6, 1, 0.3), "leg": Color(0.3, 1, 0.3, 0.3)}

static var show := false  # --hitboxes: draw the zones
static var _fits: Dictionary = {}  # body variant -> {bone: [centre, size]} in bone space


## The box for each zone bone of `model` (a zombie body scene), in that bone's space: [centre, size].
## Measured from the skinned mesh at bind (each vertex goes to the bone that weighs most on it); cached by `key`.
static func fit(model: Node3D, key: String) -> Dictionary:
	if _fits.has(key):
		return _fits[key]
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var clouds := {}  # bone name -> Array of Vector3 in bone space
	if sk != null:
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or mi.skin == null:
				continue
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				if verts.is_empty() or bones.is_empty():
					continue
				var per: int = bones.size() / verts.size()
				for i in verts.size():
					var best := -1
					var best_w := -1.0
					for k in per:
						if weights[i * per + k] > best_w:
							best_w = weights[i * per + k]
							best = bones[i * per + k]
					if best < 0 or best >= mi.skin.get_bind_count():
						continue
					var bone_name := String(mi.skin.get_bind_name(best))
					if bone_name == "":
						bone_name = sk.get_bone_name(mi.skin.get_bind_bone(best))
					if not ZONES.has(bone_name):
						continue
					if not clouds.has(bone_name):
						clouds[bone_name] = []
					(clouds[bone_name] as Array).append(mi.skin.get_bind_pose(best) * verts[i])
	var out := {}
	for bone_name: String in clouds:
		var pts: Array = clouds[bone_name]
		if pts.size() < MIN_VERTS:
			continue
		var lo := Vector3.ZERO
		var hi := Vector3.ZERO
		for axis in 3:
			var values: Array = pts.map(func(p: Vector3) -> float: return p[axis])
			values.sort()
			lo[axis] = values[int(LOW * (values.size() - 1))]
			hi[axis] = values[int(HIGH * (values.size() - 1))]
		out[bone_name] = [(lo + hi) / 2.0, (hi - lo).max(Vector3.ONE * 0.04)]
	_fits[key] = out
	return out


## Puts the zones on `model`'s skeleton for zombie `zombie_id`. Returns their collision shapes (to switch on/off).
static func build(model: Node3D, fits: Dictionary, zombie_id: int) -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return shapes
	for bone_name: String in fits:
		if sk.find_bone(bone_name) < 0:
			continue
		var attach := BoneAttachment3D.new()
		attach.name = "Hit_" + bone_name.replace(".", "_")
		attach.bone_name = bone_name
		sk.add_child(attach)
		var area := Area3D.new()
		area.collision_layer = Layers.HITBOX
		area.collision_mask = 0
		area.monitoring = false
		area.set_meta("zombie_id", zombie_id)
		area.set_meta("zone", ZONES[bone_name])
		attach.add_child(area)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = fits[bone_name][1]
		cs.shape = box
		cs.position = fits[bone_name][0]
		area.add_child(cs)
		shapes.append(cs)
		if show:
			var mesh := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = box.size
			mesh.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.no_depth_test = true
			mat.albedo_color = DEBUG_COLORS[ZONES[bone_name]]
			mesh.material_override = mat
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cs.add_child(mesh)
	return shapes


## The first thing a ray from `from` to `to` meets, with zombies seen through their bone zones where those are
## on. Returns {} for nothing; otherwise the ray result plus "zombie_id" (-1: not a zombie) and "zone".
## `generous` (melee): a swing that meets a zombie's body but slips between its zones still hits it, in the zone
## at that height, so melee never misses a body it touches; a gun's round in that gap flies on (a miss).
static func cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID],
		generous: bool = false) -> Dictionary:
	var skip: Array[RID] = exclude.duplicate()
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.BUILT | Layers.ZOMBIE | Layers.HITBOX, skip)
	query.collide_with_areas = true
	var body_hit := {}  # the first zombie body (capsule) met, in case the zones are slipped past
	for i in 8:
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit["collider"] == null:
			break
		var col: Object = hit["collider"]
		if col is Area3D and (col as Area3D).has_meta("zone"):
			var id := int(col.get_meta("zombie_id"))
			if generous and not body_hit.is_empty() and id != int(body_hit["zombie_id"]):
				return body_hit  # melee stops at the first body it touched
			hit["zombie_id"] = id
			hit["zone"] = str(col.get_meta("zone"))
			return hit
		if col is Area3D:  # some other area: look past it
			skip.append((col as Area3D).get_rid())
			query.exclude = skip
			continue
		var body := col as ZombieBody
		if body != null and body.brain != null:
			if body.hitboxes_on():
				if body_hit.is_empty():
					body_hit = hit.duplicate()
					body_hit["zombie_id"] = body.brain.id
					body_hit["zone"] = body.zone_at(hit["position"].y, hit["position"])
				elif generous:
					return body_hit
				skip.append(body.get_rid())
				query.exclude = skip
				continue
			if generous and not body_hit.is_empty():
				return body_hit
			hit["zombie_id"] = body.brain.id
			hit["zone"] = body.zone_at(hit["position"].y, hit["position"])
			return hit
		if generous and not body_hit.is_empty():
			return body_hit
		hit["zombie_id"] = -1
		hit["zone"] = ""
		return hit
	return body_hit if generous else {}
