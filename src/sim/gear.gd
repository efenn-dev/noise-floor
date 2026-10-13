class_name Gear
extends RefCounted
## Gear (M13): weapons and things you wear. Stackable things (scrap, nails, food) stay counts in
## Inventory; each piece of gear is an instance with its own rolled stats, rarity and condition:
##   {uid, base, tier, rarity, stats: {effect: value}, condition: 0..1, name, set: ""}
## You carry pieces in your pockets (`pieces`, they weigh their base's weight) and wear one per slot
## (`equipped`: weapon, head, body, hands, light). Numbers are in data/gear.json.
## bonus(effect) sums what the equipped pieces give: each base's own stats (always), their rolled stats
## (only while condition is at least broken_below), and set bonuses. Skills.bonus() adds it in, so the
## rules keep asking one question. Rolls take the caller's seeded rng, so the same seed finds the same gear.

var data: GameData
var pieces: Array = []         # carried, not worn
var equipped: Dictionary = {}  # slot -> piece
var next_uid := 1

const SUFFIX := {"melee_damage": "of Hurt", "fighter_perks": "of the Brawler", "ghost_perks": "of Shadows",
		"engineer_perks": "of the Workshop", "strength": "of the Ox", "gear_quiet": "of Hush",
		"carry_kg": "of the Mule", "durability": "of Lasting", "search_speed": "of the Magpie"}
const RARE_FIRST := ["Rust", "Grim", "Night", "Ash", "Bone", "Storm", "Dead", "Iron", "Hollow", "Static"]
const RARE_SECOND := {"weapon": ["Bite", "Mangler", "Knock", "Cleaver"], "head": ["Crown", "Lid", "Visor"],
		"body": ["Shell", "Coat", "Hide"], "hands": ["Grip", "Knuckle", "Paw"], "light": ["Eye", "Beacon", "Glow"]}


func _init(p_data: GameData) -> void:
	data = p_data


func g() -> Dictionary:
	return data.gear


func slots() -> Array:
	return g()["slots"]


func base_of(piece: Dictionary) -> Dictionary:
	return g()["bases"][piece["base"]]


func slot_of(piece: Dictionary) -> String:
	return base_of(piece)["slot"]


# --- Making pieces --------------------------------------------------------------

func make(base: String, tier: String, rarity: String, stats: Dictionary = {}, condition: float = 1.0,
		piece_name: String = "", set_id: String = "") -> Dictionary:
	var piece := {"uid": next_uid, "base": base, "tier": tier, "rarity": rarity, "stats": stats,
			"condition": condition, "name": piece_name, "set": set_id}
	next_uid += 1
	if piece_name == "":
		piece["name"] = _plain_name(piece)
	return piece


## A new game: the starting pipe, white, mint, in the weapon slot.
func give_start() -> Dictionary:
	var pipe := make(g()["start_weapon"], "civilian", "white")
	equipped["weapon"] = pipe
	return pipe


## One random piece found in `source` (a loot table such as "kitchen", or "zombie"):
## tier (Police with its chance, else Civilian), then rarity by weight (white 70 / blue 20 / yellow 8 /
## set 2; set only from a set's sources or a Police roll, otherwise its weight is left out), then a base.
func roll_piece(rng: RandomNumberGenerator, source: String) -> Dictionary:
	var tier := "police" if rng.randf() < float(g()["tiers"]["police"]["chance"]) else "civilian"
	var set_id := _set_for(source, tier)
	var weights := {}
	for r: String in ["white", "blue", "yellow", "set"]:
		if r != "set" or set_id != "":
			weights[r] = float(g()["rarities"][r]["weight"])
	var rarity: String = _weighted(rng, weights)
	if rarity == "set":
		var names: Dictionary = g()["sets"][set_id]["pieces"]
		var bases := names.keys()
		bases.sort()
		var set_base: String = bases[rng.randi_range(0, bases.size() - 1)]
		return make(set_base, tier, "set", {}, roll_condition(rng), names[set_base], set_id)
	var all_bases: Array = g()["bases"].keys()
	all_bases.sort()
	var base: String = all_bases[rng.randi_range(0, all_bases.size() - 1)]
	var count := 0
	if rarity != "white":
		var span: Array = g()["rarities"][rarity]["stats"]
		count = rng.randi_range(int(span[0]), int(span[1])) + int(g()["tiers"][tier]["extra_stats"])
	var piece := make(base, tier, rarity, roll_stats(rng, count), roll_condition(rng))
	piece["name"] = _rolled_name(piece, rng)
	return piece


