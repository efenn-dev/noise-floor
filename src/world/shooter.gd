class_name Shooter
extends Node3D
## M14: the gun in your hands. Left-click (outside build mode, gun in hand: Q) fires: the sim uses a round
## and makes the noise (SimWorld.fire), then this raycasts from the camera inside a cone as wide as the
## sim's spread (Gunplay.spread_deg: accuracy, ADS, scope, recoil, Firearms), and if it meets a zombie that's a hit
## (SimWorld.shoot_zombie; P2: the ray is the only roll). V15: right click aims every gun. A hit above the shoulders is a headshot. Shows the gun model
## held in view, a brief muzzle light and a recoil kick on the camera. Sounds come from SoundView, which plays
## the shot's noise event.

const MODELS := {
	"pistol": "res://assets/models/pistol.glb",
	"hunting_rifle": "res://assets/models/hunting_rifle.glb",
	"shotgun": "res://assets/models/shotgun.glb",
	"crossbow": "res://assets/models/crossbow.glb",
}
const PART_MODELS := {
	"oil_filter_suppressor": "res://assets/models/part_oil_filter_suppressor.glb",
	"machined_suppressor": "res://assets/models/part_machined_suppressor.glb",
	"extended_mag": "res://assets/models/part_extended_mag.glb",
	"scope": "res://assets/models/part_scope.glb",
	"padded_stock": "res://assets/models/part_padded_stock.glb",
	"choke": "res://assets/models/part_choke.glb",
}
## Handheld models are authored with these stable names. Gun Rubber deliberately reuses the fine polymer
## grain (there is no separate rubber photo). V2 review: the models' own colours are near black, which hid
## the texture, so each material's colour is its photo times `tint` (gun steel reads as dark grey steel).
## Any new material name must be mapped or explicitly listed here so test_textured_looks.gd catches it.
const GUN_LOOKS := {
	"materials": {
		"Gun Metal": {"texture": "gun_metal", "tile_m": 0.15, "tint": Color(0.8, 0.8, 0.84), "metallic": 0.5, "roughness": 0.5},
		"Gun Wood": {"texture": "gun_wood", "tile_m": 0.15, "tint": Color(1.0, 0.95, 0.9)},
		"Gun Polymer": {"texture": "gun_polymer", "tile_m": 0.15, "tint": Color(0.85, 0.85, 0.85)},
		"Gun Rubber": {"texture": "gun_polymer", "tile_m": 0.15, "tint": Color(0.5, 0.5, 0.5)},
		"Gun Glass": {"texture": "gun_metal", "tile_m": 0.08, "tint": Color(0.18, 0.55, 0.62), "metallic": 0.1, "roughness": 0.15},
	},
	"untextured": [],
}
## Where each gun sits in view (camera space): resting at the lower right, pointing ahead.
const HOLD := {
	"pistol": Vector3(0.2, -0.2, -0.42),
	"hunting_rifle": Vector3(0.18, -0.2, -0.5),
	"shotgun": Vector3(0.19, -0.21, -0.53),
	"crossbow": Vector3(0.18, -0.23, -0.56),
}
## V23: mount points measured on the exported, centred GLBs (metres in gun-local Godot space). The source
## bounds were pistol x +/-0.0167, y -0.080..0.0795, z -0.1075..0.1075 and rifle x +/-0.0431,
## y -0.100..0.0663, z -0.5403..0.5403. Mount nodes stay exactly on these points; centred part meshes use
## PART_OFFSETS to put their attaching face on the mount.
const ATTACHMENT_ANCHORS := {
	"pistol": {
		"muzzle": Vector3(0.0, 0.057, -0.1075),
		"magazine": Vector3(0.0, -0.080, 0.073),
		"sight": Vector3(0.0, 0.0795, -0.005),
	},
	"hunting_rifle": {
		"muzzle": Vector3(-0.015, 0.027, -0.5403),
		"magazine": Vector3(-0.015, -0.034, 0.060),
		"sight": Vector3(-0.015, 0.0663, -0.010),
		"stock": Vector3(-0.015, -0.024, 0.5403),
	},
	# Exported bounds: x +/-0.035, y -0.090..0.090, z -0.620..0.620.
	"shotgun": {
		"muzzle": Vector3(0.0, 0.072, -0.620),
		"stock": Vector3(0.0, -0.023, 0.606),
	},
	# Exported bounds: x +/-0.370, y -0.095..0.095, z -0.585..0.585.
	"crossbow": {
		"sight": Vector3(0.0, 0.085, -0.050),
	},
}
const PART_OFFSETS := {
	"oil_filter_suppressor": Vector3(0.0, 0.0, -0.1125),
	"machined_suppressor": Vector3(0.0, 0.0, -0.104),
	"extended_mag": Vector3(0.0, -0.087, 0.0),
	"scope": Vector3(0.0, 0.045, 0.0),
	"padded_stock": Vector3(0.0, 0.0, 0.030),
	"choke": Vector3(0.0, 0.0, -0.045),
}
## V15: the sight tops measured from the exported .glb vertices (the models are centred on their bounding
## box, so the .py coordinates don't apply; the rifle's bore runs 15 mm left of centre). ADS_POSES puts the
## rear-to-front line through camera-space x/y zero.
const SIGHT_POINTS := {
	"pistol": {"rear": Vector3(0, 0.0785, 0.084), "front": Vector3(0, 0.0785, -0.076)},
	"hunting_rifle": {"rear": Vector3(-0.015, 0.0635, -0.07), "front": Vector3(-0.015, 0.0635, -0.5)},
	"shotgun": {"rear": Vector3(0.0, 0.089, 0.181), "front": Vector3(0.0, 0.089, -0.564)},
	"crossbow": {"rear": Vector3(0.0, 0.085, 0.145), "front": Vector3(0.0, 0.085, -0.420)},
}
const ADS_POSES := {
	"pistol": [Vector3(0, -0.0785, -0.42), Vector3.ZERO],
	"hunting_rifle": [Vector3(0.015, -0.0635, -0.62), Vector3.ZERO],  # further out, so the stock's comb doesn't fill the view
	"shotgun": [Vector3(0.0, -0.089, -0.66), Vector3.ZERO],
	"crossbow": [Vector3(0.0, -0.085, -0.65), Vector3.ZERO],
}
const SCOPE_SIGHT_POINTS := {
	"pistol": {"rear": Vector3(0.0, 0.1245, 0.115), "front": Vector3(0.0, 0.1245, -0.125)},
	"hunting_rifle": {"rear": Vector3(-0.015, 0.1113, 0.110), "front": Vector3(-0.015, 0.1113, -0.130)},
	"crossbow": {"rear": Vector3(0.0, 0.130, 0.110), "front": Vector3(0.0, 0.130, -0.130)},
}
const SCOPE_ADS_POSES := {
	"pistol": [Vector3(0.0, -0.1245, -0.42), Vector3.ZERO],
	"hunting_rifle": [Vector3(0.015, -0.1113, -0.62), Vector3.ZERO],
	"crossbow": [Vector3(0.0, -0.130, -0.65), Vector3.ZERO],
}
const FLASH_TIME := 0.06
## V33: what a gun hit says, by the zone it landed in.
const ZONE_WORDS := {"head": "Headshot!", "torso": "Hit", "arm": "Arm hit", "leg": "Leg hit"}
const KICK_DEG := {"pistol": 2.0, "hunting_rifle": 5.0, "shotgun": 9.0, "crossbow": 0.8}
const KICK_BACK := 12.0  # how fast the kick comes back down, per second
const AIM_FOV := 35.0  # P2/V15: right click (hold) with a scope aims at this field of view
## V16: on iron sights the gun skips what's closer to your eye than this, so the stock under your cheek doesn't
## fill the bottom of the view (the receiver, sights and both hands are farther out). Q6: only the gun's own
## surfaces fade out (distance fade, per pixel); it used to be the camera's near plane, which also sliced the
## right glove and sleeve into a hollow horn shape.
const ADS_NEAR := {"hunting_rifle": 0.34, "shotgun": 0.35, "crossbow": 0.34}
const ADS_FADE_BAND := 0.03  # the last few cm before ADS_NEAR dither in, so the cut edge isn't a hard line
const IRON_FOV_MULT := 0.85  # V15: iron sights narrow the normal field of view by 15%
const ADS_SWAY_MULT := 0.12
const ZOOM_SPEED := 400.0  # degrees of field of view a second, zooming in or out
const INSPECT_TIME := 2.4
## V13: this is a measured-looking guess. Tune it to the rig's actual HoldMag palm centre once the arm
## asset lands; the prop remains a child of Hand_L so every wrist correction carries it with the hand.
const MAG_IN_HAND := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-0.023, 0.0, -0.04))  # the rig's measured HoldMag centre (left arm); the box is long along +Y, the held magazine along +Z

