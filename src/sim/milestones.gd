class_name Milestones
extends RefCounted
## F2 (Emmitt: building "more like Satisfactory"): the Hub's milestones (data/milestones.json), like Satisfactory's
## HUB. Each asks for parts, handed in at the Hub (SimWorld.hub_deliver: from your pockets or a crate near it),
## part at a time; what's handed in stays handed in. A milestone fully handed in is done and unlocks its pieces.
## Tier 1 is open from the start; each later tier opens once every milestone of the tier before is done. Pieces no
## milestone unlocks can always be built. The "final" milestone unlocks the radio mast (the rescue broadcast).

var data: GameData
var delivered: Dictionary = {}  # milestone id -> {item: count handed in so far}
var done: Array = []            # milestone ids finished, in the order they were
var _unlock_of: Dictionary = {}  # buildable id -> the milestone that unlocks it


func _init(p_data: GameData) -> void:
	data = p_data
	for id: String in all():
		for b: String in cfg(id).get("unlocks", []):
			_unlock_of[b] = id


func _table() -> Dictionary:
	return data.milestones.get("milestones", {})


## Every milestone id, tier by tier (data order within a tier).
func all() -> Array:
	var ids: Array = _table().keys()
	var order := {}
	for i in ids.size():
		order[ids[i]] = i
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ta := int(_table()[a]["tier"])
		var tb := int(_table()[b]["tier"])
		return ta < tb if ta != tb else int(order[a]) < int(order[b]))
	return ids


func cfg(id: String) -> Dictionary:
	return _table().get(id, {})


func tiers() -> Array:
	var out: Array = []
	for id: String in all():
		var t := int(cfg(id)["tier"])
		if not out.has(t):
			out.append(t)
	return out


func tier_name(tier: int) -> String:
	return str(data.milestones.get("tiers", {}).get(str(tier), "Tier %d" % tier))


## Whether tier `tier`'s milestones can be worked on: tier 1 always, then once all of the tier before are done.
func tier_open(tier: int) -> bool:
	for id: String in all():
		if int(cfg(id)["tier"]) < tier and not done.has(id):
			return false
	return true


func is_done(id: String) -> bool:
	return done.has(id)


## Open to hand parts in to (its tier is open and it isn't done).
func available(id: String) -> bool:
	return not cfg(id).is_empty() and not is_done(id) and tier_open(int(cfg(id)["tier"]))


## What's still to hand in for `id`: {item: count}.
func missing(id: String) -> Dictionary:
	var out := {}
	var got: Dictionary = delivered.get(id, {})
	for item: String in cfg(id).get("cost", {}):
		var left := int(cfg(id)["cost"][item]) - int(got.get(item, 0))
		if left > 0:
			out[item] = left
	return out


## Hands in what `stock` has of what `id` still needs (stock: an Inventory or a Stock). Returns what moved
## ({} if nothing could); "done": true in it when that finished the milestone.
func deliver(id: String, stock: Variant) -> Dictionary:
	var moved := {}
	if not available(id):
		return moved
	if not delivered.has(id):
		delivered[id] = {}
	var need := missing(id)
	for item: String in need:
		var n := mini(int(stock.count(item)), int(need[item]))
		if n > 0 and stock.take_all({item: n}):
			delivered[id][item] = int(delivered[id].get(item, 0)) + n
			moved[item] = n
	if not moved.is_empty() and missing(id).is_empty():
		done.append(id)
		moved["done"] = true
	return moved


## Whether `buildable` may be built (no milestone unlocks it, or that one is done).
func unlocked(buildable: String) -> bool:
	return not _unlock_of.has(buildable) or done.has(_unlock_of[buildable])


## The milestone that unlocks `buildable` ("" if none does).
func unlocked_by(buildable: String) -> String:
	return str(_unlock_of.get(buildable, ""))


## The final milestone's id ("" if the data has none).
func final_id() -> String:
	for id: String in all():
		if bool(cfg(id).get("final", false)):
			return id
	return ""


func to_dict() -> Dictionary:
	return {"done": done.duplicate(), "delivered": delivered.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	done = []
	for id: Variant in d.get("done", []):
		if _table().has(str(id)):
			done.append(str(id))
	delivered = {}
	var raw: Dictionary = d.get("delivered", {})
	for id: String in raw:
		delivered[id] = {}
		for item: String in raw[id]:
			delivered[id][item] = int(raw[id][item])


## F2 migration: a save from before the Hub had every piece unlocked, so all milestones but the final one are
## marked done (nothing it built is locked away; the rescue is still ahead).
func grant_all_but_final() -> void:
	var final := final_id()
	for id: String in all():
		if id != final and not done.has(id):
			done.append(id)
