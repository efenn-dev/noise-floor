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
## M14: guns are gear in the "gun" slot, and gun parts are gear (slot "part") carried in your pockets and
## attached to a gun at a workbench: a gun piece also has {parts: {muzzle|magazine|sight|stock: piece},
## loaded: rounds in it, ammo: the ammo item it's loaded with}. gun_stats(piece) = its base (guns.json, damage
## times its tier) plus its own rolled gun stats plus its working parts. Gun-only stats (those whose
## gear.json entry lists "slots") count only through gun_stats, never bonus(). Ordinary finds and drops never
## roll a gun or part, and only gun pieces roll gun stats, so M13's seeded rolls are unchanged.

var data: GameData
var pieces: Array = []         # carried, not worn
var equipped: Dictionary = {}  # slot -> piece
var next_uid := 1

const SUFFIX := {"melee_damage": "of Hurt", "fighter_perks": "of the Brawler", "ghost_perks": "of Shadows",
		"engineer_perks": "of the Workshop", "strength": "of the Ox", "gear_quiet": "of Hush",
		"carry_kg": "of the Mule", "durability": "of Lasting", "search_speed": "of the Magpie",
		"gun_damage": "of Ruin", "gun_quiet": "of Whispers", "accuracy": "of the Hawk", "recoil_cut": "of Steadiness"}
