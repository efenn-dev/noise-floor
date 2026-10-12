class_name Skills
extends RefCounted
## Skills that level by doing, 0-10 (Zomboid style). For now only Mechanics (repairs, mufflers,
## hotwiring); M12 adds the rest on the same table. XP needed per level is in data/skills.json.

var data: GameData
var xp: Dictionary = {}  # skill -> total xp


func _init(p_data: GameData) -> void:
	data = p_data


func level(skill: String) -> int:
	var total := float(xp.get(skill, 0.0))
	var levels: Array = data.skills["levels"]
	var lv := 0
	for i in levels.size():
		if total >= float(levels[i]):
			lv = i
	return lv


## Adds the XP that `action` is worth for `skill` (see data/skills.json). Returns the new level.
func practice(skill: String, action: String) -> int:
	xp[skill] = float(xp.get(skill, 0.0)) + float(data.skills["skills"][skill]["xp"].get(action, 0.0))
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