## [time, gun position offset, gun rotation degrees, left-hand position in gun space,
## left-hand rotation degrees, rig pose, magazine state]. State changes at its key; transforms smoothstep.
const PISTOL_RELOAD_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Grip", "in_gun"],
	[0.10, Vector3(0.055, 0.05, 0.03), Vector3(-10, 8, 16), Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Open", "in_gun"],
	[0.18, Vector3(0.08, 0.08, 0.045), Vector3(-16, 12, 24), Vector3(-0.08, -0.15, 0.08), Vector3(-20, -15, -8), "Open", "dropping"],
	[0.30, Vector3(0.08, 0.08, 0.045), Vector3(-16, 12, 24), Vector3(-0.16, -0.48, 0.12), Vector3(-30, 5, -12), "Open", "none"],
	[0.42, Vector3(0.08, 0.08, 0.045), Vector3(-16, 12, 24), Vector3(-0.16, -0.42, 0.08), Vector3(-8, -12, 5), "HoldMag", "in_hand"],
	[0.56, Vector3(0.07, 0.06, 0.03), Vector3(-14, 10, 20), Vector3(-0.045, -0.12, 0.07), Vector3(-12, -22, 2), "HoldMag", "in_hand"],
	[0.62, Vector3(0.07, 0.09, 0.015), Vector3(-18, 10, 20), Vector3(-0.03, -0.035, 0.065), Vector3(-15, -30, 0), "HoldMag", "in_gun"],
	[0.74, Vector3(0.055, 0.06, 0.02), Vector3(-12, 7, 16), Vector3(-0.035, 0.015, -0.03), Vector3(72, -10, -18), "Flat", "in_gun"],
	[0.82, Vector3(0.055, 0.06, 0.10), Vector3(-15, 7, 16), Vector3(-0.035, 0.015, -0.03), Vector3(72, -10, -18), "Flat", "in_gun"],
	[0.93, Vector3(0.03, 0.03, 0.02), Vector3(-6, 3, 8), Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Grip", "in_gun"],
	[1.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Grip", "in_gun"],
]
const RIFLE_RELOAD_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Grip", "in_gun"],
	[0.12, Vector3(0.03, 0.06, 0.02), Vector3(-4, 4, 10), Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Open", "in_gun"],
	[0.24, Vector3(0.04, 0.075, 0.03), Vector3(-5, 5, 12), Vector3(-0.15, -0.48, -0.05), Vector3(30, 5, -15), "Open", "in_gun"],
	[0.34, Vector3(0.04, 0.075, 0.03), Vector3(-5, 5, 12), Vector3(-0.14, -0.38, -0.05), Vector3(15, 10, -8), "Pinch", "in_gun"],
	[0.42, Vector3(0.04, 0.075, 0.03), Vector3(-5, 5, 12), Vector3(-0.04, 0.015, 0.02), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.47, Vector3(0.04, 0.09, 0.03), Vector3(-7, 5, 12), Vector3(-0.03, 0.035, 0.015), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.51, Vector3(0.04, 0.065, 0.035), Vector3(-4, 5, 12), Vector3(-0.05, 0.005, 0.04), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.56, Vector3(0.04, 0.09, 0.03), Vector3(-7, 5, 12), Vector3(-0.03, 0.035, 0.015), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.60, Vector3(0.04, 0.065, 0.035), Vector3(-4, 5, 12), Vector3(-0.05, 0.005, 0.04), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.65, Vector3(0.04, 0.09, 0.03), Vector3(-7, 5, 12), Vector3(-0.03, 0.035, 0.015), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.72, Vector3(0.04, 0.065, 0.09), Vector3(-5, 5, 12), Vector3(0.035, 0.02, 0.11), Vector3(35, -15, -25), "Pinch", "in_gun"],
	[0.80, Vector3(0.04, 0.065, -0.03), Vector3(-5, 5, 12), Vector3(0.035, 0.02, 0.11), Vector3(35, -15, -25), "Pinch", "in_gun"],
	[0.90, Vector3(0.02, 0.03, 0.0), Vector3(-2, 2, 5), Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Grip", "in_gun"],
	[1.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Grip", "in_gun"],
]
## One shell step. Gunplay repeats this short sequence until full and a trigger pull can interrupt between steps.
const SHOTGUN_RELOAD_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, -0.015, -0.23), Vector3(90, 0, 0), "Grip", "in_gun"],
	[0.25, Vector3(0.03, 0.05, 0.03), Vector3(-5, 5, 10), Vector3(-0.15, -0.30, -0.04), Vector3(15, 0, -20), "Pinch", "in_gun"],
	[0.62, Vector3(0.03, 0.07, 0.03), Vector3(-7, 5, 11), Vector3(-0.02, -0.055, 0.10), Vector3(25, -15, -20), "Pinch", "in_gun"],
	[0.82, Vector3(0.02, 0.035, 0.01), Vector3(-3, 2, 5), Vector3(0.0, -0.015, -0.23), Vector3(90, 0, 0), "Grip", "in_gun"],
	[1.0, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, -0.015, -0.23), Vector3(90, 0, 0), "Grip", "in_gun"],
]
const CROSSBOW_RELOAD_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -0.18), Vector3(90, 0, 0), "Grip", "in_gun"],
	[0.18, Vector3(0.02, -0.09, 0.07), Vector3(-18, 5, 8), Vector3(-0.12, -0.24, 0.15), Vector3(20, 0, -20), "Grip", "in_gun"],
	[0.62, Vector3(0.02, -0.15, 0.09), Vector3(-25, 4, 8), Vector3(-0.02, -0.02, 0.22), Vector3(80, 0, 0), "Pinch", "in_gun"],
	[0.84, Vector3(0.02, 0.03, 0.02), Vector3(-5, 2, 4), Vector3(0.0, 0.03, -0.34), Vector3(25, 0, -10), "Pinch", "in_gun"],
	[1.0, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -0.18), Vector3(90, 0, 0), "Grip", "in_gun"],
]

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []
var last_message := ""
## Tests set this so a shot goes straight down the middle of the cone.
var no_spread := false
## --aim (screenshots) and tests: hold the scope zoom without a right click.
var hold_aim := false
var sprinting := false  # V15: the player controller sets this from the sprint request; sprint cancels ADS
var hold_reload_at := -1.0  # V13: --reload-at freezes the visible choreography without touching the sim
var hold_inspect_at := -1.0  # V13: --inspect-at does the same for inspection
var base_fov := 75.0
var base_near := 0.05
var _aim_held := false
var _aim_weight := 0.0