## A named unique (gold): its fixed stats, each rolled in its own range.
func roll_unique(rng: RandomNumberGenerator, unique: String) -> Dictionary:
	var u: Dictionary = g()["uniques"][unique]
	var stats := {}
	for s: String in u["stats"]:
		stats[s] = _roll_value(rng, s, u["stats"][s][0], u["stats"][s][1])
	return make(u["base"], u["tier"], "gold", stats, roll_condition(rng), u["name"])


## `count` different stats, each a value in its range.
func roll_stats(rng: RandomNumberGenerator, count: int) -> Dictionary:
	var ids: Array = g()["stats"].keys()
	ids.sort()
	var out := {}
	for i in mini(count, ids.size()):
		var s: String = ids.pop_at(rng.randi_range(0, ids.size() - 1))
		out[s] = _roll_value(rng, s, g()["stats"][s]["min"], g()["stats"][s]["max"])
	return out


func roll_condition(rng: RandomNumberGenerator) -> float:
	var span: Array = g()["found_condition"]
	return snappedf(rng.randf_range(float(span[0]), float(span[1])), 0.01)


func _roll_value(rng: RandomNumberGenerator, stat: String, lo: Variant, hi: Variant) -> float:
	if bool(g()["stats"][stat].get("int", false)):
		return float(rng.randi_range(int(lo), int(hi)))
	return snappedf(rng.randf_range(float(lo), float(hi)), 0.01)


func _set_for(source: String, tier: String) -> String:
	var ids: Array = g()["sets"].keys()
	ids.sort()
	for s: String in ids:
		if tier == "police" or source in g()["sets"][s].get("sources", []):
			return s
	return ""


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var pick := rng.randf() * total
	var last := ""
	for k: String in weights:
		last = k
		pick -= float(weights[k])
		if pick <= 0.0:
			return k
	return last


func _plain_name(piece: Dictionary) -> String:
	var base_name: String = base_of(piece)["name"]
	return ("Police " + base_name.to_lower()) if piece["tier"] == "police" else base_name


func _rolled_name(piece: Dictionary, rng: RandomNumberGenerator) -> String:
	if piece["rarity"] == "blue":
		var best := ""
		for s: String in piece["stats"]:
			best = s if best == "" else best
		return "%s %s" % [_plain_name(piece), SUFFIX.get(best, "")]
	if piece["rarity"] == "yellow":
		var second: Array = RARE_SECOND[slot_of(piece)]
		return "%s %s" % [RARE_FIRST[rng.randi_range(0, RARE_FIRST.size() - 1)],
				second[rng.randi_range(0, second.size() - 1)]]
	return _plain_name(piece)


# --- Carrying and wearing --------------------------------------------------------

## The piece with this uid, in your pockets or worn ({} if neither).
func find(uid: int) -> Dictionary:
	for p: Dictionary in pieces:
		if int(p["uid"]) == uid:
			return p
	for s: String in equipped:
		if int(equipped[s]["uid"]) == uid:
			return equipped[s]
	return {}


func is_equipped(uid: int) -> bool:
	for s: String in equipped:
		if int(equipped[s]["uid"]) == uid:
			return true
	return false


