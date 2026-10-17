class_name Salvage
extends RefCounted
## P11 (playtest: "We need a way to chop down trees for lumber and a way to get metal scrap"): what your melee hits
## take out of the world. A tree takes damage until it falls and gives its planks; a car that won't drive (or a
## highway or junkyard wreck) gives a scrap metal for every `per_scrap` damage until it's stripped. The numbers are
## data/resources.json "salvage". SimWorld.player_hit_tree / player_hit_wreck pay out, make the noise and wear the
## weapon; this only keeps count. Felled trees and stripped scrap are saved; a half-chopped tree is not.

var data: GameData
var felled: Dictionary = {}  # tree id -> true
var stripped: Dictionary = {}  # wreck id -> scrap taken out of it
var wrecks: Dictionary = {}  # P11: the countryside's static wrecks: id -> car type (vehicles are looked up by SimWorld)
var changes := 0  # goes up whenever a tree falls or a save loads, so the views know to look
var last_felled := ""  # the tree that fell last (the views tip it over; trees from a save just aren't there)
var _chop: Dictionary = {}  # tree id -> damage so far
var _strip: Dictionary = {}  # wreck id -> damage toward its next scrap


func _init(p_data: GameData) -> void:
	data = p_data


## A tree's id from where it stands (plans are seeded, so it's the same tree every load).
static func tree_id(pos: Vector3) -> String:
	return "tree_%d_%d" % [roundi(pos.x * 10.0), roundi(pos.z * 10.0)]


func cfg() -> Dictionary:
	return data.resources.get("salvage", {})


func tree_cfg(kind: String) -> Dictionary:
	var trees: Dictionary = cfg().get("trees", {})
	return trees.get(kind, trees.get("tree", {"hp": 480, "planks": 6}))


func wreck_scrap(type: String) -> int:
	return int(cfg().get("wrecks", {}).get(type, 8))


## How much of `damage` a hit of weapon class `by` does to wood or metal.
func hit_amount(material: String, damage: float, by: String) -> float:
	var factors: Dictionary = cfg().get(material + "_factor", {})
	return damage * float(factors.get(by, 1.0))


## A hit on tree `id` (of `kind`). Returns {"felled": bool, "planks": int, "done": 0..1 how far chopped}.
func hit_tree(id: String, kind: String, damage: float, by: String) -> Dictionary:
	if felled.has(id):
		return {"felled": false, "planks": 0, "done": 1.0}
	var tree := tree_cfg(kind)
	var hp := float(tree["hp"])
	var so_far := float(_chop.get(id, 0.0)) + hit_amount("wood", damage, by)
	if so_far < hp:
		_chop[id] = so_far
		return {"felled": false, "planks": 0, "done": so_far / hp}
	_chop.erase(id)
	felled[id] = true
	last_felled = id
	changes += 1
	return {"felled": true, "planks": int(tree["planks"]), "done": 1.0}


## Scrap still in wreck `id` of car `type`.
func scrap_left(id: String, type: String) -> int:
	return maxi(0, wreck_scrap(type) - int(stripped.get(id, 0)))


## A hit on wreck `id` (a car of `type`). Returns {"scrap": what this hit gave, "left": scrap still in it}.
func hit_wreck(id: String, type: String, damage: float, by: String) -> Dictionary:
	if scrap_left(id, type) <= 0:
		return {"scrap": 0, "left": 0}
	var per := float(cfg().get("per_scrap", 80.0))
	var so_far := float(_strip.get(id, 0.0)) + hit_amount("metal", damage, by)
	var gave := mini(int(so_far / per), scrap_left(id, type))
	_strip[id] = so_far - gave * per
	stripped[id] = int(stripped.get(id, 0)) + gave
	if scrap_left(id, type) <= 0:
		_strip.erase(id)
	return {"scrap": gave, "left": scrap_left(id, type)}


func to_dict() -> Dictionary:
	return {"felled": felled.keys(), "stripped": stripped.duplicate()}


func load_dict(d: Dictionary) -> void:
	felled.clear()
	stripped.clear()
	_chop.clear()
	_strip.clear()
	for id: String in d.get("felled", []):
		felled[id] = true
	var s: Dictionary = d.get("stripped", {})
	for id: String in s:
		stripped[id] = int(s[id])
	last_felled = ""
	changes += 1