var _rng := RandomNumberGenerator.new()
var _models: Dictionary = {}  # base -> Node3D
var _part_nodes: Dictionary = {}  # gun base -> part base -> the visible model below its measured mount
var feel: ViewFeel  # V3: carries the kick to the camera, shake, hit marker, impact puffs (null when built alone)
var _flash: OmniLight3D
var _flash_time := 0.0
var _kick := 0.0  # radians the camera is tipped up right now
var _message_time := 0.0
var _last_reloading := 0.0
var _reload_total := 0.0
var _reload_sound_progress := -1.0  # V16: last choreography progress heard; -1 means stopped/cancelled
var _reload_sound_gun := ""
var _inspect_elapsed := -1.0
var _inspect_uid := -1
var _mag_in_hand: Dictionary = {}  # gun base -> the prop parented to Hand_L
var _fade_materials: Dictionary = {}  # Q6: gun base -> its own surfaces' distance-faded materials (ADS_NEAR)
var _drop_mag: MeshInstance3D
var _last_cooldown := 0.0

## Guns with the same authored material share one object-space material across every place they are shown.
static var _material_cache: Dictionary = {}


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	exclude = p_exclude
	base_fov = camera.fov
	base_near = camera.near
	_rng.randomize()
	for base: String in MODELS:
		var node: Node3D
		if ResourceLoader.exists(MODELS[base]):
			node = (load(MODELS[base]) as PackedScene).instantiate() as Node3D
		else:  # placeholder until the model exists
			var m := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.05, 0.12, 0.25 if base == "pistol" else 0.9)
			m.mesh = box
			node = m
		node.name = "Gun_" + base
		node.position = HOLD[base]
		node.visible = false
		Hands.attach(node, base, Hands.GUNS)  # V12: hands on the grip and under the barrel
		_attach_part_models(node, base)
		var left := node.get_node_or_null("Hand_L") as Node3D
		if base == "pistol" and left != null:
			var mag := _make_magazine()
			mag.name = "MagazineInHand"
			mag.transform = MAG_IN_HAND
			mag.visible = false
			left.add_child(mag)
			_mag_in_hand[base] = mag
		apply_textured_materials(node)
		if ADS_NEAR.has(base):
			_fade_materials[base] = _fading_gun_materials(node)
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		camera.add_child(node)
		_models[base] = node
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.45)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_flash.position = Vector3(0.2, -0.15, -0.9)
	camera.add_child(_flash)