const RARE_FIRST := ["Rust", "Grim", "Night", "Ash", "Bone", "Storm", "Dead", "Iron", "Hollow", "Static"]
const GUN_SLOTS := ["gun", "part"]
const RARE_SECOND := {"gun": ["Thunder", "Barker", "Rattler"], "part": ["Hush", "Edge", "Eye"],
		"weapon": ["Bite", "Mangler", "Knock", "Cleaver"], "head": ["Crown", "Lid", "Visor"],
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
	if slot_of(piece) == "gun":
		piece["parts"] = {}
		piece["loaded"] = 0
		piece["ammo"] = data.guns["ammo_order"][0]
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
	var all_bases: Array = g()["bases"].keys().filter(func(b: String) -> bool:
			return not g()["bases"][b]["slot"] in GUN_SLOTS)
	all_bases.sort()
	var base: String = all_bases[rng.randi_range(0, all_bases.size() - 1)]
	return _roll_as(rng, base, tier, rarity)


func _roll_as(rng: RandomNumberGenerator, base: String, tier: String, rarity: String) -> Dictionary:
	var count := 0
	if rarity != "white":
		var span: Array = g()["rarities"][rarity]["stats"]
		count = rng.randi_range(int(span[0]), int(span[1])) + int(g()["tiers"][tier]["extra_stats"])
	var piece := make(base, tier, rarity, roll_stats(rng, count, g()["bases"][base]["slot"]), roll_condition(rng))
	piece["name"] = _rolled_name(piece, rng)
	return piece


## M14: one gun or gun part found ("gun" or "part"): a base by guns.json weights, the tier (Police with its
## chance, or `police` forced), a rarity by weight (no sets), stats from the gun stats only.
func roll_gun_piece(rng: RandomNumberGenerator, kind: String, police: bool = false) -> Dictionary:
	var tier := "police" if police or rng.randf() < float(g()["tiers"]["police"]["chance"]) else "civilian"
	var weights := {}
	for r: String in ["white", "blue", "yellow"]:
		weights[r] = float(g()["rarities"][r]["weight"])
	var rarity: String = _weighted(rng, weights)
	var base: String = _weighted(rng, data.guns["gun_weights" if kind == "gun" else "part_weights"])
	return _roll_as(rng, base, tier, rarity)


## A named unique (gold): its fixed stats, each rolled in its own range.
func roll_unique(rng: RandomNumberGenerator, unique: String) -> Dictionary:
	var u: Dictionary = g()["uniques"][unique]
	var stats := {}
	for s: String in u["stats"]:
		stats[s] = _roll_value(rng, s, u["stats"][s][0], u["stats"][s][1])
	return make(u["base"], u["tier"], "gold", stats, roll_condition(rng), u["name"])


## `count` different stats, each a value in its range. A gun or part rolls only stats that list its slot;
## anything else only stats that list no slots.
func roll_stats(rng: RandomNumberGenerator, count: int, slot: String = "") -> Dictionary:
	var ids: Array = g()["stats"].keys().filter(func(s: String) -> bool:
			var only: Variant = g()["stats"][s].get("slots")
			return (slot in only) if only is Array else not slot in GUN_SLOTS)
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
	var found := find(uid)
	if not found.is_empty() and slot_of(found) == "part":
		return "Attach it to a gun at a workbench"
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
		for slot: String in p.get("parts", {}):
			kg += float(base_of(p["parts"][slot])["weight"])
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
		if working(piece) and not g()["stats"].get(effect, {}).has("slots"):  # gun stats: gun_stats() only
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

# --- Guns (M14) --------------------------------------------------------------------

func gun() -> Dictionary:
	return equipped.get("gun", {})


func gun_name() -> String:
	return equipped["gun"]["name"] if equipped.has("gun") else ""


## A part piece's numbers in guns.json ({} if it isn't a part).
func part_def(piece: Dictionary) -> Dictionary:
	if piece.is_empty():
		return {}
	return data.guns["parts"].get(base_of(piece).get("part", ""), {})


## The gun's effective numbers: its base (guns.json; damage times its tier), its own rolled gun stats and
## its working parts. Keys: damage, range, spread, recoil, settle, handling, magazine, loudness, cooldown,
## reload, knockback, wear_per_shot, sound, plus suppressed (a working muzzle part cuts loudness) and
## muzzle_wear (per shot, less with a threaded barrel). The rules and the HUD both read this.
func gun_stats(piece: Dictionary) -> Dictionary:
	var s: Dictionary = data.guns["guns"][base_of(piece)["gun"]].duplicate()
	var dmg := 0.0
	var quiet := 0.0
	var acc := 0.0
	var recoil := 0.0
	var mag := 0.0
	var muzzle := 0.0
	var all := [piece]
	for slot: String in piece.get("parts", {}):
		all.append(piece["parts"][slot])
	for p: Dictionary in all:
		if not working(p):
			continue
		dmg += float(p["stats"].get("gun_damage", 0.0))
		quiet += float(p["stats"].get("gun_quiet", 0.0))
		acc += float(p["stats"].get("accuracy", 0.0))
		recoil -= float(p["stats"].get("recoil_cut", 0.0))
		var pd := part_def(p) if not is_same(p, piece) else {}
		acc += float(pd.get("range", 0.0))
		recoil += float(pd.get("recoil", 0.0))
		mag += float(pd.get("magazine", 0.0))
		muzzle += float(pd.get("loudness", 0.0))
	s["damage"] = float(s["damage"]) * tier_mult(piece) * (1.0 + dmg)
	s["range"] = float(s["range"]) * (1.0 + acc)
	s["recoil"] = float(s["recoil"]) * maxf(0.2, 1.0 + recoil)
	s["magazine"] = floori(float(s["magazine"]) * (1.0 + mag))
	s["loudness"] = maxf(0.0, float(s["loudness"]) + muzzle - quiet)
	s["suppressed"] = muzzle < 0.0
	var m: Dictionary = piece.get("parts", {}).get("muzzle", {})
	s["muzzle_wear"] = float(part_def(m).get("wear_per_shot", 0.0)) * (1.0 - float(piece["stats"].get("threaded", 0.0)))
	return s


## Attaches a part from your pockets to `gun_piece` (worn or carried). A part already in that slot comes
## back to your pockets. "" or why not.
func attach(gun_piece: Dictionary, part_uid: int) -> String:
	if gun_piece.is_empty() or slot_of(gun_piece) != "gun":
		return "Hold a gun first (equip one from Tab)"
	var part := {}
	for p: Dictionary in pieces:
		if int(p["uid"]) == part_uid and slot_of(p) == "part":
			part = p
	if part.is_empty():
		return "You don't have that part"
	var slot: String = part_def(part)["slot"]
	take(part_uid)
	if gun_piece["parts"].has(slot):
		pieces.append(gun_piece["parts"][slot])
	gun_piece["parts"][slot] = part
	return ""


## Takes the part in `slot` off the gun, back into your pockets. Rounds that no longer fit the magazine
## come out too. Returns {"why": "" or why not, "rounds": how many came out}.
func detach(gun_piece: Dictionary, slot: String) -> Dictionary:
	if gun_piece.is_empty() or not gun_piece.get("parts", {}).has(slot):
		return {"why": "Nothing attached there", "rounds": 0}
	pieces.append(gun_piece["parts"][slot])
	gun_piece["parts"].erase(slot)
	var spare := maxi(0, int(gun_piece["loaded"]) - int(gun_stats(gun_piece)["magazine"]))
	gun_piece["loaded"] = int(gun_piece["loaded"]) - spare
	return {"why": "", "rounds": spare}


## One shot's wear on the gun and its muzzle part. Returns the pieces that just wore out.
func wear_shot(gun_piece: Dictionary) -> Array:
	var out := []
	var st := gun_stats(gun_piece)
	if _wear(gun_piece, float(st["wear_per_shot"])):
		out.append(gun_piece)
	var m: Dictionary = gun_piece["parts"].get("muzzle", {})
	if not m.is_empty() and _wear(m, float(st["muzzle_wear"])):
		out.append(m)
	return out


## One hit's wear on the weapon. Returns true if that hit wore it out (crossed broken_below).
func wear_weapon() -> bool:
	return equipped.has("weapon") and _wear(equipped["weapon"], float(g()["wear_per_hit"]))


## A day's wear on everything worn but the weapon. Returns the pieces that just wore out.
func wear_day() -> Array:
	var out := []
	for s: String in equipped:
		if not s in ["weapon", "gun"] and _wear(equipped[s], float(g()["wear_per_day"])):
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
	if b.has("gun"):
		var gs := gun_stats(piece)
		lines.append("Damage %d, range %d m, %d rounds" % [roundi(gs["damage"]), roundi(gs["range"]), int(gs["magazine"])])
		lines.append("Loudness %d%s, recoil %.1f" % [roundi(gs["loudness"]), " (suppressed)" if gs["suppressed"] else "",
				float(gs["recoil"])])
		lines.append("Loaded: %d %s" % [int(piece["loaded"]), data.item_name(piece["ammo"])])
		for slot: String in piece["parts"]:
			lines.append("%s: %s" % [slot.capitalize(), piece["parts"][slot]["name"]])
	if b.has("part"):
		lines.append(part_text(piece))
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


## What a part does, e.g. "Muzzle: 20 quieter, wears 0.5% a shot".
func part_text(piece: Dictionary) -> String:
	var pd := part_def(piece)
	var bits := PackedStringArray()
	if pd.has("loudness"):
		bits.append("%d quieter, wears %.2f%% a shot" % [-int(pd["loudness"]), float(pd.get("wear_per_shot", 0.0)) * 100.0])
	if pd.has("magazine"):
		bits.append("+%d%% rounds" % roundi(float(pd["magazine"]) * 100.0))
	if pd.has("range"):
		bits.append("+%d%% accuracy at range" % roundi(float(pd["range"]) * 100.0))
	if pd.has("recoil"):
		bits.append("%d%% less recoil" % roundi(-float(pd["recoil"]) * 100.0))
	return "%s: %s" % [str(pd.get("slot", "")).capitalize(), ", ".join(bits)]


static func _base_text(effect: String, v: float) -> String:
	match effect:
		"damage_cut": return "Zombies hurt you %d%% less" % roundi(v * 100.0)
		"walk_quiet": return "Footsteps %d quieter" % roundi(v)
		"carry_kg": return "+%d kg carry" % roundi(v)
		"melee_damage": return "+%d%% melee damage" % roundi(v * 100.0)
		"search_speed": return "+%d%% search speed" % roundi(v * 100.0)
		"quiet_all": return "your noises %d quieter" % roundi(v)
		"warmth": return "The cold gets to you %d%% slower" % roundi(v * 100.0)  # M16
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
	var out := {"uid": int(p["uid"]), "base": str(p["base"]), "tier": str(p["tier"]), "rarity": str(p["rarity"]),
			"stats": stats, "condition": float(p["condition"]), "name": str(p["name"]), "set": str(p.get("set", ""))}
	if p.has("parts"):  # M14: a gun, with its parts and what's loaded
		var parts := {}
		for slot: String in p["parts"]:
			parts[slot] = clean(p["parts"][slot])
		out["parts"] = parts
		out["loaded"] = int(p.get("loaded", 0))
		out["ammo"] = str(p.get("ammo", "ammo_standard"))
	return out