## Takes a piece out of your pockets (to drop it). {} if it isn't there.
func take(uid: int) -> Dictionary:
	for i in pieces.size():
		if int(pieces[i]["uid"]) == uid:
			return pieces.pop_at(i)
	return {}


## Wears a piece from your pockets; whatever was in that slot goes back in your pockets. "" or why not.
func equip(uid: int) -> String:
	var piece := take(uid)
	if piece.is_empty():
		return "You don't have that"
	var slot := slot_of(piece)
	if equipped.has(slot):
		pieces.append(equipped[slot])
	equipped[slot] = piece
	return ""


func unequip(slot: String) -> String:
	if not equipped.has(slot):
		return "Nothing there"
	pieces.append(equipped[slot])
	equipped.erase(slot)
	return ""


## Weight of the pieces in your pockets (worn pieces don't count against your carry limit).
func weight() -> float:
	var kg := 0.0
	for p: Dictionary in pieces:
		kg += float(base_of(p)["weight"])
	return kg


# --- What gear gives -------------------------------------------------------------

## A piece's rolled stats work only above broken_below; its base stats always do.
func working(piece: Dictionary) -> bool:
	return float(piece["condition"]) >= float(g()["broken_below"])


## The total of `effect` from everything you wear: base stats, working rolled stats and set bonuses.
## Effects are the skills' effect names (melee_damage, carry_kg, search_speed, damage_cut, walk_quiet)
## plus gear's own: strength (levels), fighter_perks / ghost_perks / engineer_perks (ranks),
## gear_quiet (footsteps and swings), quiet_all (every noise you make), durability.
func bonus(effect: String) -> float:
	var total := 0.0
	for s: String in equipped:
		var piece: Dictionary = equipped[s]
		total += float(base_of(piece).get("base", {}).get(effect, 0.0)) * tier_mult(piece)
		if working(piece):
			total += float(piece["stats"].get(effect, 0.0))
	for set_id: String in g()["sets"]:
		var n := set_count(set_id)
		var bonuses: Dictionary = g()["sets"][set_id]["bonuses"]
		for at: String in bonuses:
			if n >= int(at):
				total += float(bonuses[at].get(effect, 0.0))
	return total


func tier_mult(piece: Dictionary) -> float:
	return float(g()["tiers"][piece["tier"]]["base_mult"])


## How many working pieces of a set you're wearing.
func set_count(set_id: String) -> int:
	var n := 0
	for s: String in equipped:
		if equipped[s]["set"] == set_id and working(equipped[s]):
			n += 1
	return n


## The equipped weapon's stats (data/weapons.json for its base, damage times its tier), or fists.
func weapon_stats() -> Dictionary:
	if not equipped.has("weapon"):
		return data.weapons["fists"]
	var piece: Dictionary = equipped["weapon"]
	var w: Dictionary = data.weapons[base_of(piece)["weapon"]].duplicate()
	w["damage"] = float(w["damage"]) * tier_mult(piece)
	return w


func weapon_name() -> String:
	return equipped["weapon"]["name"] if equipped.has("weapon") else "Fists"


# --- Wear and repair ---------------------------------------------------------------

## One hit's wear on the weapon. Returns true if that hit wore it out (crossed broken_below).
func wear_weapon() -> bool:
	return equipped.has("weapon") and _wear(equipped["weapon"], float(g()["wear_per_hit"]))


## A day's wear on everything worn but the weapon. Returns the pieces that just wore out.
func wear_day() -> Array:
	var out := []
	for s: String in equipped:
		if s != "weapon" and _wear(equipped[s], float(g()["wear_per_day"])):
			out.append(equipped[s])
	return out


func _wear(piece: Dictionary, amount: float) -> bool:
	var was := working(piece)
	var tough := float(piece["stats"].get("durability", 0.0)) if was else 0.0
	piece["condition"] = maxf(0.0, float(piece["condition"]) - amount * (1.0 - tough))
	return was and not working(piece)