## Q6: gives the gun's own surfaces (its parts too, not the hands) their own copies of their materials with a
## per-pixel distance fade, all visible until iron-sight aiming raises the fade distance (see ADS_NEAR).
static func _fading_gun_materials(gun_node: Node3D) -> Array[BaseMaterial3D]:
	var out: Array[BaseMaterial3D] = []
	var copies := {}
	var hands: Array[Node] = []
	for hand_name: String in ["Hand_R", "Hand_L"]:
		if gun_node.has_node(hand_name):
			hands.append(gun_node.get_node(hand_name))
	for child: Node in gun_node.find_children("*", "MeshInstance3D", true, false) + ([gun_node] if gun_node is MeshInstance3D else []):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or hands.any(func(h: Node) -> bool: return h.is_ancestor_of(mesh)):
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_surface_override_material(surface)
			if source == null:
				source = mesh.mesh.surface_get_material(surface)
			if not source is BaseMaterial3D:
				continue
			if not copies.has(source):
				var copy := source.duplicate() as BaseMaterial3D
				copy.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				copy.distance_fade_min_distance = 0.0
				copy.distance_fade_max_distance = 0.001
				copies[source] = copy
				out.append(copy)
			mesh.set_surface_override_material(surface, copies[source])
	return out


func _attach_part_models(gun_node: Node3D, gun_id: String) -> void:
	_part_nodes[gun_id] = {}
	var slots: Array = sim.data.guns["guns"][gun_id]["part_slots"]
	for part_id: String in PART_MODELS:
		var part_def: Dictionary = sim.data.guns["parts"][part_id]
		var slot := str(part_def["slot"])
		if not slot in slots or gun_id not in part_def.get("guns", []) \
				or not ResourceLoader.exists(PART_MODELS[part_id]):
			continue
		var mount := Node3D.new()
		mount.name = "AttachmentMount_" + part_id
		mount.position = ATTACHMENT_ANCHORS[gun_id][slot]
		gun_node.add_child(mount)
		var model := (load(PART_MODELS[part_id]) as PackedScene).instantiate() as Node3D
		model.name = "Attachment_" + part_id
		model.position = PART_OFFSETS[part_id]
		model.visible = false
		mount.add_child(model)
		apply_textured_materials(model)
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_part_nodes[gun_id][part_id] = model


func _sync_part_models(gun_id: String) -> void:
	var fitted := {}
	for part: Dictionary in sim.gear.gun().get("parts", {}).values():
		fitted[part["base"]] = true
	for part_id: String in _part_nodes.get(gun_id, {}):
		(_part_nodes[gun_id][part_id] as Node3D).visible = fitted.has(part_id)


## Apply the named gun surfaces to any instance (hands now; reusable if a 3-D workbench preview is added).
## Object-space triplanar keeps the grain attached to the moving weapon.
static func apply_textured_materials(node: Node3D) -> void:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for child: Node in meshes:
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or not GUN_LOOKS["materials"].has(source.resource_name):
				continue
			var mapping: Dictionary = GUN_LOOKS["materials"][source.resource_name]
			mesh.set_surface_override_material(surface, _gun_material(source, String(mapping["texture"]),
					float(mapping["tile_m"]), mapping.get("tint", Color.WHITE), mapping))


## V2 review: a fully metallic surface takes its colour from reflections, and a dim sky left the pistol black,
## so a mapping may set its own "metallic" and "roughness" (gun steel is satin, not mirror).
static func _gun_material(source: StandardMaterial3D, texture: String, tile_m: float, tint: Color = Color.WHITE,
		mapping: Dictionary = {}) -> StandardMaterial3D:
	var key := "%s|%s|%.3f|%s|%.3f|%.3f" % [source.resource_name, texture, tile_m,
			tint.to_html(), source.metallic, source.roughness]
	if not _material_cache.has(key):
		var mat := source.duplicate() as StandardMaterial3D
		mat.resource_name = source.resource_name
		mat.albedo_color = tint
		mat.metallic = float(mapping.get("metallic", source.metallic))
		mat.roughness = float(mapping.get("roughness", source.roughness))
		mat.albedo_texture = load("res://assets/textures/%s_albedo.jpg" % texture)
		mat.normal_enabled = true
		mat.normal_texture = load("res://assets/textures/%s_normal.jpg" % texture)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = false
		mat.uv1_scale = Vector3.ONE / tile_m
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_material_cache[key] = mat
	return _material_cache[key]


