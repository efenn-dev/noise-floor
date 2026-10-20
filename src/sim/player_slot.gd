class_name PlayerSlot
extends RefCounted
## Co-op A (docs/COOP_PLAN.md): everything that is one-per-player, in one place, so the sim can hold two (or more)
## players. SimWorld keeps a list of these and its `player`, `inventory`, `gear`, `guns`, `hotbar`, `skills` and
## `player_*` properties read whichever slot is `active`, so the rules written for one player act for any of them.
## Shared things (the world, the base, machines, zombies, the clock, the base log, the Hub) stay on SimWorld.

var name := "You"
var stats: PlayerStats  # health, food, water, energy, stamina, warmth, bleeding, death and respawn
var inventory := Inventory.new()  # pockets
var gear: Gear  # what's worn and held, each piece rolled (Skills.bonus includes it)
var guns: Gunplay  # the gun in hand, its magazine and reloads
var hotbar: Hotbar  # the keys 1-9 and 0
var skills: Skills  # skills that level by doing, perks and the perk tree
var pos := Vector3.ZERO  # where they stand (the world writes it each frame)
var facing := Vector3(0, 0, -1)  # where they look (flat)
var lit := false  # flashlight on
var sneaking := false  # moving while crouched
var vault: Dictionary = {}  # V17: a window climb in progress {key, from, to, elapsed, duration}
var vault_landing := Vector3.INF  # the climb's endpoint, handed to the world for one frame
var clearing_glass: Dictionary = {}  # V17: clearing a broken window's shards {key, elapsed, duration}
var spawn_point := Vector3.ZERO  # where they come back (their bed, or the start)
var respawn_grace := 0.0  # Q6: seconds after a respawn in which zombies take no notice of them
var messages: Array = []  # short notices for their HUD: {text, time_left}
var gathering := ""  # P5: the resource node they're working by hand ("" = none)
var gather_progress := 0.0
var ready_throw := ""  # V30: a throwable readied in the right hand
var perk_snooze_until := 0.0  # P12: no perk pick before this absolute game hour
var combat_at := -100.0  # P12: the game hour of their last swing, shot or hit taken
var perk_reset_day := -1  # P13: the game day they last took a tree's points back


func _init(data: GameData, difficulty: Difficulty, p_name: String) -> void:
	name = p_name
	stats = PlayerStats.new()
	stats.cfg = data.survival
	stats.difficulty = difficulty
	if not data.seasons.is_empty():
		stats.cold_cfg = data.seasons["warmth"]
	hotbar = Hotbar.new(data)
	skills = Skills.new(data)
	gear = Gear.new(data)
	skills.gear = gear  # M13: every bonus(effect) query includes what you wear
	gear.give_start()  # the pipe, white, in the weapon slot
	guns = Gunplay.new(data, gear, skills)