## Puts a piece (carried or worn) back to mint. Uses one repair kit from `inv`. "" or why not.
func repair(uid: int, inv: Inventory) -> String:
	var piece := find(uid)
	if piece.is_empty():
		return "You don't have that"
	if float(piece["condition"]) >= 1.0:
		return "It's already mint"
	if not inv.remove("repair_kit", 1):
		return "You need a repair kit (the Press makes them)"
	piece["condition"] = 1.0
	return ""


# --- Showing it ------------------------------------------------------------------

func color(piece: Dictionary) -> Color:
	return Color.from_string(g()["rarities"][piece["rarity"]]["color"], Color.WHITE)


static func rarity_word(rarity: String) -> String:
	return {"white": "white", "blue": "blue", "yellow": "yellow", "gold": "gold", "set": "green",
			"orange": "orange"}.get(rarity, rarity)


func condition_text(piece: Dictionary) -> String:
	var c := float(piece["condition"])
	var word := "Mint" if c >= 0.9 else ("Good" if c >= 0.6 else ("Worn" if working(piece) else "Worn out"))
	return "%s %d%%" % [word, roundi(c * 100.0)]


## What a piece does, one line each: base stats, then rolled stats, then its set's bonuses.
func stat_lines(piece: Dictionary) -> Array:
	var lines := []
	var b := base_of(piece)
	if b.has("weapon"):
		var w: Dictionary = data.weapons[b["weapon"]]
		lines.append("Damage %d, a swing every %.2f s" % [roundi(float(w["damage"]) * tier_mult(piece)), float(w["cooldown"])])
	for e: String in b.get("base", {}):
		lines.append(_base_text(e, float(b["base"][e]) * tier_mult(piece)))
	for s: String in piece["stats"]:
		var v := float(piece["stats"][s])
		var shown := roundi(v * 100.0) if not bool(g()["stats"][s].get("int", false)) else roundi(v)
		lines.append((g()["stats"][s]["text"] % shown) + ("" if working(piece) else " (worn out)"))
	if piece["set"] != "":
		var st: Dictionary = g()["sets"][piece["set"]]
		var parts := PackedStringArray()
		for at: String in st["bonuses"]:
			for e: String in st["bonuses"][at]:
				parts.append("%s: %s" % [at, _base_text(e, float(st["bonuses"][at][e]))])
		lines.append("%s set (%d worn): %s" % [st["name"], set_count(piece["set"]), ", ".join(parts)])
	return lines


static func _base_text(effect: String, v: float) -> String:
	match effect:
		"damage_cut": return "Zombies hurt you %d%% less" % roundi(v * 100.0)
		"walk_quiet": return "Footsteps %d quieter" % roundi(v)
		"carry_kg": return "+%d kg carry" % roundi(v)
		"melee_damage": return "+%d%% melee damage" % roundi(v * 100.0)
		"search_speed": return "+%d%% search speed" % roundi(v * 100.0)
		"quiet_all": return "your noises %d quieter" % roundi(v)
	return "%s %s" % [effect, v]


# --- Saving ------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"pieces": pieces.duplicate(true), "equipped": equipped.duplicate(true), "next_uid": next_uid}


func load_dict(d: Dictionary) -> void:
	pieces = []
	for p: Dictionary in d.get("pieces", []):
		pieces.append(clean(p))
	equipped = {}
	for s: String in d.get("equipped", {}):
		equipped[s] = clean(d["equipped"][s])
	next_uid = int(d.get("next_uid", 1))


## A piece read back from JSON (numbers come back as floats).
static func clean(p: Dictionary) -> Dictionary:
	var stats := {}
	for s: String in p.get("stats", {}):
		stats[s] = float(p["stats"][s])
	return {"uid": int(p["uid"]), "base": str(p["base"]), "tier": str(p["tier"]), "rarity": str(p["rarity"]),
			"stats": stats, "condition": float(p["condition"]), "name": str(p["name"]), "set": str(p.get("set", ""))}
