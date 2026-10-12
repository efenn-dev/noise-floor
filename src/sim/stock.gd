class_name Stock
extends Inventory
## What you can build or feed with right now: your pockets first, then any storage crates in range.
## Behaves like an Inventory, so BuildGrid and Factory take it as-is. Things given to it go to your
## pockets, unless refund_to_storage is set (build refunds go back into the first crate in range).

var pockets: Inventory
var crates: Array = []  # Inventory per storage crate in range
var refund_to_storage := false


func _init(p_pockets: Inventory, p_crates: Array) -> void:
	pockets = p_pockets
	crates = p_crates


func count(item: String) -> int:
	var n := pockets.count(item)
	for c: Inventory in crates:
		n += c.count(item)
	return n


func add(item: String, amount: int) -> void:
	give_all({item: amount})


func has_all(costs: Dictionary) -> bool:
	for item: String in costs:
		if count(item) < int(costs[item]):
			return false
	return true


func take_all(costs: Dictionary) -> bool:
	if not has_all(costs):
		return false
	for item: String in costs:
		var need := int(costs[item])
		for source: Inventory in [pockets] + crates:
			var n := mini(need, source.count(item))
			if n > 0:
				source.take_all({item: n})
				need -= n
	return true


func give_all(items: Dictionary) -> void:
	if refund_to_storage and not crates.is_empty():
		crates[0].give_all(items)
	else:
		pockets.give_all(items)


func items() -> Array:
	var ids := {}
	for source: Inventory in [pockets] + crates:
		for item: String in source.items():
			ids[item] = true
	var out := ids.keys()
	out.sort()
	return out