## V13: pure reload choreography. Position/rotation are offsets from HOLD; the left-hand transform is
## absolute in the gun model's space. Unknown future guns retain the old centred dip.
static func reload_pose(gun_id: String, p: float) -> Dictionary:
	if gun_id == "pistol":
		return _sample_hand_pose(PISTOL_RELOAD_KEYS, p)
	if gun_id == "hunting_rifle":
		return _sample_hand_pose(RIFLE_RELOAD_KEYS, p)
	if gun_id == "shotgun":
		return _sample_hand_pose(SHOTGUN_RELOAD_KEYS, p)
	if gun_id == "crossbow":
		return _sample_hand_pose(CROSSBOW_RELOAD_KEYS, p)
	var rest := _left_rest(gun_id)
	var keys := [
		[0.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
		[0.5, Vector3(0.0, -0.12, 0.0), Vector3(-25, 0, 20), rest[0], rest[1], "Grip", "in_gun"],
		[1.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
	]
	return _sample_hand_pose(keys, p)


## V16: mechanical sounds land on the V13 choreography keys, independent of the sim's reload noise.
static func reload_sounds(gun_id: String) -> Array:
	if gun_id == "pistol":
		return [[0.18, "mag_out"], [0.62, "mag_in"], [0.74, "slide_rack"]]
	if gun_id == "hunting_rifle":
		return [[0.12, "bolt_open"], [0.47, "round_in"], [0.56, "round_in"],
				[0.65, "round_in"], [0.72, "bolt_close"]]
	if gun_id == "shotgun":
		return [[0.62, "shell_in"]]
	if gun_id == "crossbow":
		return [[0.18, "draw_string"], [0.84, "bolt_in"]]
	return []


## The pump is included in the firing cooldown. The moving fore-hand and the small whole-gun translation
## make the action readable even though the low-poly export is a single optimized mesh.
static func pump_pose(progress: float) -> Dictionary:
	var p := clampf(progress, 0.0, 1.0)
	var travel := 0.0
	if p < 0.42:
		travel = smoothstep(0.0, 1.0, p / 0.42) * 0.105
	else:
		travel = (1.0 - smoothstep(0.0, 1.0, (p - 0.42) / 0.48)) * 0.105
	return {"gun_offset": Vector3(0.0, 0.0, travel * 0.18),
			"hand_position": Vector3(0.0, -0.015, -0.23 + travel)}


static func passed_pump_sounds(previous_progress: float, current_progress: float) -> Array[String]:
	var sounds: Array[String] = []
	if previous_progress < 0.28 and current_progress >= 0.28:
		sounds.append("pump_back")
	if previous_progress < 0.67 and current_progress >= 0.67:
		sounds.append("pump_forward")
	return sounds


## Every cue crossed by a forward progress step, in order. The open lower bound prevents repeats.
static func passed_reload_sounds(gun_id: String, previous_progress: float, current_progress: float) -> Array:
	var passed: Array = []
	if current_progress <= previous_progress:
		return passed
	for cue: Array in reload_sounds(gun_id):
		var at := float(cue[0])
		if at > previous_progress and at <= current_progress:
			passed.append(cue)
	return passed


## V13: pure two-sided inspection. A pistol's left hand lets go; a rifle stays held between both hands.
static func inspect_pose(gun_id: String, p: float) -> Dictionary:
	var rest := _left_rest(gun_id)
	var keys: Array
	if gun_id == "pistol":
		keys = [
			[0.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
			[0.16, Vector3(-0.01, 0.05, 0.10), Vector3(-6, 22, -5), Vector3(-0.17, -0.24, 0.05), Vector3(12, -12, -20), "Open", "in_gun"],
			[0.38, Vector3(-0.04, 0.04, 0.14), Vector3(-8, 48, -10), Vector3(-0.20, -0.28, 0.08), Vector3(15, -5, -25), "Open", "in_gun"],
			[0.58, Vector3(0.02, 0.04, 0.13), Vector3(-5, -40, 35), Vector3(-0.18, -0.27, 0.10), Vector3(8, 12, -18), "Open", "in_gun"],
			[0.78, Vector3(0.01, 0.06, 0.10), Vector3(-32, 5, 15), Vector3(-0.14, -0.22, 0.08), Vector3(4, -8, -12), "Open", "in_gun"],
			[1.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
		]
	else:
		keys = [
			[0.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
			[0.22, Vector3(-0.035, 0.045, 0.10), Vector3(-5, 28, 8), rest[0], rest[1], "Grip", "in_gun"],
			[0.50, Vector3(0.025, 0.05, 0.12), Vector3(-3, -30, -13), rest[0], rest[1], "Grip", "in_gun"],
			[0.76, Vector3(0.0, 0.055, 0.08), Vector3(-18, 0, 5), rest[0], rest[1], "Grip", "in_gun"],
			[1.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
		]
	return _sample_hand_pose(keys, p)


static func _sample_hand_pose(keys: Array, p: float) -> Dictionary:
	var tt := clampf(p, 0.0, 1.0)
	var state: Array = keys[0]
	for key: Array in keys:
		if float(key[0]) <= tt:
			state = key
	var a: Array = keys[0]
	var b: Array = keys[keys.size() - 1]
	for i in range(1, keys.size()):
		b = keys[i]
		if tt <= float(b[0]):
			a = keys[i - 1]
			break
	var span := maxf(0.0001, float(b[0]) - float(a[0]))
	var u := smoothstep(0.0, 1.0, clampf((tt - float(a[0])) / span, 0.0, 1.0))
	var rotation_deg: Vector3 = (a[2] as Vector3).lerp(b[2], u)
	var left_rotation_deg: Vector3 = (a[4] as Vector3).lerp(b[4], u)
	return {
		"position": (a[1] as Vector3).lerp(b[1], u),
		"rotation": _radians(rotation_deg),
		"left_position": (a[3] as Vector3).lerp(b[3], u),
		"left_rotation": _radians(left_rotation_deg),
		"left_pose": String(state[5]),
		"magazine": String(state[6]),
		"magazine_state": String(state[6]),
	}


static func _left_rest(gun_id: String) -> Array:
	var cfg: Dictionary = Hands.GUNS.get(gun_id, {})
	if not cfg.has("left"):
		return [Vector3.ZERO, Vector3.ZERO]
	var pr: Array = cfg["left"]
	return [pr[0], pr[1]]


static func _radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))


static func _rest_pose(gun_id: String) -> Dictionary:
	var rest := _left_rest(gun_id)
	return {"position": Vector3.ZERO, "rotation": Vector3.ZERO, "left_position": rest[0],
			"left_rotation": _radians(rest[1]), "left_pose": "Grip", "magazine": "in_gun",
			"magazine_state": "in_gun"}


## V15: the exact camera-space pose used at full ADS, kept pure for sight-alignment tests.
static func aim_pose(gun_id: String, scoped: bool = false) -> Dictionary:
	var poses: Dictionary = SCOPE_ADS_POSES if scoped else ADS_POSES
	var p: Array = poses.get(gun_id, [HOLD.get(gun_id, Vector3.ZERO), Vector3.ZERO])
	return {"position": p[0] as Vector3, "rotation": p[1] as Vector3}


func _apply_left_hand(node: Node3D, pose: Dictionary) -> void:
	var left := node.get_node_or_null("Hand_L") as Node3D
	if left == null:
		return
	Hands.set_target(left, pose["left_position"], pose["left_rotation"])
	Hands.set_pose(left, pose["left_pose"])


static func _make_magazine() -> MeshInstance3D:
	var mag := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.12, 0.03)
	mag.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.075, 0.08, 0.09)
	material.metallic = 0.55
	material.roughness = 0.5
	mag.material_override = material
	mag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mag


func _update_magazines(node: Node3D, gun_id: String, pose: Dictionary, reload_p: float) -> void:
	var state: String = pose["magazine"]
	if _mag_in_hand.has(gun_id):
		(_mag_in_hand[gun_id] as MeshInstance3D).visible = state == "in_hand"
	if gun_id != "pistol" or state != "dropping":
		_free_drop_mag()
		return
	if _drop_mag == null:
		_drop_mag = _make_magazine()
		_drop_mag.name = "DroppingMagazine"
		camera.add_child(_drop_mag)
	var fall := smoothstep(0.0, 1.0, clampf((reload_p - 0.18) / 0.12, 0.0, 1.0))
	_drop_mag.transform = node.transform * Transform3D(Basis(), Vector3(0.0, -0.08, 0.07))
	_drop_mag.position += Vector3(0.02 * fall, -0.42 * fall, 0.04 * fall)
	_drop_mag.rotation += Vector3(fall * 1.8, 0.0, fall * 0.7)


func _free_drop_mag() -> void:
	if _drop_mag != null:
		_drop_mag.queue_free()
		_drop_mag = null


func is_inspecting() -> bool:
	return _inspect_elapsed >= 0.0 or hold_inspect_at >= 0.0


func start_inspect() -> bool:
	if not sim.guns.in_hand() or builder.active or sim.player.dead or sim.guns.reloading > 0.0 \
			or sim.guns.raising > 0.0:
		return false
	sim.guns.aiming = false
	_inspect_elapsed = 0.0
	_inspect_uid = int(sim.gear.gun().get("uid", -1))
	var gun := sim.gear.gun()
	var gun_id: String = gun.get("base", "")
	var gun_node: Node3D = _models.get(gun_id) as Node3D
	if is_inside_tree():  # tests build Shooter/Melee alone, with no camera
		var sound_pos := gun_node.global_position if gun_node != null else camera.global_position
		SoundView.play_at(self, "gun_handle", sound_pos, -3.0, randf_range(0.95, 1.05))
	_say("%s%s · %d/%d rounds" % [gun["name"], sim.guns.weapon_condition_text(true), int(gun["loaded"]),
			int(sim.guns.stats()["magazine"])], INSPECT_TIME)
	return true


func cancel_inspect() -> void:
	var was_inspecting := _inspect_elapsed >= 0.0
	_inspect_elapsed = -1.0
	if was_inspecting:
		last_message = ""
		_message_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("aim") and not event.is_echo():
		_aim_held = event.is_pressed() and InputSetup.captured() and sim.ready_throw == ""  # RMB cancels a throwable without also aiming
		if _aim_held and sim.guns.in_hand():
			cancel_inspect()
	if not InputSetup.captured() or builder.active:
		return
	if event.is_action_pressed("attack") and sim.guns.in_hand() and sim.ready_throw == "":
		fire()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var base: String = sim.gear.gun().get("base", "")
	var show := sim.guns.in_hand() and sim.ready_throw == "" and not builder.active and not sim.player.dead
	var remaining := sim.guns.reloading
	var reload_started := remaining > 0.0 and (_last_reloading <= 0.0 or remaining > _last_reloading + 0.001)
	if reload_started:
		# The parent advances the fixed sim tick before this presentation node. Capture the reload's full
		# skilled duration, not the already-ticked first visible value, and never recalculate it mid-reload.
		_reload_total = maxf(remaining, sim.guns.reload_time())
		_reload_sound_progress = 0.0
		_reload_sound_gun = base
		cancel_inspect()
	_last_reloading = remaining
	if _inspect_elapsed >= 0.0 and (not show or int(sim.gear.gun().get("uid", -1)) != _inspect_uid):
		cancel_inspect()
	var inspect_p := -1.0
	if _inspect_elapsed >= 0.0:
		_inspect_elapsed = minf(INSPECT_TIME, _inspect_elapsed + delta)
		inspect_p = _inspect_elapsed / INSPECT_TIME
		if _inspect_elapsed >= INSPECT_TIME:
			_inspect_elapsed = -1.0
	if hold_inspect_at >= 0.0:
		inspect_p = hold_inspect_at
	var reload_p := hold_reload_at
	if remaining > 0.0:
		reload_p = 1.0 - remaining / maxf(0.001, _reload_total)
	var reload_cues: Array = []
	var pump_cues: Array[String] = []
	if remaining > 0.0 and _reload_sound_progress >= 0.0 and show and base == _reload_sound_gun:
		reload_cues = passed_reload_sounds(base, _reload_sound_progress, reload_p)
		_reload_sound_progress = reload_p
	elif remaining > 0.0 and _reload_sound_progress >= 0.0:
		_reload_sound_progress = -1.0  # hidden, swapped or dead: this reload stays silent from here on
	elif remaining <= 0.0:
		_reload_sound_progress = -1.0
		_reload_sound_gun = ""
	var handling := maxf(0.01, float(sim.guns.stats()["handling"])) if not sim.gear.gun().is_empty() else 0.35
	_aim_weight = 1.0 if hold_aim and aiming() else move_toward(_aim_weight, 1.0 if aiming() else 0.0, delta / handling)  # --aim screenshots start fully aimed
	for b: String in _models:
		var node: Node3D = _models[b]
		_sync_part_models(b)
		node.visible = show and b == base
		if node.visible and sim.guns.scoped() and _aim_weight > 0.9:
			node.visible = false  # V15/V23: looking through the scope the eyepiece would fill the view; the zoom and reticle take over
		if node.visible:
			var raise := clampf(sim.guns.raising / maxf(0.01, float(sim.guns.stats()["handling"])), 0.0, 1.0)
			var pose := _rest_pose(b)
			if reload_p >= 0.0:
				pose = reload_pose(b, reload_p)
			elif inspect_p >= 0.0:
				pose = inspect_pose(b, inspect_p)
			var hip_position: Vector3 = HOLD[b] + pose["position"] + Vector3(0.0, -0.25 * raise, 0.0)
			if b == "shotgun" and sim.guns.cooldown > 0.0:
				var pump_progress := 1.0 - sim.guns.cooldown / float(sim.guns.stats()["cooldown"])
				var pump := pump_pose(pump_progress)
				hip_position += pump["gun_offset"] as Vector3
				pose["left_position"] = pump["hand_position"]
				var previous_pump := 1.0 - _last_cooldown / float(sim.guns.stats()["cooldown"]) \
						if _last_cooldown > 0.0 else 0.0
				pump_cues = passed_pump_sounds(previous_pump, pump_progress)
			var hip_rotation: Vector3 = pose["rotation"]
			var ads: Dictionary = aim_pose(b, sim.guns.scoped())
			node.position = hip_position.lerp(ads["position"] as Vector3, _aim_weight) \
					+ Vector3(0.0, 0.0, 0.06 * _kick * 10.0)
			node.rotation = hip_rotation.lerp(ads["rotation"] as Vector3, _aim_weight) \
					+ Vector3(_kick * 2.0, 0.0, 0.0)
			if feel != null:
				var move_scale := lerpf(1.0, ADS_SWAY_MULT, _aim_weight)
				node.position += feel.hold_position_offset() * move_scale
				node.rotation += feel.hold_rotation_offset() * move_scale
			_apply_left_hand(node, pose)
			_update_magazines(node, b, pose, reload_p)
			Hands.reaim(node, node.basis)  # V12: through the kick and the reload too
	if not reload_cues.is_empty() and _models.has(base):
		var gun_node: Node3D = _models[base]
		for cue: Array in reload_cues:
			SoundView.play_at(self, String(cue[1]), gun_node.global_position, -3.0, randf_range(0.95, 1.05))
	if not pump_cues.is_empty() and _models.has(base):
		var pump_node: Node3D = _models[base]
		for cue: String in pump_cues:
			SoundView.play_at(self, cue, pump_node.global_position, -2.0, randf_range(0.96, 1.04))
	if reload_p < 0.0:
		_free_drop_mag()
	_flash_time -= delta
	_flash.light_energy = 6.0 if _flash_time > 0.0 else 0.0
	if feel != null:
		feel.kick = _kick  # V3: ViewFeel adds shake and bob and applies it to the camera
	else:
		camera.rotation.x = _kick  # the head holds the look; the camera only carries the kick
	var aimed_fov := AIM_FOV if sim.guns.scoped() else base_fov * IRON_FOV_MULT
	camera.fov = move_toward(camera.fov, aimed_fov if aiming() else base_fov, ZOOM_SPEED * delta)
	var gun_base := str(sim.gear.gun().get("base", ""))
	var clip: float = 0.0 if sim.guns.scoped() else float(ADS_NEAR.get(gun_base, 0.0)) * _aim_weight
	for mat: BaseMaterial3D in _fade_materials.get(gun_base, []):
		mat.distance_fade_min_distance = maxf(0.0, clip - ADS_FADE_BAND)
		mat.distance_fade_max_distance = maxf(0.001, clip)
	_kick = maxf(0.0, _kick - KICK_BACK * delta * maxf(_kick, 0.02))
	_last_cooldown = sim.guns.cooldown
	_message_time -= delta
	if _message_time <= 0.0:
		last_message = ""


## V15: true while any gun is aimed. Reload/inspect/raise/sprint all lower it; a scope only changes the FOV
## and adds its extra cone tightening once this is true.
func aiming() -> bool:
	return (_aim_held or hold_aim) and sim.guns.in_hand() and not builder.active and not sim.player.dead \
			and not sim.player.asleep and sim.guns.reloading <= 0.0 and sim.guns.raising <= 0.0 \
			and not is_inspecting() and not sprinting


## Fires if the sim lets it. Returns the id of the zombie the ray met (hit or not), -1 for none, -2 if no shot.
func fire() -> int:
	cancel_inspect()  # V13: pulling the trigger snaps the weapon straight back to its firing hold
	sim.guns.aiming = aiming()  # input can fire before Main's next presentation-to-sim sync
	var why := sim.fire()
	if why != "":
		_say(why)
		return -2
	var base: String = sim.gear.gun()["base"]
	_flash_time = 0.0 if base == "crossbow" else FLASH_TIME
	_kick = minf(deg_to_rad(12.0), _kick + deg_to_rad(KICK_DEG.get(base, 2.0)))
	if feel != null:
		feel.fired(base)
	var from := camera.global_position
	var dir := -camera.global_basis.z
	if base == "shotgun":
		var pellet_hits := sim.fire_shotgun_pellets(from, dir)
		for pellet: Dictionary in pellet_hits:
			if feel != null:
				feel.impact(pellet["position"], -dir, "blood")
				feel.hit_zombie(bool(pellet["killed"]), false)
		_say("Missed" if pellet_hits.is_empty() else ("Killed it" if pellet_hits.any(func(h: Dictionary) -> bool: return bool(h["killed"])) else "%d pellet hits" % pellet_hits.size()))
		return int(pellet_hits[0]["zombie"]) if not pellet_hits.is_empty() else -1
	if base == "crossbow":
		# The sim owns the one spread roll as well as travel, gravity and hit checks.
		sim.launch_bolt(from + dir * 0.35, dir, true)
		_say("Bolt away")
		return -1
	if not no_spread:
		dir = _in_cone(dir, deg_to_rad(sim.guns.spread_deg()))
	var to := from + dir * float(sim.data.guns["ray_range"])
	# V33: zombies are hit through their bone zones; a round through the gap between arm and body flies on.
	var hit := ZombieHitboxes.cast(get_world_3d().direct_space_state, from, to, exclude)
	if hit.is_empty() or int(hit["zombie_id"]) < 0:
		_say("Missed")
		var fx := "dust"
		if not hit.is_empty() and hit["collider"] != null and hit["collider"].has_meta("piece_key"):  # W2: glass and town doors
			var key: String = hit["collider"].get_meta("piece_key")
			var mat := sim.piece_material(key)
			if sim.player_hit_piece(key, float(sim.guns.stats().get("damage", 30.0)), "bullet") != "":
				fx = "glass" if mat == "glass" else "wood"
		if not hit.is_empty() and feel != null:
			feel.impact(hit["position"], hit["normal"], fx)  # V3: the round kicks up dust where it lands
		return -1
	var id: int = hit["zombie_id"]
	var zone: String = hit["zone"]
	var head := zone == "head"
	var r := sim.shoot_zombie(id, zone)
	_say("Killed it" if r["killed"] else (ZONE_WORDS.get(zone, "Hit") if r["hit"] else "Missed"))
	if feel != null and r["hit"]:
		feel.impact(hit["position"], hit["normal"], "blood_head" if head else "blood")
		feel.hit_zombie(r["killed"], head)
	if r["hit"] and head:
		SoundView.play_at(self, "headshot", hit["position"], -2.0, randf_range(0.9, 1.1))  # V7: a headshot reads
	return id


## A random direction within `half_angle` radians of `dir` (uniform over the cone's disc).
func _in_cone(dir: Vector3, half_angle: float) -> Vector3:
	if half_angle <= 0.0:
		return dir
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var r := tan(half_angle) * sqrt(_rng.randf())
	var a := _rng.randf() * TAU
	return (dir + side * cos(a) * r + up * sin(a) * r).normalized()


func _say(text: String, seconds: float = 1.0) -> void:
	last_message = text
	_message_time = seconds
