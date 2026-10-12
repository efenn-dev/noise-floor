class_name Inventory
extends RefCounted
## Item counts by id. Each item has a weight (data/items.json); the carry limit lives in SimWorld.

signal changed

var _counts: Dictionary = {}  # item id (String) -> int > 0


func count(item: String) -> int:
	return _counts.get(item, 0)


func add(item: String, amount: int) -> void:
	if amount <= 0:
		return
	_counts[item] = count(item) + amount
	changed.emit()


## Takes `amount` of one item. All or nothing: returns false and changes nothing if short.
func remove(item: String, amount: int) -> bool:
	return take_all({item: amount})


## True if every item in `costs` ({id: amount}) is on hand.
func has_all(costs: Dictionary) -> bool:
	for item: String in costs:
		if count(item) < int(costs[item]):
			return false
	return true


## Takes a whole bill of materials, or nothing at all.
func take_all(costs: Dictionary) -> bool:
	if not has_all(costs):
		return false
	for item: String in costs:
		var left := count(item) - int(costs[item])
		if left > 0:
			_counts[item] = left
		else:
			_counts.erase(item)
	changed.emit()
	return true


func give_all(items: Dictionary) -> void:
	for item: String in items:
		if int(items[item]) > 0:
			_counts[item] = count(item) + int(items[item])
	changed.emit()


## Total weight in kg.
func weight(data: GameData) -> float:
	var kg := 0.0
	for item: String in _counts:
		kg += _counts[item] * data.item_weight(item)
	return kg


## Item ids currently held, sorted, for display.
func items() -> Array:
	var ids := _counts.keys()
	ids.sort()
	return ids
