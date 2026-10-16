class_name Skills
extends RefCounted
## Skills that level by doing, 0-10 (Zomboid style), and perks bought with the points they earn
## (Diablo 2 style). Everything numeric is in data/skills.json:
##   skills.<id>.xp      xp per action ("swing", "search", ...); practice() adds it
##   skills.<id>.effects what each level gives: effect -> amount per level, or {"value", "every"} for
##                       "value per `every` levels" (Farming: 1 extra vegetable per 3 levels)
##   perks.<id>.effects  what each rank gives; perks.<id>.synergy adds more per `every` points spent
##                       in another tree (Dampened Gears gains from Ghost), once you have a rank
##   levels_per_perk_point: every 3 skill levels gained in total earn a perk point
## The rules ask one question, bonus(effect), and get the sum over every skill level and perk rank,
## so a test can set levels or ranks and read the numbers. Skills and perks survive death.

var data: GameData
var xp: Dictionary = {}     # skill -> total xp
var perks: Dictionary = {}  # perk -> rank (1-5); missing = 0
## Points earned and not yet spent. Never refunded (respec is a later milestone).
var perk_points := 0
## M13: what you wear. bonus() adds its stats in, Strength levels from gear count for Strength's
## effects, and "+N to <tree> perks" raises every perk you have a rank in, in that tree (past 5 too).
var gear: Gear


func _init(p_data: GameData) -> void:
	data = p_data


## Skill ids in the order the skills screen lists them.
func ids() -> Array:
	return data.skills["order"]


func level(skill: String) -> int:
	var total := float(xp.get(skill, 0.0))
	var levels: Array = data.skills["levels"]
	var lv := 0
	for i in levels.size():
		if total >= float(levels[i]):
			lv = i
	return lv


func max_level() -> int:
	return data.skills["levels"].size() - 1


## Every skill's level added up (perk points come from this).
func total_levels() -> int:
	var n := 0
	for s: String in data.skills["skills"]:
		n += level(s)
	return n


## Perk points the total levels are worth (spent or not).
func points_earned() -> int:
	return total_levels() / int(data.skills["levels_per_perk_point"])


## Adds the XP that `action` is worth for `skill`, `times` over (e.g. seconds of sprinting).
## New perk points go into perk_points. Returns the new level.
func practice(skill: String, action: String, times: float = 1.0) -> int:
	var before := points_earned()
	xp[skill] = float(xp.get(skill, 0.0)) + float(data.skills["skills"][skill]["xp"].get(action, 0.0)) * times
	perk_points += maxi(0, points_earned() - before)
	return level(skill)


## [xp into this level, xp this level needs], or [0, 0] at the top level.
func progress(skill: String) -> Array:
	var levels: Array = data.skills["levels"]
	var lv := level(skill)
	if lv >= levels.size() - 1:
		return [0, 0]
	var total := float(xp.get(skill, 0.0))
	return [total - float(levels[lv]), float(levels[lv + 1]) - float(levels[lv])]


func skill_name(skill: String) -> String:
	return data.skills["skills"][skill]["name"]


## True for a skill that's listed but does nothing yet (Firearms, until guns).
func is_disabled(skill: String) -> bool:
	return bool(data.skills["skills"][skill].get("disabled", false))


# --- Perks ---------------------------------------------------------------------

func rank(perk: String) -> int:
	return int(perks.get(perk, 0))


func max_rank() -> int:
	return int(data.skills["perk_max_rank"])


func perk_name(perk: String) -> String:
	return data.skills["perks"][perk]["name"]


## "" if a point can go into `perk`, otherwise why not.
func can_spend(perk: String) -> String:
	if not data.skills["perks"].has(perk):
		return "No such perk"
	if rank(perk) >= max_rank():
		return "%s is at its top rank" % perk_name(perk)
	if perk_points <= 0:
		return "No perk points (one every %d skill levels)" % int(data.skills["levels_per_perk_point"])
	return ""


## Spends a perk point on `perk`. Returns "" or why not.
func spend(perk: String) -> String:
	var why := can_spend(perk)
	if why == "":
		perk_points -= 1
		perks[perk] = rank(perk) + 1
	return why


## F4: up to three perks for the dawn pick (PerkPickScreen), one from each tree: of that tree's perks below the
## top rank, one with the fewest ranks so far, chosen by `seed` (the day) so the offer changes from day to day.
func offer(seed: int) -> Array:
	var out := []
	var trees: Array = data.skills["trees"].keys()
	for i in trees.size():
		var lowest := []
		var low_rank := max_rank()
		for perk: String in data.skills["trees"][trees[i]]["perks"]:
			var r := rank(perk)
			if r >= max_rank():
				continue
			if r < low_rank:
				lowest = [perk]
				low_rank = r
			elif r == low_rank:
				lowest.append(perk)
		if not lowest.is_empty():
			out.append(lowest[posmod(seed + i, lowest.size())])
	return out


## Points spent in a tree ("ghost"), for synergies.
func tree_points(tree: String) -> int:
	var n := 0
	for perk: String in data.skills["trees"][tree]["perks"]:
		n += rank(perk)
	return n


# --- The one question the rules ask ---------------------------------------------

## The total of `effect` from every skill level and perk rank (0.0 if nothing gives it).
## e.g. bonus("melee_damage") = 0.05 * Strength + 0.04 * Melee + 0.10 * Heavy Swing.
func bonus(effect: String) -> float:
	var total := 0.0
	for s: String in data.skills["skills"]:
		var effects: Dictionary = data.skills["skills"][s].get("effects", {})
		if effects.has(effect):
			total += _amount(effects[effect], effective_level(s))
	for perk: String in perks:
		var r := effective_rank(perk)
		var p: Dictionary = data.skills["perks"].get(perk, {})
		if r <= 0 or p.is_empty():
			continue
		if p["effects"].has(effect):
			total += _amount(p["effects"][effect], r)
		var syn: Dictionary = p.get("synergy", {})
		if syn.get("effects", {}).has(effect):
			total += float(syn["effects"][effect]) * (tree_points(syn["tree"]) / int(syn["every"]))
	if gear != null:
		total += gear.bonus(effect)
	return total


## A skill's level for its effects: the level you earned plus any "+N <skill>" on your gear (M13).
func effective_level(skill: String) -> int:
	return level(skill) + (roundi(gear.bonus(skill)) if gear != null else 0)


## A perk's rank for its effects: the ranks you bought plus "+N to <tree> perks" from gear, but only
## if you bought at least one rank. Can go past perk_max_rank.
func effective_rank(perk: String) -> int:
	var r := rank(perk)
	if r <= 0 or gear == null:
		return r
	return r + roundi(gear.bonus(tree_of(perk) + "_perks"))


func tree_of(perk: String) -> String:
	for t: String in data.skills["trees"]:
		if perk in data.skills["trees"][t]["perks"]:
			return t
	return ""


static func _amount(spec: Variant, n: int) -> float:
	if spec is Dictionary:
		return float(spec["value"]) * (n / int(spec["every"]))
	return float(spec) * n


# --- Saving ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"perks": perks.duplicate(), "perk_points": perk_points}
