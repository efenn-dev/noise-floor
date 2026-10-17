class_name Learning
extends RefCounted
## P10 (playtest: a new player faced fifty pieces at once): pieces you learn by building. data/learning.json "after"
## names, for some pieces, the piece you must have built once first (a workbench before a generator, a generator
## before a power pole...); every other piece is open from the start (a Hub milestone or a project may still lock it).
## BuildGrid.place notes each piece built; what that teaches waits in `news` for SimWorld to announce and stays in
## `fresh` (the build menu's NEW badge) until you look at it there. Saved; a save without it knows every piece.

var data: GameData
var knows_all := true  # test worlds and older saves know every piece; a real new game calls start_new_game()
var built: Dictionary = {}  # piece id -> true: every piece built at least once in this game
var fresh: Dictionary = {}  # piece id -> true: learned but not yet looked at in the build menu
var news: Array = []  # pieces just learned, oldest first (take_news empties it)


func _init(p_data: GameData) -> void:
	data = p_data


func start_new_game() -> void:
	knows_all = false
	built.clear()
	fresh.clear()
	news.clear()


## The piece `id` needs built first ("" if none).
func after(id: String) -> String:
	return str(data.learning.get("after", {}).get(id, ""))


func knows(id: String) -> bool:
	return knows_all or after(id) == "" or built.has(after(id))


## The pieces to build, in order, to learn `id`: the first one can be built now, the last is the one `id` needs.
## Empty when `id` is known.
func path_to(id: String) -> Array:
	var out := []
	var at := id
	while not knows(at) and out.size() < 20:
		at = after(at)
		out.push_front(at)
	return out


## The pieces that building `id` teaches (whether or not they are known yet).
func teaches(id: String) -> Array:
	var out := []
	var table: Dictionary = data.learning.get("after", {})
	for b: String in table:
		if str(table[b]) == id and data.buildables.has(b):
			out.append(b)
	return out


## A piece was built: anything it teaches that wasn't known goes into `news` and `fresh`.
func note_built(id: String) -> void:
	if built.has(id):
		return
	var was_known := {}
	for b: String in teaches(id):
		was_known[b] = knows(b)
	built[id] = true
	for b: String in was_known:
		if not was_known[b]:
			news.append(b)
			fresh[b] = true


func take_news() -> Array:
	var out := news
	news = []
	return out


func seen(id: String) -> void:
	fresh.erase(id)


func to_dict() -> Dictionary:
	return {"knows_all": knows_all, "built": built.keys(), "fresh": fresh.keys()}


func load_dict(d: Dictionary) -> void:
	start_new_game()
	knows_all = d.is_empty() or bool(d.get("knows_all", false))  # a save from before P10 knows every piece
	for id: String in d.get("built", []):
		built[id] = true
	for id: String in d.get("fresh", []):
		fresh[id] = true
