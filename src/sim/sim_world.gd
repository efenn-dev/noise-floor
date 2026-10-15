class_name SimWorld
extends RefCounted
## Owns all game-rule state and steps it on a fixed tick, separate from the frame rate.
## The world layer calls update(frame_delta) every frame; rules only ever see TICK-sized steps,
## so the same total time always gives the same result no matter how frames were sliced.

const TICK_RATE := 20
const TICK := 1.0 / TICK_RATE
## Cap per update so a long freeze (debugger, alt-tab) can't snowball into thousands of ticks.
const MAX_TICKS_PER_UPDATE := 10
const PARRY_WINDOW := 0.25  # V15: seconds after raising a guard that a frontal hit is fully stopped
const PARRY_STUN := 0.35
const PARRY_KNOCKBACK := 4.0
## What the HUD says the first time you sit in a car you have no key for.
const NO_KEY_MESSAGE := "No key. The glovebox is searched from the trunk, or try the nearest house"

signal container_searched(id: String)  # V18: the world opens this container's loot screen

var clock: GameClock
var data: GameData
var difficulty: Difficulty
var inventory := Inventory.new()
var build: BuildGrid
var factory: Factory
var horde: Horde
var noise: NoiseField
var power: PowerGrid
## M16: stoves, heaters and the warmth rate (data/seasons.json)
var climate: Climate
var defense: Defense
## M15: sensors and their actions, floodlights, noisemakers, locked doors.
var automation: Automation
## M17a: big projects (the water tower), their sites, phases and what's done
var projects: Projects
## M15: what happened at your base (the last 50 events with game time). L opens it.
var base_log: BaseLog
## M15: radio alerts sent to the HUD (far events while you carry a radio), newest last. For tests.
var radio_lines: Array = []
var _pete_busy := false
## The town's cars: position, fuel (gas cans, siphoned with G), damage, wrecks, and the one you drive.
var vehicles: Vehicles
var hotbar: Hotbar  # S3: the ten slots under keys 1-9 and 0
## Skills that level by doing and the perks they earn (M12). Kept when you die.
var skills: Skills
## V25: saved first-hour objectives and the most recent quick-equip suggestion.
var guidance := Guidance.new()
## M13: your gear (weapon and things you wear, each piece rolled). Skills.bonus() includes it.
var gear: Gear
## M14/V14 slots: what's in your hands (melee, primary or sidearm), spread, magazine and reloads.
var guns: Gunplay
## V30 ballistics live in the fixed sim: crossbow bolts, thrown bottles/bombs and their presentation events.
var projectiles: Array = []
var thrown: Array = []
var projectile_events: Array = []
var projectile_pickups: Dictionary = {}  # container id -> world position for the world pickup view
var embedded_bolts: Dictionary = {}      # zombie id -> recoverable bolts added to its corpse
var ready_throw := ""
var _next_projectile := 1
var _ballistic_rng := RandomNumberGenerator.new()
## For the stats screen: zombies killed (by you, your turrets, traps or your car) and your deaths.
var tally := {"kills": 0, "deaths": 0}  # saved; `stats` below is the per-sitting session log
var _counted_dead: Dictionary = {}
var _day := 1
var director: Director
## Short notices for the HUD ("Moaning to the north..."): {text, time_left}.
var messages: Array = []
## Cars you've already been told have no key (see enter_car).
var _told_no_key := {}
var _told_glass := false  # W2: the first window you break tells you it was loud
var _cold_hour := -1  # M16: the game-hour "You're cold" / "You're freezing" was last said
var loot: Loot
## Storage crates: piece key -> Inventory.
var storages: Dictionary = {}
## Storage crates can hold rolled gear as well as stackable items.
var storage_gear: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var player := PlayerStats.new()
## What happened this session (deaths, builds, loudest sounds...), for the playtest session log.
var stats := RunStats.new()
## Written by the world each frame: where the player stands and whether the flashlight is on.
var player_pos := Vector3.ZERO
## V17: an active scripted window crossing. Rules and timing live here; Player only draws the curve.
## {key, from, to, elapsed, duration}. `vault_landing` hands the exact endpoint to the world for one frame.
var player_vault: Dictionary = {}
var vault_landing := Vector3.INF
## V17: timed E interaction on sharp remnants: {key, elapsed, duration}.
var clearing_glass: Dictionary = {}
## P3: town cell -> house name (from know_houses), so the session log can say which houses you went into.
var house_cells: Dictionary = {}
var player_lit := false
var player_facing := Vector3(0, 0, -1)  # S4: where you look (flat), for the jumpscare rules
var scares: Scares  # S4: jumpscare stings (SoundView plays scares.fired)
var _told_corpse := false  # S4: "dead zombies can be searched", once
## Written by the world each frame: moving while crouched (Sneaking xp near zombies that haven't noticed you).
var player_sneaking := false
var spawn_point := Vector3.ZERO
## Q6: seconds after a respawn during which zombies take no notice of you (data/survival.json "respawn_grace"),
## so dying near your bed doesn't mean dying again the moment you're back. Swinging, shooting or throwing ends it.
var respawn_grace := 0.0
## Bags dropped where the player died: {id: int, pos: Vector3, items: {item: count}}.
var bags: Array = []
var _next_bag := 1
var ticks: int = 0
var seed_value: int = 1
var paused := false
var _accumulator := 0.0


func _init(start_hour: float = 8.0, p_data: GameData = null, p_seed: int = 1,
		p_difficulty: String = Difficulty.DEFAULT) -> void:
	seed_value = p_seed
	clock = GameClock.new(start_hour)
	data = p_data if p_data != null else GameData.load_default()
	difficulty = Difficulty.new(data.difficulty)
	apply_difficulty(p_difficulty)
	build = BuildGrid.new(data)
	factory = Factory.new(data)
	power = PowerGrid.new(data, build, factory)
	climate = Climate.new(data, build, power)
	if not data.seasons.is_empty():
		clock.set_calendar(data.seasons)  # M16: four seasons; sunrise and sunset follow them
		player.cold_cfg = data.seasons["warmth"]
	defense = Defense.new(data, build, factory)
	horde = Horde.new(data, seed_value, difficulty)
	noise = NoiseField.new(data, build)
	director = Director.new(data, seed_value, difficulty)
	loot = Loot.new(data, seed_value, difficulty)
	vehicles = Vehicles.new(data)
	hotbar = Hotbar.new(data)
	scares = Scares.new()
	base_log = BaseLog.new(data, build)
	automation = Automation.new(data, build, power, noise)
	automation.base_log = base_log
	defense.power = power
	defense.base_log = base_log
	projects = Projects.new(data)
	build.projects = projects  # M17a: the water tap can't be built until the tower runs
	director.watch(build)  # M15: the Director's wall counts are cached until the grid changes
	skills = Skills.new(data)
	factory.skills = skills  # belt speed, craft speed, planter yield
	noise.skills = skills    # quieter machines (Dampened Gears)
	power.skills = skills    # quieter generators
	loot.skills = skills     # search time, Lucky Find
	gear = Gear.new(data)
	skills.gear = gear       # M13: every bonus(effect) query includes what you wear
	gear.give_start()        # the pipe, white, in the weapon slot
	guns = Gunplay.new(data, gear, skills)
	defense.gear = gear  # M15: turret suppressors and scopes are gear pieces
	_day = clock.day
	player.cfg = data.survival
	player.difficulty = difficulty
	_rng.seed = hash([seed_value, "sim"])
	_ballistic_rng.seed = hash([seed_value, "v30_ballistics"])
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	build.piece_added.connect(_on_piece_added)
	build.piece_removed.connect(_on_piece_removed)
	build.piece_built.connect(_on_piece_built)


## V29: the single sim entry point for selecting a tuning table. Call before spawning/restoring zombies;
## all participating rules hold this same Difficulty object and read through it.
func apply_difficulty(chosen: String) -> void:
	difficulty.set_id(chosen)


## Starting materials for testing builds (data/debug_kit.json).
func give_debug_kit() -> void:
	inventory.give_all(data.debug_kit)


## Feeds real frame time in; runs as many whole ticks as fit. Returns how many ran.
func update(real_delta: float) -> int:
	if paused:
		return 0
	_accumulator += real_delta
	var ran := 0
	while _accumulator >= TICK and ran < MAX_TICKS_PER_UPDATE:
		_accumulator -= TICK
		step()
		ran += 1
	if ran == MAX_TICKS_PER_UPDATE:
		_accumulator = minf(_accumulator, TICK)
	return ran


## One fixed tick of every rule. New systems (machines, noise, zombies) hook in here.
func step() -> void:
	ticks += 1
	clock.advance(TICK)
	base_log.now = when_text()
	stats.tick(TICK, clock.seconds_per_day)
	if ticks % 10 == 0 and not house_cells.is_empty():
		var house: String = house_cells.get(BuildGrid.world_to_cell(player_pos), "")
		if house != "":
			stats.note_house(house)
	var season := clock.season_cfg()
	var night_now := clock.is_night()
	factory.crop_speed = float(season.get("crop_speed", 1.0))  # M16: winter freezes planters
	factory.rain_speed = float(season.get("rain_speed", 1.0))
	noise.carry_bonus = float(season.get("hearing_night", 0.0)) if night_now else 0.0  # M16: cold, still nights
	power.tick(TICK, clock.daylight())
	climate.tick(TICK, clock.seconds_per_hour())
	_tick_projects()
	factory.tick(TICK)
	vehicles.tick(TICK)
	_tick_hotwire()
	noise.refresh(factory, TICK, power, vehicles)
	noise.continuous.append_array(climate.noise_sources())  # M16: lit stoves crackle
	noise.continuous.append_array(projects.noise_sources())  # M17a: hammering and the tower pump
	_note_noise()
	_tick_first_night()
	player.carry_ratio = carry_ratio()
	player.stamina_regen_mult = 1.0 + skills.bonus("stamina_regen")
	player.heal_mult = 1.0 + skills.bonus("heal_rate")
	var sprinted := player.sprinting and not player.asleep and player.can_sprint()
	player.warmth_rate = climate.warmth_rate(season, night_now, climate.heat_near(player_pos), is_indoors(player_pos),
			player.asleep, skills.bonus("warmth")) / clock.seconds_per_hour() if not data.seasons.is_empty() else 0.0
	_tick_window_actions()
	var was_bleeding := player.bleeding
	player.tick(TICK)
	if was_bleeding and not player.bleeding and not player.dead:
		add_message("The bleeding stopped", 3.0)  # Q5: on its own (a bandage clears it outside the tick)
	_cold_messages()
	guns.tick(TICK, inventory)
	_tick_ballistics(TICK)
	if sprinted:
		_practice("fitness", "sprint_second", TICK)
	if player_sneaking and not player.dead and _unnoticed_zombie_near():
		_practice("sneaking", "sneak_second", TICK)
	var found := loot.tick(TICK, player_pos)
	if not found.is_empty():
		_finish_search(found)
	var night := clock.is_night()
	respawn_grace = maxf(0.0, respawn_grace - TICK)
	var ctx := {"player_pos": player_pos, "player_dead": player.dead or respawn_grace > 0.0, "night": night,
			"player_lit": player_lit or automation.in_light(player_pos), "pieces": build.pieces, "noise": noise}
	for e: Dictionary in horde.tick(TICK, ctx):
		var z: ZombieBrain = horde.zombies.get(e["zombie"])
		if z == null:
			continue
		if e["target"] == "scream":
			noise.emit(z.pos, float(z.stats["scream_loudness"]), "scream")  # pulls in everything nearby
		elif e["target"] == "player" and vehicles.driving != "":
			vehicles.damage(vehicles.driving, z.attack_damage())  # the car takes it while you're inside
			noise.emit_kind(z.pos, "zombie_bash")
		elif e["target"] == "player":
			zombie_hit_player(z)
		elif build.pieces.has(e["target"]):
			var at := z.pos  # the noise is where the zombie stands, not inside the wall it hits
			noise.emit_kind(at, "zombie_bash")  # banging on your walls draws more of them
			var target: String = e["target"]
			if build.player_placeable(build.pieces[target]["id"]):  # M15: your own walls, doors, machines
				base_log.add_once("hit:" + target, float(data.defense["log"]["attack_every"]), "%s under attack: %s" % [
						base_log.place_name(target), _zombies_near(build.piece_center(target))], build.piece_center(target))
			var was_window := build.kind_of(build.pieces[target]["id"]) == "window"
			var structure_damage := zombie_structure_damage(z, target)
			if structure_damage > 0 and build.damage(target, structure_damage):
				noise.emit_kind(build.piece_center(target) if was_window else at, "glass_break" if was_window else "wreck")
	scares.tick(TICK, horde.zombies, player_pos, player_facing, player.dead)  # S4
	defense.tick(TICK, horde, noise)
	automation.tick(TICK, horde, night, defense.bells)
	base_log.tick(TICK)
	if ticks % TICK_RATE == 0:
		_watch_pete()
	var wave := director.tick(TICK, noise, night, horde)
	if stats.is_peak_heat(director.heat):
		stats.note_heat(director.heat, when_text())
	if not director.newly_unlocked.is_empty():
		add_message(director.newly_unlocked["message"], 8.0)
	_count_kills()
	if clock.day != _day:
		_day = clock.day
		_new_day()
	if not wave.is_empty():
		stats.note_wave(wave["kind"], wave["edge"])
		var what: String = {"wanderers": "Something is stirring", "group": "Moaning", "horde": "A horde is coming"}[wave["kind"]]
		add_message("%s from the %s..." % [what, wave["edge"]])
		var label: String = {"wanderers": "Wanderers", "group": "A group", "horde": "A horde"}[wave["kind"]]
		base_log.add("%s coming from the %s: %d zombies" % [label, wave["edge"], wave["size"]],
				Director.EDGES[Director.EDGE_NAMES.find(wave["edge"])])
	_radio()
	guidance.tick(TICK, clock, build, int(tally["deaths"]), player_pos)
	for m: Dictionary in messages:
		m["time_left"] -= TICK
	messages = messages.filter(func(m: Dictionary) -> bool: return m["time_left"] > 0.0)


## M17a: the projects' work, their rewards (rain collectors, water taps) and what they say.
func _tick_projects() -> void:
	var can_work := not player.dead and not player.asleep and vehicles.driving == ""
	for e: Dictionary in projects.tick(TICK, player_pos, can_work, clock.seconds_per_hour(), power):
		var name: String = projects.cfg(e["id"]).get("name", e["id"])
		var site: Vector3 = projects.sites.get(e["id"], player_pos)
		var ph: Dictionary = projects.phases(e["id"])[e["phase"]]
		match e["kind"]:
			"started":
				add_message(e["text"], 8.0)
				base_log.add("%s: phase %d started (%s)" % [name, e["phase"] + 1, str(ph["name"]).to_lower()], site, false)
				stats.note("started %s on the %s" % [str(ph["name"]).to_lower(), name.to_lower()])
			"finished":
				add_message(e["text"], 8.0)
				base_log.add("%s: phase %d of %d done (%s)" % [name, e["phase"] + 1, projects.phases(e["id"]).size(),
						str(ph["name"]).to_lower()], site, false)
			"done":
				base_log.add("%s is running" % name, site, false)
				stats.note("got the %s running" % name.to_lower())
			"paused", "no_power":
				add_message(e["text"], 5.0)
	factory.rain_boost = projects.rain_mult()
	factory.tap_on = projects.is_done("water_tower")


## Delivers what project `id`'s current phase still needs, from your pockets and storage crates within its
## deliver_range of the site. Returns a message.
func project_deliver(id: String) -> String:
	if not projects.sites.has(id):
		return "Nothing here"
	if projects.is_done(id):
		return "Nothing more to deliver"
	if projects.missing(id).is_empty():
		return "It has everything this phase needs: start the work"
	var cfg := projects.cfg(id)
	var site: Vector3 = projects.sites[id]
	var crates := []
	for key: String in storages:
		if build.pieces.has(key) and _flat_dist(build.piece_center(key), site) <= float(cfg["deliver_range"]):
			crates.append(storages[key])
	var moved := projects.deliver(id, Stock.new(inventory, crates))
	if moved.is_empty():
		return "You have none of what it needs (pockets, or a crate within %d m)" % int(cfg["deliver_range"])
	var left := projects.missing(id)
	return "Delivered %s%s" % [_list(moved), (" · still needs " + _list(left)) if not left.is_empty() else " · ready: start the work"]


## Starts the work on project `id`'s current phase. Returns a message.
func project_start(id: String) -> String:
	var why := projects.start_work(id)
	if why != "":
		return why
	var r := float(projects.cfg(id)["work_radius"])
	if _flat_dist(projects.sites.get(id, player_pos), player_pos) > r:
		return "Work started: stand within %d m of it to keep it going" % int(r)
	return "Work started: stay within %d m. It's loud." % int(r)


## M16: "You're cold" / "You're freezing", at most once per game-hour while it lasts.
func _cold_messages() -> void:
	if player.dead or not player.is_cold():
		return
	var hour := clock.day * 24 + int(clock.time_of_day)
	if hour != _cold_hour:
		_cold_hour = hour
		add_message("You're freezing: get to a fire or a heater" if player.is_freezing() else "You're cold", 5.0)


## M16: under a roof: standing on a town floor (a house or the factory hall), as the zombies' "indoors" and
## the indoor fog go by.
func is_indoors(at: Vector3) -> bool:
	return ZombieBrain._indoors(build.pieces, at)


## V29: the Director owns the one-shot dusk/night/morning state; the sim supplies shelter and player noise,
## then turns its events into presentation-neutral messages and a sting request.
func _tick_first_night() -> void:
	var sheltered := guidance.is_sheltered(build, player_pos)
	for event: Dictionary in director.first_night_events(clock, player_pos, sheltered, _player_made_noise(),
			int(tally["deaths"]), horde):
		match str(event["kind"]):
			"warning":
				add_message("It'll be dark at 21:00. Find shelter: a bed inside walls with a door", 10.0)
			"night":
				add_message("Night falls", 4.0)
				scares.fire("night", player_pos)
				var wave: Dictionary = event["wave"]
				stats.note_wave("first_night", "nearby")
				base_log.add("Night falls: %d zombies are closing in" % int(wave["size"]), player_pos)
			"morning":
				add_message("You made it to morning", 6.0)


func _player_made_noise() -> bool:
	for sound: Dictionary in noise.recent:
		if float(sound.get("age", 1.0)) > TICK or sound.get("kind", "") in ["zombie_bash", "scream"]:
			continue
		if _flat_dist(sound["pos"], player_pos) <= 4.0:
			return true
	return false


## M16: E on a stove: loads planks from your pockets and nearby crates. Returns a message.
func stove_interact(key: String) -> String:
	if not climate.stoves.has(key):
		return ""
	var n := climate.load_fuel(key, stock_at(build.piece_center(key)))
	if n > 0:
		return "Loaded %d plank%s" % [n, "s" if n > 1 else ""]
	if climate.stoves[key]["planks"] >= int(data.seasons["stove"]["cap"]):
		return "The stove is full"
	return "No planks to burn"


## M15: the base log's new entries that happened more than radio "far" metres from you go to the HUD as
## "Radio: ..." lines, if you carry a radio.
func _radio() -> void:
	if base_log.fresh.is_empty():
		return
	var cfg: Dictionary = data.defense["radio"]
	var carried := carries_radio()
	for e: Dictionary in base_log.fresh:
		if _flat_dist(e["pos"], player_pos) > float(cfg["far"]):
			stats.note_away(e["text"], e["when"])  # P3: for the session log, radio or not
		if carried and e["radio"] and _flat_dist(e["pos"], player_pos) > float(cfg["far"]):
			radio_lines.append(e["text"])
			add_message("Radio: " + e["text"], float(cfg["seconds"]))
	base_log.fresh = []
	if radio_lines.size() > 20:
		radio_lines = radio_lines.slice(radio_lines.size() - 20)


func carries_radio() -> bool:
	return inventory.count(str(data.defense["radio"]["item"])) > 0


func _zombies_near(at: Vector3) -> String:
	var n := 0
	var r := float(data.defense["log"]["attack_radius"])
	for id: int in horde.zombies:
		if not horde.zombies[id].is_dead() and _flat_dist(horde.zombies[id].pos, at) <= r:
			n += 1
	return "1 zombie" if n == 1 else "%d zombies" % n


## M15: the base log notes Old Pete leaving his spot (chasing, investigating or breaking something).
func _watch_pete() -> void:
	var busy := false
	var at := Vector3.ZERO
	for id: int in horde.zombies:
		var z: ZombieBrain = horde.zombies[id]
		if z.type == "old_pete" and not z.is_dead() and z.state in [ZombieBrain.State.CHASE, ZombieBrain.State.INVESTIGATE,
				ZombieBrain.State.BREAK, ZombieBrain.State.CLIMB, ZombieBrain.State.ATTACK]:
			busy = true
			at = z.pos
	if busy and not _pete_busy:
		base_log.add_once("pete", 120.0, "Old Pete is on the move", at)
	_pete_busy = busy


func add_message(text: String, seconds: float = 6.0) -> void:
	messages.append({"text": text, "time_left": seconds})


## "day 2 21:40": game time, for the session log.
func when_text() -> String:
	return "day %d %s" % [clock.day, clock.clock_text()]


## The session log keeps the loudest one-off sound (new this tick) and the loudest machine or engine.
func _note_noise() -> void:
	for s: Dictionary in noise.recent:
		if s["age"] == 0.0 and stats.is_loudest_sound(s["loudness"]):
			stats.note_sound(s["kind"], s["loudness"], when_text())
	for s: Dictionary in noise.continuous:
		if stats.is_loudest_continuous(s["loudness"]):
			stats.note_continuous(s["kind"], s["loudness"], when_text())


## A one-off sound from the player ("footstep_walk", "footstep_sprint", ...; see data/noise.json).
## Footsteps get louder when you carry more than your limit, and quieter with Sneaking and Soft Step.
## Each step under a heavy load (over heavy_load of your limit) trains Strength.
func make_noise(pos: Vector3, kind: String) -> void:
	noise.emit(pos, noise_loudness(kind), kind)
	if kind.begins_with("footstep") and carry_ratio() > float(data.skills["heavy_load"]):
		_practice("strength", "heavy_step")


## How loud one of your sounds is right now (footsteps depend on load, Sneaking and Soft Step).
func noise_loudness(kind: String) -> float:
	var loudness := float(data.noise["sounds"][kind])
	if kind.begins_with("footstep") and carry_ratio() > 1.0:
		loudness += float(data.survival["carry_footstep_bonus"])
	if kind == "footstep_walk":
		loudness -= skills.bonus("walk_quiet")
	elif kind == "footstep_sprint":
		loudness -= skills.bonus("sprint_quiet")
	if kind.begins_with("footstep") or kind == "melee_hit":
		loudness -= skills.bonus("gear_quiet")  # M13: "N quieter" on gear: your footsteps and swings
	loudness -= skills.bonus("quiet_all")  # M13: the whole Night Shift set: every noise you make
	return maxf(0.0, loudness)


## Chance a zombie's hit makes you bleed: bleed_chance, less 2 points per First Aid level.
func bleed_chance() -> float:
	return maxf(0.0, float(data.survival["bleed_chance"]) - skills.bonus("bleed_cut"))


## V15: resolves one zombie hit against the held guard. Returns the outcome for headless tests and future
## presentation; the ordinary horde path uses the same method. Armour reduces the hit before the guard.
func zombie_hit_player(z: ZombieBrain) -> Dictionary:
	var damage := z.attack_damage() * maxf(0.0, 1.0 - skills.bonus("damage_cut"))
	var result: Dictionary = {"blocked": false, "parried": false, "damage": damage, "stumbled": false}
	var w: Dictionary = weapon_stats()
	if player.blocking and not guns.in_hand() and block_faces(player_facing, player_pos, z.pos) \
			and player.try_block(float(w["block_stamina"])):
		result["blocked"] = true
		result["parried"] = player.block_time <= PARRY_WINDOW
		noise.emit(player_pos, noise_loudness("block"), "block")
		_wear_block_weapon()
		if result["parried"]:
			damage = 0.0
			var parry_factor := float(z.stats.get("parry_stagger_factor", 1.0))
			z.take_hit(0.0, player_pos, PARRY_KNOCKBACK * parry_factor)
			z.stunned = maxf(z.stunned, PARRY_STUN * parry_factor)
			add_message("Parried", 0.8)
		else:
			var block_factor := float(z.stats.get("block_factor", 1.0))
			damage *= maxf(0.0, 1.0 - float(w["block_reduction"]) * block_factor)
	result["damage"] = damage
	player.damage(damage, z.type)
	if damage > 0.0 and not player.dead:
		if z.stats.has("stumble_time"):
			player.stumble(float(z.stats["stumble_time"]), float(z.stats["stumble_slow"]))
			result["stumbled"] = true
		var shove := float(z.stats.get("player_knockback", 0.0))
		var away := Vector3(player_pos.x - z.pos.x, 0.0, player_pos.z - z.pos.z)
		if shove > 0.0 and away.length_squared() > 1e-6:
			player.knockback += away.normalized() * shove
	if damage > 0.0 and not player.dead and _rng.randf() < bleed_chance():
		if not player.bleeding:
			add_message("You're bleeding (H to bandage)", 4.0)
		player.start_bleeding()
	return result


## V28: brute structure strength and the crawler's refusal to attack doors are data-driven.
func zombie_structure_damage(z: ZombieBrain, key: String) -> int:
	if not build.pieces.has(key):
		return 0
	var kind := build.kind_of(build.pieces[key]["id"])
	var factor := float(z.stats.get("break_multiplier", 1.0))
	if kind == "door":
		factor = float(z.stats.get("door_break_multiplier", factor))
	return maxi(0, roundi(z.structure_damage() * factor))  # V29: scaled by the difficulty


## The attacker must be within 70 degrees of the player's flat look direction.
static func block_faces(facing: Vector3, player_at: Vector3, attacker_at: Vector3) -> bool:
	var look := Vector2(facing.x, facing.z)
	var to_attacker := Vector2(attacker_at.x - player_at.x, attacker_at.z - player_at.z)
	if look.length_squared() <= 1e-6 or to_attacker.length_squared() <= 1e-6:
		return false
	return look.normalized().dot(to_attacker.normalized()) >= cos(deg_to_rad(70.0))


## A block uses the same per-weapon wear and break path as a landed swing.
func _wear_block_weapon() -> void:
	var name := gear.weapon_name()
	match gear.wear_weapon(skills.bonus("wear_cut")):
		"worn":
			add_message("Your %s is worn out: its bonuses stop, and it'll break soon (repair kit from the Press)" % name, 6.0)
		"broke":
			add_message("Your %s broke while blocking! Find another weapon" % name, 7.0)
			noise.emit(player_pos, noise_loudness("weapon_break"), "weapon_break")
			stats.note("broke a " + name.to_lower())


func _unnoticed_zombie_near() -> bool:
	var reach := float(data.skills["sneak_range"])
	var calm := [ZombieBrain.State.IDLE, ZombieBrain.State.WANDER, ZombieBrain.State.INVESTIGATE]
	for id: int in horde.zombies:
		var z: ZombieBrain = horde.zombies[id]
		if z.state in calm and _flat_dist(z.pos, player_pos) <= reach:
			return true
	return false


# --- Window vaulting and glass -------------------------------------------------

## Fitness is the existing agility-like skill: 3% off per level, capped so the motion stays readable.
func vault_duration() -> float:
	return float(data.survival["vault_seconds"]) * maxf(0.65, 1.0 - skills.bonus("vault_speed"))


func vault_fraction() -> float:
	if player_vault.is_empty():
		return 0.0
	return clampf(float(player_vault["elapsed"]) / maxf(0.001, float(player_vault["duration"])), 0.0, 1.0)


## A prompt/action only counts when the player is beside the opening, not merely inside the 4 m look ray.
func window_in_reach(key: String) -> bool:
	return build.is_broken(key) and _flat_dist(player_pos, build.piece_center(key)) <= float(data.survival["vault_reach"])


## Why Space cannot begin this vault. Empty means it is legal.
func vault_reason(key: String) -> String:
	if not build.is_broken(key):
		return "Only a broken window can be climbed"
	if not window_in_reach(key):
		return "Move closer to the window"
	if not player_vault.is_empty():
		return "Already climbing"
	if player.dead or player.asleep:
		return "You can't climb now"
	if player.aiming or guns.aiming:
		return "Lower your aim before climbing"
	if guns.reloading > 0.0:
		return "Finish reloading before climbing"
	if player.swing_cooldown > 0.0:
		return "Finish the swing before climbing"
	if player.blocking:
		return "Lower your guard before climbing"
	if carry_ratio() > 1.0:
		return "Too over-encumbered to climb"
	if player.stamina < float(data.survival["vault_stamina"]):
		return "Too tired to climb"
	return ""


## Starts a deterministic crossing from the player's side of the frame to a safe point on the other side.
## Returns "" or the reason it did not start.
func start_vault(key: String) -> String:
	var why := vault_reason(key)
	if why != "":
		return why
	var piece: Dictionary = build.pieces[key]
	var center := build.piece_center(key)
	center.y = player_pos.y
	var yaw := build.yaw_for(piece["id"], piece["cell"], piece["side"])
	var normal := Basis(Vector3.UP, deg_to_rad(yaw)).z
	var side := 1.0 if (player_pos - center).dot(normal) >= 0.0 else -1.0
	var clearance := float(data.survival["vault_clearance"])
	var landing := center - normal * side * clearance
	if not player.try_vault(float(data.survival["vault_stamina"])):
		return "Too tired to climb"
	player.sprinting = false
	player.set_blocking(false)
	clearing_glass = {}
	vault_landing = Vector3.INF
	player_vault = {"key": key, "from": player_pos, "to": landing, "elapsed": 0.0, "duration": vault_duration()}
	noise.emit_kind(center, "vault")
	if build.has_shards(key):
		player.damage(float(data.survival["vault_cut_damage"]), "glass")
		if not player.dead:
			player.bleeding = true
			add_message("The glass cut you — you're bleeding (H to bandage)", 5.0)
	return ""


## Screenshot-only positioning uses the same state and curve without advancing the sim clock.
func set_vault_fraction(fraction: float) -> void:
	if not player_vault.is_empty():
		player_vault["elapsed"] = float(player_vault["duration"]) * clampf(fraction, 0.0, 1.0)
		player_pos = (player_vault["from"] as Vector3).lerp(player_vault["to"] as Vector3, vault_fraction())


## Starts clearing sharp glass. An equipped melee weapon (not bare fists or a gun in hand) is faster.
func start_clear_glass(key: String) -> String:
	if not build.is_broken(key):
		return "The window is not broken"
	if not window_in_reach(key):
		return "Move closer to the window"
	if player.dead or player.asleep:
		return "You can't clear glass now"
	if not player_vault.is_empty():
		return "Finish climbing first"
	if not build.has_shards(key):
		return "The glass is already cleared"
	if not clearing_glass.is_empty():
		return "Clearing the glass..." if clearing_glass.get("key", "") == key else "Already clearing another window"
	var duration := float(data.survival["clear_glass_seconds"])
	if guns.hands == "melee" and gear.equipped.get("weapon") is Dictionary:
		duration *= float(data.survival["clear_glass_weapon_mult"])
	clearing_glass = {"key": key, "elapsed": 0.0, "duration": duration}
	return "Clearing the glass..."


func clear_glass_fraction() -> float:
	if clearing_glass.is_empty():
		return 0.0
	return clampf(float(clearing_glass["elapsed"]) / maxf(0.001, float(clearing_glass["duration"])), 0.0, 1.0)


func _tick_window_actions() -> void:
	if not player_vault.is_empty():
		player_vault["elapsed"] = minf(float(player_vault["duration"]), float(player_vault["elapsed"]) + TICK)
		var k := smoothstep(0.0, 1.0, vault_fraction())
		player_pos = (player_vault["from"] as Vector3).lerp(player_vault["to"] as Vector3, k)
		if float(player_vault["elapsed"]) >= float(player_vault["duration"]):
			vault_landing = player_vault["to"] as Vector3
			player_pos = vault_landing
			player_vault = {}
	if clearing_glass.is_empty():
		return
	var key: String = clearing_glass["key"]
	if not build.has_shards(key) or not window_in_reach(key):
		clearing_glass = {}
		return
	clearing_glass["elapsed"] = float(clearing_glass["elapsed"]) + TICK
	if float(clearing_glass["elapsed"]) < float(clearing_glass["duration"]):
		return
	clearing_glass = {}
	if build.clear_shards(key):
		noise.emit_kind(build.piece_center(key), "glass_clear")
		add_message("Glass cleared — the frame is safe to climb", 3.0)


# --- Carrying ---------------------------------------------------------------

## Carry limit in kg: carry_base, plus 3 kg per Strength level (skills.json), plus the bag worn on back.
func carry_limit() -> float:
	var bag := str(gear.equipped.get("back", ""))
	return float(data.survival["carry_base"]) + skills.bonus("carry_kg") + data.item_value(bag, "bag")


func carry_ratio() -> float:
	return carried_kg() / carry_limit()


## What you carry in kg: your pockets' items plus the gear pieces in them (worn gear doesn't count).
func carried_kg() -> float:
	return inventory.weight(data) + gear.weight()


## V18: the right-hand inventory behind either a searched world container or a built storage crate.
func container_inventory(id: String) -> Inventory:
	if storages.has(id):
		return storages[id]
	if loot.containers.has(id) and loot.containers[id]["searched"]:
		return loot.inventory(id)
	return null


func container_gear(id: String) -> Array:
	if storage_gear.has(id):
		return storage_gear[id]
	if loot.containers.has(id) and loot.containers[id]["searched"]:
		return loot.containers[id]["gear"]
	return []


func container_exists(id: String) -> bool:
	return storages.has(id) or (loot.containers.has(id) and loot.containers[id]["searched"])


func container_in_reach(id: String) -> bool:
	if storages.has(id):
		return build.pieces.has(id) and _flat_dist(build.piece_center(id), player_pos) <= float(data.survival["crate_reach"])
	return loot.in_reach(id, player_pos)


func container_name(id: String) -> String:
	if storages.has(id):
		return "Crate"
	if id.begins_with(CORPSE):
		return "Corpse"
	if loot.containers.has(id):
		var table := str(loot.containers[id]["table"])
		return "Trunk" if table == "car_trunk" else loot.display_name(id)
	return "Container"


## Moves a stack between a searched container and pockets. Taking stops at the carry limit.
## Returns {moved, left, why}; `left` is the requested amount that could not move.
func move_container_item(id: String, item: String, amount: int, to_pockets: bool) -> Dictionary:
	var box := container_inventory(id)
	if box == null:
		return {"moved": 0, "left": maxi(0, amount), "why": "Container closed"}
	if not container_in_reach(id):
		return {"moved": 0, "left": maxi(0, amount), "why": "Too far away"}
	var from := box if to_pockets else inventory
	var to := inventory if to_pockets else box
	var wanted := mini(maxi(0, amount), from.count(item))
	var allowed := wanted
	if to_pockets:
		var each := data.item_weight(item)
		if each > 0.0:
			allowed = mini(allowed, maxi(0, floori((carry_limit() - carried_kg() + 0.001) / each)))
	var moved := from.move_to(to, item, allowed)
	var left := wanted - moved
	return {"moved": moved, "left": left, "why": "Too heavy" if left > 0 and to_pockets else ""}


func can_take_container_item(id: String, item: String, amount: int) -> String:
	var box := container_inventory(id)
	if box == null:
		return "Container closed"
	if not container_in_reach(id):
		return "Too far away"
	var wanted := mini(maxi(0, amount), box.count(item))
	if wanted <= 0:
		return "Nothing to take"
	return "Too heavy" if carried_kg() + data.item_weight(item) * wanted > carry_limit() + 0.001 else ""


## Moves one rolled gear piece between a searched container and pockets.
func move_container_gear(id: String, uid: int, to_pockets: bool) -> Dictionary:
	if not container_exists(id):
		return {"moved": false, "why": "Container closed"}
	if not container_in_reach(id):
		return {"moved": false, "why": "Too far away"}
	var held := container_gear(id)
	if to_pockets:
		for i in held.size():
			var piece: Dictionary = held[i]
			if int(piece["uid"]) != uid:
				continue
			if carried_kg() + gear.piece_weight(piece) > carry_limit() + 0.001:
				return {"moved": false, "why": "Too heavy"}
			held.remove_at(i)
			gear.pieces.append(piece)
			_consider_better_gear(piece)
			return {"moved": true, "why": ""}
		return {"moved": false, "why": "Nothing to take"}
	var piece := gear.take(uid)
	if piece.is_empty():
		return {"moved": false, "why": "You don't have that"}
	held.append(piece)
	return {"moved": true, "why": ""}


## V27 (Emmitt: "we can't immediately equip items, it has to go to inventory before being equipped"): "" if
## the gear piece `uid` in the open container `id` can be worn straight into `slot` ("" = its own slot),
## otherwise why not. Worn gear doesn't count toward carry weight, so only an old piece coming off can be a
## weight problem, and that one just stays in the container instead.
func can_equip_from_container(id: String, uid: int, slot: String = "") -> String:
	if not container_exists(id):
		return "Container closed"
	if not container_in_reach(id):
		return "Too far away"
	for piece: Dictionary in container_gear(id):
		if int(piece["uid"]) != uid:
			continue
		var own := gear.slot_of(piece)
		if own == "part":
			return "Fit it on a gun"
		if slot != "" and slot != own:
			return "Doesn't fit that slot"
		return ""
	return "Nothing to take"


## V27: wears the gear piece `uid` straight out of the open container `id`. What you wore in that slot goes
## into your pockets, or back into the container if your pockets can't take it. Returns a message.
func equip_from_container(id: String, uid: int, slot: String = "") -> String:
	var why := can_equip_from_container(id, uid, slot)
	if why != "":
		return why
	var held := container_gear(id)
	var piece := {}
	for i in held.size():
		if int(held[i]["uid"]) == uid:
			piece = held[i]
			held.remove_at(i)
			break
	var own := gear.slot_of(piece)
	var old: Variant = gear.equipped.get(own)
	gear.pieces.append(piece)
	why = gear.equip(uid)
	if why != "":
		gear.take(uid)
		held.append(piece)
		return why
	if old is Dictionary and carried_kg() > carry_limit() + 0.001:
		var taken := gear.take(int((old as Dictionary)["uid"]))
		held.append(taken)
		return "Equipped %s (your %s stayed in the %s: too heavy to carry)" % [piece["name"], taken["name"],
				container_name(id).to_lower()]
	return "Equipped " + String(piece["name"])


func can_take_container_gear(id: String, uid: int) -> String:
	if not container_exists(id):
		return "Container closed"
	if not container_in_reach(id):
		return "Too far away"
	for piece: Dictionary in container_gear(id):
		if int(piece["uid"]) == uid:
			return "Too heavy" if carried_kg() + gear.piece_weight(piece) > carry_limit() + 0.001 else ""
	return "Nothing to take"


## Takes every stack and gear piece that fits. What remains is reported for the HUD.
func take_all(id: String) -> Dictionary:
	var box := container_inventory(id)
	var out := {"items": {}, "gear": [], "not_fit": {}, "gear_not_fit": []}
	if box == null or not container_in_reach(id):
		return out
	for item: String in box.items():
		var before := box.count(item)
		var moved: Dictionary = move_container_item(id, item, before, true)
		if moved["moved"] > 0:
			out["items"][item] = moved["moved"]
		if moved["left"] > 0:
			out["not_fit"][item] = moved["left"]
	for piece: Dictionary in container_gear(id).duplicate():
		var moved := move_container_gear(id, int(piece["uid"]), true)
		if moved["moved"]:
			out["gear"].append(piece["name"])
		else:
			out["gear_not_fit"].append(piece["name"])
	return out


## Your pockets plus every storage crate within storage_range of `at`: what building and hand-feeding use.
func stock_at(at: Vector3) -> Stock:
	var crates := []
	var reach := float(data.survival["storage_range"])
	for key: String in storages:
		if build.pieces.has(key) and _flat_dist(build.piece_center(key), at) <= reach:
			crates.append(storages[key])
	return Stock.new(inventory, crates)


## Puts every building material you carry (not food, drink, bandages or bags) into a storage crate.
func deposit(key: String) -> Dictionary:
	if not storages.has(key):
		return {}
	stats.note_crate()
	var moved := {}
	for item: String in inventory.items():
		if _is_supply(item):
			continue
		moved[item] = inventory.count(item)
	if not moved.is_empty():
		inventory.take_all(moved)
		storages[key].give_all(moved)
	return moved


## Puts the debug kit in a new storage crate on a new foundation at `cell` (the start-of-game stash).
func place_start_stash(cell: Vector2i) -> String:
	var was_muted := stats.muted
	stats.muted = true  # the game set this up, not the player
	var key := _place_start_stash(cell)
	stats.muted = was_muted
	return key


## Lays the town's houses (TownPlan.generate) into the build grid as if built: floors, walls, doors,
## windows and a bed per house, at full hp, free, and not counted as the player's builds.
## Containers aren't pieces: the world registers them (they need bodies). Returns pieces placed.
func place_town(plan: Dictionary) -> int:
	var was_muted := stats.muted
	stats.muted = true
	var n := 0
	for p: Dictionary in plan["pieces"]:
		build.restore(TownPlan.piece_key(p), {"id": p["id"], "cell": p["cell"], "side": p["side"],
				"hp": data.buildables[p["id"]]["hp"], "town": true})  # P3: town pieces salvage, they don't refund
		n += 1
	for b: Dictionary in plan["beds"]:
		build.restore(build.key_for("bed", b["cell"]), {"id": "bed", "cell": b["cell"], "side": b["side"],
				"hp": data.buildables["bed"]["hp"], "town": true})
		n += 1
	stats.muted = was_muted
	return n


## W1b: lays the factory hall (TownPlan.factory, in plan["factory"]) the same way: floor, walls, windows,
## and an open doorway on the road end. Returns pieces placed.
func place_factory(plan: Dictionary) -> int:
	var was_muted := stats.muted
	stats.muted = true
	var n := 0
	for p: Dictionary in plan["factory"]["pieces"]:
		build.restore(TownPlan.piece_key(p), {"id": p["id"], "cell": p["cell"], "side": p["side"],
				"hp": data.buildables[p["id"]]["hp"], "town": true})
		n += 1
	stats.muted = was_muted
	return n


## W1c: lays the town's furniture (plan["props"], and plan["factory"]["props"]) as pieces, like place_town.
## A spot is skipped if something already stands on that cell, its floor is gone, or a zombie stands in it:
## that only happens when furnishing a loaded pre-W1c save, where the player may have built in a house.
## Returns pieces placed.
func place_props(plan: Dictionary) -> int:
	var was_muted := stats.muted
	stats.muted = true
	var n := 0
	for p: Dictionary in plan["props"] + plan["factory"].get("props", []):
		var key := build.key_for(p["id"], p["cell"])
		if build.pieces.has(key) or not build.pieces.has("f:%d:%d" % [p["cell"].x, p["cell"].y]):
			continue
		var taken := false
		for z: ZombieBrain in horde.zombies.values():
			taken = taken or BuildGrid.world_to_cell(z.pos) == p["cell"]
		if taken:
			continue
		build.restore(key, {"id": p["id"], "cell": p["cell"], "side": p["side"], "hp": data.buildables[p["id"]]["hp"],
				"town": true})
		n += 1
	stats.muted = was_muted
	return n


## A1: the street's trash cans (StreetPlan "trash_can" items) are searchable "trash" containers, like the
## fridges. The rest of the street plan is scenery with no rule. Returns how many were registered.
func place_street(street: Dictionary) -> int:
	var n := 0
	for item: Dictionary in street["items"]:
		if item["kind"] == "trash_can":
			loot.add(item["id"], "trash", item["pos"] + Vector3(0, 0.5, 0))
			n += 1
	return n


## M17a: the industrial park (ParkPlan.generate). Lays the warehouses' pieces like place_factory unless
## `lay_pieces` is false (a save that already holds them), and always registers what isn't a piece: the
## warehouse crates (loot table "industrial"), the wrecked cars on the park road (searchable trunks, gas to
## siphon, never drivable) and the water tower's project site. Returns pieces laid.
func place_park(plan: Dictionary, lay_pieces: bool = true) -> int:
	var was_muted := stats.muted
	stats.muted = true
	var n := 0
	if lay_pieces:
		for p: Dictionary in plan["pieces"]:
			build.restore(TownPlan.piece_key(p), {"id": p["id"], "cell": p["cell"], "side": p["side"],
					"hp": data.buildables[p["id"]]["hp"], "town": true})
			n += 1
	for c: Dictionary in plan["crates"]:
		loot.add(c["id"], c["table"], park_crate_pos(c))
	for w: Dictionary in plan["wrecks"]:
		var size: Array = data.vehicles[w["type"]]["size"]
		var pos: Vector3 = w["pos"] + Vector3(0, float(size[1]) / 2.0, 0)
		loot.add(w["id"], "car_trunk", pos)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, w["id"], "fuel"])
		vehicles.add(w["id"], w["type"], pos, w["yaw"], rng.randi_range(0, 2), "Burned out: nothing left to drive", "lost")
		loot.containers[w["id"]]["pos"] = vehicles.trunk_pos(w["id"])
	projects.add_site("water_tower", plan["tower"]["pos"])
	stats.muted = was_muted
	return n


## Where a park crate stands: against its wall, like a town container (a 1.2 x 1.0 x 1.0 crate).
static func park_crate_pos(c: Dictionary) -> Vector3:
	return town_container_pos(c, 1.0, 1.0)


## M17a: the park's zombies (plan["zombies"]: shamblers and runners inside and between the warehouses).
## Only for a new game, or a save from before the park; a save brings its own back.
func spawn_park_zombies(plan: Dictionary) -> Array:
	var ids: Array = []
	var planned: Array = plan["zombies"]
	if planned.is_empty():
		return ids
	var count := difficulty.count("zombie_count", planned.size())
	for i in count:
		var pz: Dictionary = planned[i % planned.size()]
		var z := horde.spawn(pz["type"], pz["pos"])
		if i >= planned.size():
			z.pos += Vector3(float(i) / float(planned.size()) + 1.0, 0.0, 0.5)
			z.home = z.pos
			z.target_pos = z.pos
		z.facing = pz["facing"]
		ids.append(z.id)
	return ids


## W1b/V28: one starting zombie in each house the plan picked (plan["zombies"]), facing its front door;
## the data-driven indoor mix has more crawlers. Only a new game: a save brings its own zombies back.
func spawn_house_zombies(plan: Dictionary) -> Array:
	var ids: Array = []
	var planned: Array = plan["zombies"]
	if planned.is_empty():
		return ids
	var count := difficulty.count("zombie_count", planned.size())
	for i in count:
		var hz: Dictionary = planned[i % planned.size()]
		var z := horde.spawn_starting(hz["pos"], true)
		if i >= planned.size():
			z.pos += Vector3(0.45, 0.0, 0.45)
			z.home = z.pos
			z.target_pos = z.pos
		z.facing = hz["facing"]
		ids.append(z.id)
	return ids


## Where a town container stands: against its wall in its cell, on the floor (y = its middle).
static func town_container_pos(c: Dictionary, height: float = 1.6, depth: float = 0.7) -> Vector3:
	var g := BuildGrid.GRID
	var out := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][c["side"]] as Vector2
	var push := g / 2.0 - 0.1 - depth / 2.0 - 0.02  # to the wall's inner face
	return Vector3((c["cell"].x + 0.5) * g + out.x * push, 0.1 + height / 2.0, (c["cell"].y + 0.5) * g + out.y * push)


func _place_start_stash(cell: Vector2i) -> String:
	var kit := Inventory.new()
	kit.give_all(data.debug_kit)
	kit.give_all({"plank": 12, "nails": 8})  # pays for the foundation and crate themselves
	if build.place("foundation", cell, BuildGrid.Side.NORTH, kit) != "":
		return ""
	if build.place("storage", cell, BuildGrid.Side.WEST, kit) != "":
		return ""
	var key := build.key_for("storage", cell)
	storages[key].give_all(_counts_of(kit))
	storages[key].add(str(data.defense["radio"]["item"]), 1)  # M15: the handheld radio
	return key


## Storage crates within arm's reach (crate_reach) of `at`, nearest first: what the inventory screen shows.
func crates_near(at: Vector3) -> Array:
	var reach := float(data.survival["crate_reach"])
	var found := []
	for key: String in storages:
		if build.pieces.has(key):
			var d := _flat_dist(build.piece_center(key), at)
			if d <= reach:
				found.append([d, key])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return found.map(func(e: Array) -> String: return e[1])


## V34 (Emmitt: "skins for the items dropped, also allow placing items"): a dropped or placed thing lies in the
## world as itself (kind "item": one item stack or one gear piece, drawn with its own model and turned to `yaw`),
## not in a bag. Death bags stay bags (kind "bag"). Both live in `bags`, are picked up with E (take_bag) and saved.
const ITEM := "item"
const BAG := "bag"
const DROP_AHEAD := 0.55   # how far in front of your feet a dropped thing lands
const STACK_REACH := 0.45  # a drop this close to the same item lying there joins its stack
const PLACE_REACH := 3.0   # how far from your feet (across the floor) you can place something
const PLACE_HEIGHT := 2.4  # and how high above them (a shelf, a counter, a table)


## Drops items from your pockets on the floor in front of you, as themselves; the same item dropped on the
## same spot again joins that stack. Pick it back up with E. Returns a message.
func drop_items(item: String, amount: int) -> String:
	var n := mini(amount, inventory.count(item))
	if n <= 0:
		return "Nothing to drop"
	inventory.remove(item, n)
	var at := _drop_spot()
	for lying: Dictionary in bags:
		if lying.get("kind", BAG) == ITEM and lying["gear"].is_empty() and lying["items"].has(item) 				and _flat_dist(lying["pos"], at) <= STACK_REACH:
			lying["items"][item] = int(lying["items"][item]) + n
			return "Dropped %d %s" % [n, data.item_name(item)]
	_lay(at, player_yaw(), {item: n}, [])
	return "Dropped %d %s" % [n, data.item_name(item)]


## M13: drops a gear piece from your pockets on the floor in front of you (V34: as itself). Returns a message.
func drop_gear(uid: int) -> String:
	var piece := gear.take(uid)
	if piece.is_empty():
		return "Nothing to drop"
	_lay(_drop_spot(), player_yaw(), {}, [piece])
	return "Dropped " + piece["name"]


## V34: puts one `item` from your pockets exactly at `at` (a surface the world found under your crosshair),
## turned to `yaw` radians. Returns "" or why not.
func place_item(item: String, at: Vector3, yaw: float) -> String:
	if inventory.count(item) <= 0:
		return "No %s left" % data.item_name(item).to_lower()
	var why := _why_not_place(at)
	if why != "":
		return why
	inventory.remove(item, 1)
	_lay(at, yaw, {item: 1}, [])
	return ""


## V34: puts a gear piece from your pockets exactly at `at`, turned to `yaw`. Returns "" or why not.
func place_gear(uid: int, at: Vector3, yaw: float) -> String:
	if gear.find(uid).is_empty():
		return "That's not in your pockets"
	var why := _why_not_place(at)
	if why != "":
		return why
	_lay(at, yaw, {}, [gear.take(uid)])
	return ""


func _why_not_place(at: Vector3) -> String:
	if not at.is_finite():
		return "Nowhere to put it"
	if not player_vault.is_empty() or vehicles.driving != "" or player.dead:
		return "Not now"
	if _flat_dist(at, player_pos) > PLACE_REACH or at.y - player_pos.y > PLACE_HEIGHT:
		return "Too far away"
	return ""


## V34: which way you face, as a yaw in radians (0 = north, -Z), for things you drop.
func player_yaw() -> float:
	return atan2(-player_facing.x, -player_facing.z)


func _drop_spot() -> Vector3:
	var ahead := Vector3(player_facing.x, 0.0, player_facing.z)
	ahead = ahead.normalized() * DROP_AHEAD if ahead.length_squared() > 1e-6 else Vector3.ZERO
	return player_pos + ahead


func _lay(at: Vector3, yaw: float, items: Dictionary, pieces: Array) -> void:
	bags.append({"id": _next_bag, "pos": at, "items": items, "gear": pieces, "kind": ITEM, "yaw": yaw})
	_next_bag += 1


## V34: what you see when you look at bag `id` lying on the ground: "Your bag", a gear piece's name, or
## "12 Nails". "" if there's no such bag.
func lying_name(id: int) -> String:
	for lying: Dictionary in bags:
		if lying["id"] != id:
			continue
		if lying.get("kind", BAG) != ITEM:
			return "Your bag"
		if not (lying["gear"] as Array).is_empty():
			return str(lying["gear"][0].get("name", "Gear"))
		var item := lying_look(lying)
		var n := int(lying["items"].get(item, 0))
		return data.item_name(item) if n == 1 else "%d %s" % [n, data.item_name(item)]
	return ""


## V34: what a thing lying on the ground is: its item id, or a gear piece's base, for its model and name.
static func lying_look(lying: Dictionary) -> String:
	if lying.get("kind", BAG) != ITEM:
		return BAG
	if not (lying["gear"] as Array).is_empty():
		return str(lying["gear"][0].get("base", ""))
	return str((lying["items"] as Dictionary).keys()[0]) if not (lying["items"] as Dictionary).is_empty() else ""


func equip_gear(uid: int) -> String:
	var piece := gear.find(uid)
	if piece.is_empty():
		return "You don't have that"
	if gear.slot_of(piece) == "part":
		return "Select a firearm, then fit this part in its modding panel"
	var why := can_equip_gear(uid, gear.slot_of(piece))
	if why != "":
		return why
	why = gear.equip(uid)
	if why != "":
		return why
	stats.note_gear_equipped("%s (%s)" % [piece["name"], piece["rarity"]])
	if guidance.better_gear_uid == uid:
		guidance.clear_better_gear()
	return "Equipped " + piece["name"]


## Y: wear the last acquired piece that was an upgrade. It is compared again, so changing gear cannot
## accidentally replace a newer, better piece with an old suggestion.
func quick_equip_better() -> String:
	var uid := guidance.better_gear_uid
	var piece := gear.find(uid)
	if uid < 0 or piece.is_empty() or gear.is_equipped(uid):
		guidance.clear_better_gear()
		return "No better gear ready"
	var slot := gear.slot_of(piece)
	var value: Variant = gear.equipped.get(slot)
	var current: Dictionary = value if value is Dictionary else {}
	if not gear.is_better(piece, current):
		guidance.clear_better_gear()
		return "That piece is no longer better"
	return equip_gear(uid)


func _consider_better_gear(piece: Dictionary) -> void:
	var slot := gear.slot_of(piece)
	var value: Variant = gear.equipped.get(slot)
	var current: Dictionary = value if value is Dictionary else {}
	if gear.is_better(piece, current):
		guidance.note_better_gear(int(piece["uid"]))


## Checks a drag from pockets onto a character slot without changing either side.
func can_equip_gear(uid: int, slot: String) -> String:
	var piece := gear.find(uid)
	if piece.is_empty() or gear.is_equipped(uid):
		return "You don't have that"
	if gear.slot_of(piece) != slot or slot == "part":
		return "Doesn't fit that slot"
	var old: Variant = gear.equipped.get(slot)
	var final_kg := carried_kg() - gear.piece_weight(piece)
	if old is Dictionary:
		final_kg += gear.piece_weight(old)
	var had := gear.equipped.has(slot)
	gear.equipped[slot] = piece
	var limit := carry_limit()
	if had:
		gear.equipped[slot] = old
	else:
		gear.equipped.erase(slot)
	# only refuse when the swap makes you heavier: putting on what you carry always lightens your pockets
	return "Too heavy" if final_kg > limit + 0.001 and final_kg > carried_kg() + 0.001 else ""


func equip_gear_to_slot(uid: int, slot: String) -> String:
	var why := can_equip_gear(uid, slot)
	return why if why != "" else equip_gear(uid)


## Wears one stackable bag item on the back. The old bag goes to pockets.
func equip_bag(item: String) -> String:
	if data.item_value(item, "bag") <= 0.0:
		return "That isn't a bag"
	if inventory.count(item) <= 0:
		return "You don't have that"
	var old := str(gear.equipped.get("back", ""))
	var final_kg := carried_kg() - data.item_weight(item) + data.item_weight(old)
	var had := gear.equipped.has("back")
	gear.equipped["back"] = item
	var limit := carry_limit()
	if had:
		gear.equipped["back"] = old
	else:
		gear.equipped.erase("back")
	if final_kg > limit + 0.001:
		return "Too heavy"
	inventory.remove(item, 1)
	gear.equipped["back"] = item
	stats.note_gear_equipped(data.item_name(item))
	var suffix := _stow_bag(old)
	return "Equipped %s%s" % [data.item_name(item), suffix]


func can_equip_item(item: String, slot: String) -> String:
	if slot != "back" or data.item_value(item, "bag") <= 0.0:
		return "Doesn't fit that slot"
	if inventory.count(item) <= 0:
		return "You don't have that"
	var old := str(gear.equipped.get("back", ""))
	var final_kg := carried_kg() - data.item_weight(item) + data.item_weight(old)
	var had := gear.equipped.has("back")
	gear.equipped["back"] = item
	var limit := carry_limit()
	if had:
		gear.equipped["back"] = old
	else:
		gear.equipped.erase("back")
	return "Too heavy" if final_kg > limit + 0.001 else ""


func equip_item_to_slot(item: String, slot: String) -> String:
	var why := can_equip_item(item, slot)
	return why if why != "" else equip_bag(item)


func unequip_gear(slot: String) -> String:
	var why := can_unequip_gear(slot)
	if why != "":
		return why
	if slot == "back":
		return _unequip_bag()
	var piece: Dictionary = gear.equipped.get(slot, {})
	why = gear.unequip(slot)
	return why if why != "" else "Took off " + piece["name"]


func can_unequip_gear(slot: String) -> String:
	if not gear.equipped.has(slot):
		return "Nothing there"
	var value: Variant = gear.equipped[slot]
	if slot == "back":
		var bag := str(value)
		gear.equipped.erase(slot)
		var fits := carried_kg() + data.item_weight(bag) <= carry_limit() + 0.001
		gear.equipped[slot] = value
		return "" if fits else "Too heavy"
	if not value is Dictionary:
		return "Nothing there"
	gear.equipped.erase(slot)
	var fits := carried_kg() + gear.piece_weight(value) <= carry_limit() + 0.001
	gear.equipped[slot] = value
	return "" if fits else "Too heavy"


func _unequip_bag() -> String:
	var item := str(gear.equipped.get("back", ""))
	if item == "":
		return "Nothing there"
	gear.equipped.erase("back")
	var suffix := _stow_bag(item)
	return "Took off %s%s" % [data.item_name(item), suffix]


## Returns a message suffix. The capacity bonus is already whatever the currently worn bag supplies.
func _stow_bag(item: String) -> String:
	if item == "":
		return ""
	inventory.add(item, 1)
	return ""


## Screen-local number-key and hotbar-drop rule.
func assign_hotbar_item(i: int, item: String) -> String:
	if inventory.count(item) <= 0:
		return "Click an item in your pockets first"
	return hotbar.assign(i, Hotbar.item_entry(item))


## Repairs a piece (carried or worn) to mint with one repair kit from your pockets. Trains Mechanics
## and (V10) Maintenance.
func repair_gear(uid: int) -> String:
	var why := gear.repair(uid, inventory)
	if why != "":
		return why
	_practice("mechanics", "repair")
	_practice("maintenance", "repair")
	return "Repaired " + gear.find(uid)["name"]


# --- Eating, drinking, first aid, sleep -----------------------------------------

## True if `item` can be used from the inventory screen (food, drink or a bandage).
func can_use(item: String) -> bool:
	return (data.item_value(item, "food") > 0.0 or data.item_value(item, "water") > 0.0
			or data.item_value(item, "bandage") > 0.0
			or str(data.items.get(item, {}).get("throwable", "")) != "")


## Uses one of a particular item from your pockets: eat or drink it, or put on a bandage.
func use_item(item: String) -> String:
	if inventory.count(item) <= 0:
		return "You don't have that"
	if data.item_value(item, "bandage") > 0.0:
		return use_bandage()
	if str(data.items[item].get("throwable", "")) != "":
		return ready_throwable(item)
	var food := data.item_value(item, "food")
	var water := data.item_value(item, "water")
	if food <= 0.0 and water <= 0.0:
		return "Can't use %s" % data.item_name(item)
	inventory.remove(item, 1)
	player.consume(food, water)
	guidance.note_consumed(food, water)
	return "%s %s" % ["Ate" if food >= water else "Drank", data.item_name(item)]



## Eats the most filling food you carry. Returns a message for the HUD.
func eat_best() -> String:
	return _consume_best("food", "Nothing to eat")


func drink_best() -> String:
	return _consume_best("water", "Nothing to drink")


func use_bandage() -> String:
	if not player.bleeding:
		return "Not bleeding"
	if not inventory.remove("bandage", 1):
		return "No bandages"
	player.bleeding = false
	var heal := skills.bonus("bandage_heal")
	player.health = minf(player.max_health, player.health + heal)
	_practice("first_aid", "bandage")
	return "Bandaged" + ((" (+%d health)" % roundi(heal)) if heal > 0.0 else "")


## Sleep in the bed `key`: it becomes your respawn point. Returns "" or why not.
func sleep_in(key: String) -> String:
	if not build.pieces.has(key) or build.kind_of(build.pieces[key]["id"]) != "bed":
		return "No bed"
	guidance.note_bed()
	spawn_point = build.piece_center(key) + Vector3(1.2, -build.piece_center(key).y, 0)
	if player.energy >= float(data.survival["sleep_below_energy"]):
		return "Not tired. You'll wake up here if you die"
	if player.bleeding:
		return "You're bleeding. Bandage first (H)"  # Q5: bleeding would wake you the same tick
	player.sleep()
	return ""


func _consume_best(key: String, none: String) -> String:
	var best := ""
	for item: String in inventory.items():
		if data.item_value(item, key) > (data.item_value(best, key) if best != "" else 0.0):
			best = item
	if best == "":
		return none
	inventory.remove(best, 1)
	var food := data.item_value(best, "food")
	var water := data.item_value(best, "water")
	player.consume(food, water)
	guidance.note_consumed(food, water)
	return "%s %s" % ["Ate" if key == "food" else "Drank", data.item_name(best)]


func _is_supply(item: String) -> bool:
	for key: String in ["food", "water", "bandage", "bag"]:
		if data.item_value(item, key) > 0.0:
			return true
	return false


# --- Doors and repair ---------------------------------------------------------

## Opens or closes a door (a little noise). Returns a message. S3: `from` is where the opener stands, so
## the door swings away from them (see BuildGrid.toggle_door).
func toggle_door(key: String, from: Vector3 = Vector3.INF) -> String:
	if not build.pieces.has(key) or build.kind_of(build.pieces[key]["id"]) != "door":
		return ""
	if automation.is_locked(key):
		return "Locked by a sensor until it clears"
	var open := build.toggle_door(key, from)
	noise.emit_kind(build.piece_center(key), "door")
	return "Door opened" if open else "Door closed"


## Repairs a piece with materials from your pockets and nearby crates. Returns "" or why not.
func repair(key: String) -> String:
	if not build.pieces.has(key):
		return "Nothing to repair"
	var why := build.repair(key, stock_at(build.piece_center(key)), skills.bonus("repair_discount"))
	if why == "":
		_practice("mechanics", "repair")
		_practice("building", "repair")
	return why


## What repairing piece `key` costs you now (Building makes it cheaper).
func repair_cost(key: String) -> Dictionary:
	return build.repair_cost(key, skills.bonus("repair_discount"))


# --- Automated defense (M15) ------------------------------------------------------

## E on a turret: loads its ammo (pockets and nearby crates), then attaches a suppressor or scope from your
## pockets to an empty slot. Returns a message.
func turret_interact(cell: Vector2i, at: Vector3) -> String:
	var t: Factory.Turret = factory.turrets.get(cell)
	if t == null:
		return ""
	var said := PackedStringArray()
	var moved := factory.hand_interact(cell, stock_at(at))
	if not moved["fed"].is_empty():
		said.append("Loaded " + _list(moved["fed"]))
	for slot: String in data.defense["turret_parts"]:
		if t.parts.has(slot):
			continue
		for p: Dictionary in gear.pieces:
			if gear.slot_of(p) == "part" and str(gear.part_def(p).get("slot", "")) == slot:
				t.parts[slot] = gear.take(int(p["uid"]))
				said.append("Fitted the " + String(p["name"]))
				break
	if said.is_empty():
		return "Nothing to load (needs %s)" % String(data.item_name(t.ammo_item)).to_lower()
	return " · ".join(said)


## Picks the action a sensor runs. "" or why not.
func set_sensor_action(key: String, action: String) -> String:
	return automation.set_action(key, action)


## E on a floodlight: only when a sensor says, or every night.
func toggle_floodlight(key: String) -> String:
	return automation.toggle_floodlight(key)


## E on a noisemaker: sets it off by hand (if it's charged and has power).
func fire_noisemaker(key: String) -> String:
	if not automation.noisemakers.has(key):
		return ""
	var n: Dictionary = automation.noisemakers[key]
	if n["blare"] > 0.0:
		return "It's already going"
	if n["recharge"] > 0.0:
		return "Recharging: %d s" % ceili(n["recharge"])
	return "Noisemaker going off" if automation.fire_noisemaker(key) else "No power for it"


## E on a sprung bear trap: sets it again.
func reset_trap(key: String) -> String:
	var why := defense.reset_trap(key)
	return "Bear trap set" if why == "" else why


## E on a machine: take what it made and load it from your pockets and nearby crates (Factory.hand_interact).
## Taking a planter's vegetables trains Farming.
func machine_interact(cell: Vector2i, at: Vector3) -> Dictionary:
	var moved := factory.hand_interact(cell, stock_at(at))
	var m: Factory.Machine = factory.machines.get(cell)
	if m != null and m.id == "planter" and not moved["took"].is_empty():
		_practice("farming", "harvest")
	return moved


# --- Fuel ---------------------------------------------------------------------

func clock_daylight() -> float:
	return clock.daylight()


## Registers a town car: its gas (fixed by the world seed and the car's id) and whether it's a wreck.
## car_0 always drives, so there's one to find near the start.
func add_car(id: String, type: String = "sedan", pos: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_rng.seed, id, "fuel"])
	var fuel := rng.randi_range(int(data.survival["car_fuel_min"]), int(data.survival["car_fuel_max"]))
	var wreck := ""
	if id != "car_0" and rng.randf() < float(data.survival["car_wreck_chance"]):
		wreck = ["Flat tyres", "The engine won't turn over", "Smashed up too badly"][rng.randi_range(0, 2)]
	if pos == Vector3.ZERO and loot.containers.has(id):
		pos = loot.containers[id]["pos"]  # registered without a spot: where its trunk is
	# Its key (Zomboid style): in the ignition, the glovebox (search the car), the nearest house, or lost.
	# car_0's is always in its glovebox, so a new game teaches you to look.
	var r := rng.randf()
	var key_in := "glovebox" if id == "car_0" else ("ignition" if r < 0.25 else ("glovebox" if r < 0.6 else ("house" if r < 0.85 else "lost")))
	vehicles.add(id, type, pos, yaw, fuel, wreck, key_in)
	if loot.containers.has(id):
		loot.containers[id]["pos"] = vehicles.trunk_pos(id)
	var key := {Vehicles.key_item(id): 1}
	if key_in == "glovebox" and loot.containers.has(id):
		loot.add_extra(id, key)
	elif key_in == "house":
		var house := _nearest_house(pos)
		if house != "":
			loot.add_extra(house, key)
		else:
			vehicles.cars[id]["key_in"] = "lost"


func _nearest_house(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for cid: String in loot.containers:
		if cid.begins_with("house_"):
			var d := _flat_dist(loot.containers[cid]["pos"], pos)
			if d < best_d:
				best_d = d
				best = cid
	return best


## Siphons every whole gas can's worth out of a car into your pockets (a sloshing noise). Returns a message.
func siphon(id: String) -> String:
	if not vehicles.cars.has(id):
		return "No fuel tank"
	if _flat_dist(vehicles.cars[id]["pos"], player_pos) > float(data.survival["search_range"]) + 2.5:
		return "Too far away"
	var cans := vehicles.siphon(id)
	if cans <= 0:
		return "The tank is dry"
	inventory.add("gas_can", cans)
	noise.emit(player_pos, float(data.survival["siphon_noise"]), "siphon")
	stats.note("siphoned gas from a " + str(vehicles.cars[id].get("type", "car")))
	return "Siphoned %d gas can%s" % [cans, "s" if cans > 1 else ""]


# --- Driving ------------------------------------------------------------------

## Gets into car `id`. Returns "" or why not.
func enter_car(id: String) -> String:
	if player.dead:
		return "You're dead"
	var why := vehicles.enter(id)
	if why == "":
		player_pos = vehicles.cars[id]["pos"]  # you're in the car now: zombies come for it
		var c: Dictionary = vehicles.cars[id]
		c["running"] = c["fuel"] > 0.0 and vehicles.can_start(id, inventory)  # no key, no engine
		if not vehicles.can_start(id, inventory) and not _told_no_key.has(id):
			_told_no_key[id] = true  # once per car, so it doesn't nag every time you sit in it
			add_message(NO_KEY_MESSAGE, 8.0)
		stats.note("got in a " + str(c.get("type", "car")))
	return why


## R while sitting in a car you have no key for: hotwire it. Needs Mechanics (data/skills.json
## hotwire_level); higher levels are quicker. Makes a little noise. Returns "" or why not.
func hotwire() -> String:
	var id := vehicles.driving
	if id == "":
		return "Not in a car"
	if vehicles.can_start(id, inventory):
		return "You don't need to: you can start this one"
	var need := int(data.skills["hotwire_level"])
	var lv := skills.level("mechanics")
	if lv < need:
		return "You don't know how to hotwire a car (needs Mechanics %d)" % need
	if vehicles.hotwire_left <= 0.0:
		vehicles.hotwire_left = maxf(float(data.skills["hotwire_min_seconds"]),
				float(data.skills["hotwire_seconds"]) - float(data.skills["hotwire_seconds_per_level"]) * (lv - need))
		noise.emit(vehicles.cars[id]["pos"], float(data.skills["hotwire_noise"]), "hotwire")
	return ""


func _tick_hotwire() -> void:
	if vehicles.hotwire_left <= 0.0 or vehicles.driving == "":
		return
	vehicles.hotwire_left -= TICK
	if vehicles.hotwire_left > 0.0:
		return
	vehicles.hotwire_left = 0.0
	var c: Dictionary = vehicles.cars[vehicles.driving]
	c["hotwired"] = true
	c["running"] = c["fuel"] > 0.0
	_practice("mechanics", "hotwire")
	add_message("Hotwired. The engine coughs into life" if c["running"] else "Hotwired, but the tank is empty", 4.0)


## Gets out; you end up beside the driver's door. Returns where you stand.
func exit_car() -> Vector3:
	var id := vehicles.exit()
	if id == "":
		return player_pos
	player_pos = vehicles.exit_pos(id)
	return player_pos


## The world reports the car you're driving each physics step: you're where the car is (so zombies come
## for the car), fuel burns, and the trunk moves with it.
func car_moved(pos: Vector3, yaw: float, speed: float) -> void:
	var id := vehicles.driving
	if id == "":
		return
	vehicles.moved(id, pos, yaw, speed)
	player_pos = pos
	if loot.containers.has(id):
		loot.containers[id]["pos"] = vehicles.trunk_pos(id)


func honk() -> void:
	if vehicles.driving != "":
		noise.emit_kind(vehicles.cars[vehicles.driving]["pos"], "horn")


func refuel_car(id: String) -> String:
	if not vehicles.cars.has(id):
		return "No fuel tank"
	return vehicles.refuel(id, inventory)


## Repairs a car with a metal plate and nails from your pockets and nearby crates. Returns "" or why not.
func repair_car(id: String) -> String:
	if not vehicles.cars.has(id):
		return "Nothing to repair"
	var why := vehicles.repair(id, stock_at(vehicles.cars[id]["pos"]))
	if why == "":
		_practice("mechanics", "repair_car")
	return why


## The car you're driving hit zombie `zombie_id` at `speed` m/s. Returns true if it died.
func car_hits_zombie(zombie_id: int, speed: float) -> bool:
	var z: ZombieBrain = horde.zombies.get(zombie_id)
	if z == null or z.is_dead() or vehicles.driving == "":
		return false
	var car: Dictionary = vehicles.cars[vehicles.driving]
	var damage := vehicles.ram(vehicles.driving, speed)
	noise.emit_kind(z.pos, "zombie_bash")
	var killed := z.take_hit(damage, car["pos"], speed * 0.6)
	if killed:
		stats.note_kill(z.type)
		stats.note("ran over a " + z.type)
	return killed


# --- Searching ----------------------------------------------------------------

## Starts searching a container (a little noise). Returns "" or why not.
func search(id: String) -> String:
	var reason := loot.start(id, player_pos)
	if reason == "" and loot.progress == 0.0:
		noise.emit(loot.containers[id]["pos"], float(data.survival["search_noise"]), "search")
		stats.note("searched " + id.replace("_", " "))
	return reason


## Screenshot/test path: reveal the same seeded contents without spending search time or making noise.
func reveal_container(id: String) -> String:
	if not loot.containers.has(id):
		return "Nothing to search"
	if loot.containers[id]["searched"]:
		return ""
	var found := loot.reveal(id)
	if found.is_empty():
		return "Nothing to search"
	_finish_search(found)
	return ""


## A completed search leaves everything in the container; the screen decides what to take.
func _finish_search(found: Dictionary) -> void:
	_practice("scavenging", "search")
	var id := str(found["id"])
	var items: Dictionary = _rot_old_food(found["items"])
	var armoury := _search_guns(found)
	for item: String in armoury["items"]:
		items[item] = int(items.get(item, 0)) + int(armoury["items"][item])
	loot.inventory(id).give_all(items)
	var rolled: Array = _search_gear(found) + armoury["pieces"]
	loot.add_gear(id, rolled)
	for piece: Dictionary in rolled:
		stats.note_gear(piece.get("rarity", "white"))
		_announce(piece, "You find")
	if id.begins_with(CORPSE):
		var zid := int(id.trim_prefix(CORPSE))
		if horde.zombies.has(zid):
			horde.zombies[zid].searched = true
	var names := PackedStringArray()
	if not items.is_empty():
		names.append(_list(items))
	for piece: Dictionary in loot.containers[id]["gear"]:
		names.append(piece["name"])
	add_message(("Found " + ", ".join(names) + " — choose what to take") if not names.is_empty() else "Nothing useful", 4.0)
	container_searched.emit(id)


## Fits a muffler to the machine at `cell`: -15 loudness, 10% slower. Returns "" or why not.
func fit_muffler(cell: Vector2i) -> String:
	var gen_key := "o:%d:%d" % [cell.x, cell.y]
	if power.generators.has(gen_key):
		if power.generators[gen_key]["muffled"]:
			return "Already muffled"
		if not inventory.take_all(data.noise["muffler"]["cost"]):
			return "Not enough materials"
		power.generators[gen_key]["muffled"] = true
		_practice("mechanics", "muffler")
		stats.note_muffler()
		return ""
	var m: Factory.Machine = factory.machines.get(cell)
	if m == null:
		return "No machine there"
	if m.muffled:
		return "Already muffled"
	var muffler: Dictionary = data.noise["muffler"]
	if not inventory.take_all(muffler["cost"]):
		return "Not enough materials"
	m.muffled = true
	m.time_scale = 1.0 + float(muffler["slowdown"])
	_practice("mechanics", "muffler")
	stats.note_muffler()
	return ""


## Starts a melee swing if the weapon is ready and there's stamina (PlayerStats.try_swing). Swinging
## trains Strength. Returns true if it swung.
func swing() -> bool:
	respawn_grace = 0.0
	if not player_vault.is_empty() or not player.try_swing(swing_cooldown()):
		return false
	_practice("strength", "swing")
	return true


## W2 (Emmitt: "lets work on making things destructible like windows"): how much of a hit a piece takes, by
## what it's made of and what hit it. Glass goes in one hit; wood takes axes best and blades worst; stone
## and brick (town walls, floors) and everything you built yourself shrug it off (no wrecking your own base
## with a missed swing). `by` is a weapon class ("blunt", "blade", "axe", "fists") or "bullet".
const BREAK_FACTOR := {
	"glass": {"blunt": 999.0, "blade": 999.0, "axe": 999.0, "fists": 999.0, "bullet": 999.0},
	"wood": {"blunt": 1.0, "blade": 0.4, "axe": 2.2, "fists": 0.25, "bullet": 0.3},
}


## W2: what a piece is made of for the player's hits: "glass", "wood", or "" (you can't break it).
func piece_material(key: String) -> String:
	if not build.pieces.has(key) or build.is_broken(key):
		return ""
	var piece: Dictionary = build.pieces[key]
	var kind := build.kind_of(piece["id"])
	if kind == "window":
		return "glass"
	if piece.get("town", false) and kind in ["door", "fence"]:
		return "wood"
	return ""


## W2: the player hits a piece (`by` as in BREAK_FACTOR) for `damage`. Returns "" (no effect: you can't break
## that), "hit" (it took the hit) or "broke" (glass shattered or the piece gave way). Loud: glass breaking can
## be heard a long way off.
func player_hit_piece(key: String, damage: float, by: String) -> String:
	var mat := piece_material(key)
	if mat == "":
		return ""
	var at := build.piece_center(key)
	var amount := maxi(1, roundi(damage * float(BREAK_FACTOR[mat].get(by, 1.0))))
	if by != "bullet" and gear.wear_weapon(skills.bonus("wear_cut")) == "broke":
		add_message("Your weapon broke! Find another weapon", 7.0)
		noise.emit(player_pos, noise_loudness("weapon_break"), "weapon_break")
	if not build.damage(key, amount):
		noise.emit_kind(at, "wood_hit")
		return "hit"
	noise.emit_kind(at, "glass_break" if mat == "glass" else "wood_break")
	stats.note("broke a window" if mat == "glass" else "broke down a door")
	if mat == "glass" and not _told_glass:
		_told_glass = true
		add_message("Breaking glass is loud: everything nearby heard that", 6.0)
	return "broke"


## Melee damage of one body hit: the weapon's, plus Strength, Heavy Swing and (V10) the skill for this
## kind of weapon (Blunt, Blades or Axe).
func melee_damage() -> float:
	var cls := gear.weapon_class()
	return float(weapon_stats()["damage"]) * (1.0 + skills.bonus("melee_damage") + skills.bonus(cls + "_damage"))


## V10: seconds between swings: the weapon's, quicker with its skill (never below half).
func swing_cooldown() -> float:
	var cut := minf(0.5, skills.bonus(gear.weapon_class() + "_speed"))
	return float(weapon_stats()["cooldown"]) * (1.0 - cut)


## V10: the skill that a hit with the weapon in hand trains ("" bare-handed).
func weapon_skill() -> String:
	return String({"blunt": "blunt", "blade": "blades", "axe": "axe"}.get(gear.weapon_class(), ""))


## The player hits zombie `id` with their weapon (call after swing() succeeds and the swing
## connects). `head` doubles the damage. Returns true if it killed the zombie.
## V33 (Emmitt: "better hitboxes"): the zones a hit can land in. The world reads them off a zombie's bone hit
## zones; old callers pass true (the head) or false (the body).
const HIT_ZONES := ["head", "torso", "arm", "leg"]


static func hit_zone(zone: Variant) -> String:
	if zone is bool:
		return "head" if zone else "torso"
	return str(zone) if str(zone) in HIT_ZONES else "torso"


## V33: the damage multiplier for `zone`; the head uses the weapon's or gun's own head multiplier.
func zone_multiplier(zone: String, head_multiplier: float) -> float:
	if zone == "head":
		return head_multiplier
	return float(data.hit_zones.get("damage", {}).get(zone, 1.0))


## V33: the zone from where a hit landed on a zombie that has no bone zones (sim bolts): over its head line is
## the head, under the leg line the legs. A crawler (head_ahead) lies flat: its head is the front of its body.
func zone_at(z: ZombieBrain, at: Vector3) -> String:
	if z.stats.has("head_ahead"):
		var ahead := Vector2(at.x - z.pos.x, at.z - z.pos.z).dot(Vector2(z.facing.x, z.facing.z).normalized())
		return "head" if ahead >= float(z.stats["head_ahead"]) else "torso"
	return zone_at_height(z, at.y)


func zone_at_height(z: ZombieBrain, y: float) -> String:
	var above := y - z.pos.y
	if above >= float(z.stats.get("head_height", 1.45)):
		return "head"
	if above <= float(z.stats.get("leg_height", data.hit_zones.get("leg_height", 0.8))):
		return "leg"
	return "torso"


## V33: a leg hit makes it limp for a moment.
func _zone_effect(z: ZombieBrain, zone: String) -> void:
	if zone == "leg" and not z.is_dead():
		z.limp = float(data.hit_zones.get("limp_time", 0.0))
		z.limp_factor = float(data.hit_zones.get("limp_factor", 1.0))


func hit_zombie(id: int, zone: Variant = "torso") -> bool:
	respawn_grace = 0.0
	var z: ZombieBrain = horde.zombies.get(id)
	if z == null:
		return false
	var where := hit_zone(zone)
	var w := weapon_stats()
	var dmg := melee_damage() * zone_multiplier(where, float(w["head_multiplier"]))
	noise.emit(z.pos, noise_loudness("melee_hit"), "melee_hit")
	var skill := weapon_skill()  # before the wear: a weapon that breaks on this hit still trains its skill
	var name := gear.weapon_name()
	match gear.wear_weapon(skills.bonus("wear_cut")):
		"worn":
			add_message("Your %s is worn out: its bonuses stop, and it'll break soon (repair kit from the Press)" % name, 6.0)
		"broke":
			add_message("Your %s broke! Find another weapon" % name, 7.0)
			noise.emit(player_pos, noise_loudness("weapon_break"), "weapon_break")
			stats.note("broke a " + name.to_lower())
	var killed := z.take_hit(dmg, player_pos, float(w["knockback"]) * (1.0 + skills.bonus("knockback")))
	_zone_effect(z, where)
	stats.note("hit a zombie")
	if skill != "":
		_practice(skill, "hit")
	_practice("maintenance", "hit")
	if killed:
		if skill != "":
			_practice(skill, "kill")
		stats.note_kill(z.type)
		stats.note("killed a " + z.type)
	return killed


# --- Guns (M14) --------------------------------------------------------------------

## Q: cycles melee, primary and sidearm, skipping empty firearm slots. Returns a message.
func swap_hands() -> String:
	if not player_vault.is_empty():
		return "Finish climbing first"
	return guns.swap()


## V19: a hands-bar key puts that weapon slot in your hands. Returns a message.
func draw_weapon(slot: String) -> String:
	if not player_vault.is_empty():
		return "Finish climbing first"
	return guns.draw(slot)


## Fires the gun in your hands: uses a round, kicks up the spread, wears the gun and its suppressor, and
## makes the shot's noise where you stand (loud: it raises heat and infamy like any one-off sound).
## Trains Firearms. Returns "" if it fired, otherwise why not. The world then raycasts and calls
## shoot_zombie() if the ray met a zombie.
func fire() -> String:
	respawn_grace = 0.0
	if not player_vault.is_empty():
		return "Finish climbing first"
	var why := guns.can_fire()
	if why != "":
		return why
	var kind := guns.shot_kind()
	var loud := guns.shot_loudness()
	for piece: Dictionary in guns.fire():
		add_message("Your %s is worn out: its bonuses stop until you repair it" % piece["name"], 5.0)
	noise.emit(player_pos, maxf(0.0, loud - skills.bonus("quiet_all")), kind)
	_practice("firearms", "shot")
	stats.note("fired a firearm")
	stats.note_shot(str(guns.gun().get("name", "firearm")))
	return ""


## A shot that the world's ray put on zombie `id`: it hits (P2: the ray in the spread cone is the only roll;
## distance, Firearms, the scope and recoil act through Gunplay.spread_deg), headshots double. Trains Firearms.
## Returns {"hit": bool, "killed": bool}.
func shoot_zombie(id: int, zone: Variant = "torso") -> Dictionary:
	var z: ZombieBrain = horde.zombies.get(id)
	if z == null or z.is_dead():
		return {"hit": false, "killed": false}
	var where := hit_zone(zone)
	var dmg := guns.damage() * zone_multiplier(where, float(data.guns["head_multiplier"]))
	var result := _damage_zombie(id, dmg, float(guns.stats()["knockback"]), player_pos,
			str(guns.gun().get("name", "firearm")), true)
	_zone_effect(z, where)
	result["zone"] = where
	return result


func _damage_zombie(id: int, damage: float, push: float, from: Vector3, weapon_name: String,
		practice_firearms: bool = false) -> Dictionary:
	var z: ZombieBrain = horde.zombies.get(id)
	if z == null or z.is_dead():
		return {"hit": false, "killed": false}
	var killed := z.take_hit(damage, from, push)
	stats.note("shot a zombie")
	stats.note_gun_hit(weapon_name, killed)
	if practice_firearms:
		_practice("firearms", "hit")
	if killed and practice_firearms:
		_practice("firearms", "kill")
	if killed:
		stats.note_kill(z.type)
		stats.note("killed a " + z.type)
	return {"hit": true, "killed": killed}


## V30 shotgun: every pellet direction and zombie intersection is a deterministic sim hit check. Returns one
## entry per pellet that met a zombie: {zombie, distance, damage, killed, position}.
func fire_shotgun_pellets(from: Vector3, forward: Vector3) -> Array:
	var hits: Array = []
	var max_range := float(guns.stats().get("range", 35.0))
	for direction: Vector3 in guns.shot_directions(forward, true):
		var best_id := -1
		var best_t := max_range + 1.0
		for id: int in horde.zombies:
			var z: ZombieBrain = horde.zombies[id]
			if z.is_dead():
				continue
			var t := _segment_sphere_t(from, direction, z.pos + Vector3.UP, 0.58, max_range)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_id = id
		if best_id < 0:
			continue
		var damage := guns.damage(best_t)
		var result := _damage_zombie(best_id, damage, float(guns.stats()["knockback"]), from,
				str(guns.gun().get("name", "Pump shotgun")), true)
		hits.append({"zombie": best_id, "distance": best_t, "damage": damage, "killed": result["killed"],
				"position": from + direction * best_t})
	return hits


static func _segment_sphere_t(origin: Vector3, direction: Vector3, center: Vector3, radius: float,
		max_distance: float) -> float:
	var to_center := center - origin
	var along := to_center.dot(direction)
	if along < 0.0 or along > max_distance:
		return -1.0
	var closest := origin + direction * along
	if closest.distance_squared_to(center) > radius * radius:
		return -1.0
	return along


## Crossbow bolts keep position and velocity in the sim; ProjectileView only mirrors this list.
func launch_bolt(from: Vector3, forward: Vector3, from_fired_shot: bool = false) -> int:
	var directions := guns.shot_directions(forward, from_fired_shot)
	var direction: Vector3 = directions[0] if not directions.is_empty() else forward.normalized()
	var id := _next_projectile
	_next_projectile += 1
	projectiles.append({"id": id, "kind": "bolt", "pos": from, "previous": from,
			"velocity": direction * float(guns.stats().get("projectile_speed", 55.0)), "age": 0.0,
			"damage": guns.damage(), "knockback": float(guns.stats().get("knockback", 2.0)),
			"gravity": float(guns.stats().get("projectile_gravity", 9.8)),
			"survival": float(guns.stats().get("bolt_survival", 0.70)),
			"weapon": str(guns.gun().get("name", "Crossbow"))})
	return id


static func bolt_survives(roll: float, chance: float = 0.70) -> bool:
	return roll < chance


func ready_throwable(item: String) -> String:
	if not data.items.has(item) or str(data.items[item].get("throwable", "")) == "":
		return "That cannot be thrown"
	if inventory.count(item) <= 0:
		return "No %s" % data.item_name(item).to_lower()
	ready_throw = item
	guns.aiming = false
	return "%s ready · hold LMB, release to throw · RMB cancel" % data.item_name(item)


func cancel_throwable() -> void:
	ready_throw = ""


## Charge 0..1 maps to a controlled toss through a full-strength throw. The small lift keeps a level-camera
## throw useful while still allowing the camera pitch to aim high or low.
static func throw_velocity(forward: Vector3, charge: float) -> Vector3:
	var speed := lerpf(9.0, 20.0, clampf(charge, 0.0, 1.0))
	return forward.normalized() * speed + Vector3.UP * lerpf(1.5, 3.0, clampf(charge, 0.0, 1.0))


## Uses the same fixed-step integration as a real throw, stopping at its first ground contact.
static func predict_throw_arc(origin: Vector3, velocity: Vector3, gravity: float = 9.8) -> PackedVector3Array:
	var points := PackedVector3Array([origin])
	var pos := origin
	var v := velocity
	for _step in 120:
		v.y -= gravity * TICK
		pos += v * TICK
		if pos.y <= 0.08:
			pos.y = 0.08
			points.append(pos)
			break
		points.append(pos)
	return points


func throw_ready_item(origin: Vector3, velocity: Vector3) -> String:
	respawn_grace = 0.0
	if ready_throw == "":
		return "Nothing readied"
	if inventory.count(ready_throw) <= 0:
		var missing := ready_throw
		ready_throw = ""
		return "No %s" % data.item_name(missing).to_lower()
	var item := ready_throw
	var kind := str(data.items[item]["throwable"])
	inventory.remove(item, 1)
	var id := _next_projectile
	_next_projectile += 1
	thrown.append({"id": id, "kind": kind, "item": item, "pos": origin, "previous": origin,
			"velocity": velocity, "fuse": 3.0 if kind == "pipe_bomb" else -1.0, "bounces": 0})
	stats.note_throw(data.item_name(item))
	stats.note("threw a %s" % data.item_name(item).to_lower())
	ready_throw = ""
	return ""


func _tick_ballistics(dt: float) -> void:
	projectile_events = projectile_events.filter(func(e: Dictionary) -> bool:
		return ticks - int(e.get("tick", ticks)) <= TICK_RATE * 3)
	for bolt: Dictionary in projectiles.duplicate():
		_tick_bolt(bolt, dt)
	for throwable: Dictionary in thrown.duplicate():
		_tick_throwable(throwable, dt)


func _tick_bolt(bolt: Dictionary, dt: float) -> void:
	bolt["previous"] = bolt["pos"]
	var velocity: Vector3 = bolt["velocity"]
	velocity.y -= float(bolt["gravity"]) * dt
	bolt["velocity"] = velocity
	bolt["pos"] = (bolt["pos"] as Vector3) + velocity * dt
	bolt["age"] = float(bolt["age"]) + dt
	var segment: Vector3 = (bolt["pos"] as Vector3) - (bolt["previous"] as Vector3)
	var length := segment.length()
	if length > 0.0001:
		var direction := segment / length
		var best_id := -1
		var best_t := length + 1.0
		for id: int in horde.zombies:
			var z: ZombieBrain = horde.zombies[id]
			if z.is_dead():
				continue
			var t := _segment_sphere_t(bolt["previous"], direction, z.pos + Vector3.UP, 0.52, length)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_id = id
		if best_id >= 0:
			bolt["pos"] = (bolt["previous"] as Vector3) + direction * best_t
			# V33: a bolt lands where it meets the body: over the head line is a headshot, low is the legs.
			var bz: ZombieBrain = horde.zombies[best_id]
			var where := zone_at(bz, bolt["pos"])
			var result := _damage_zombie(best_id, float(bolt["damage"]) * zone_multiplier(where, float(data.guns["head_multiplier"])),
					float(bolt["knockback"]), bolt["previous"], str(bolt["weapon"]), true)
			_zone_effect(bz, where)
			if bolt_survives(_ballistic_rng.randf(), float(bolt["survival"])):
				embedded_bolts[best_id] = int(embedded_bolts.get(best_id, 0)) + 1
			projectile_events.append({"type": "bolt_hit", "pos": bolt["pos"], "zombie": best_id, "zone": where,
					"killed": result["killed"], "tick": ticks})
			projectiles.erase(bolt)
			return
	if (bolt["pos"] as Vector3).y <= 0.08 or float(bolt["age"]) >= 4.0:
		var land: Vector3 = bolt["pos"]
		land.y = 0.08
		bolt["pos"] = land
		if bolt_survives(_ballistic_rng.randf(), float(bolt["survival"])):
			_drop_bolt_pickup(land)
		projectile_events.append({"type": "bolt_land", "pos": land, "tick": ticks})
		projectiles.erase(bolt)


func _drop_bolt_pickup(pos: Vector3) -> void:
	var cid := "bolt_pickup_%d" % _next_projectile
	_next_projectile += 1
	loot.add(cid, "ground_pickup", pos)
	loot.containers[cid]["searched"] = true
	loot.inventory(cid).add("bolt", 1)
	projectile_pickups[cid] = pos


func _tick_throwable(body: Dictionary, dt: float) -> void:
	body["previous"] = body["pos"]
	var velocity: Vector3 = body["velocity"]
	velocity.y -= 9.8 * dt
	body["velocity"] = velocity
	body["pos"] = (body["pos"] as Vector3) + velocity * dt
	if float(body["fuse"]) >= 0.0:
		body["fuse"] = float(body["fuse"]) - dt
		if float(body["fuse"]) <= 0.0:
			_explode_pipe_bomb(body["pos"])
			thrown.erase(body)
			return
	if (body["pos"] as Vector3).y > 0.08:
		return
	var land: Vector3 = body["pos"]
	land.y = 0.08
	body["pos"] = land
	if body["kind"] == "bottle":
		noise.emit(land, noise_loudness("bottle_break"), "bottle_break")
		projectile_events.append({"type": "bottle_break", "pos": land, "tick": ticks})
		thrown.erase(body)
		return
	velocity = body["velocity"]
	if absf(velocity.y) > 1.2:
		velocity.y = absf(velocity.y) * 0.34
		velocity.x *= 0.68
		velocity.z *= 0.68
		body["bounces"] = int(body["bounces"]) + 1
		projectile_events.append({"type": "bounce", "pos": land, "tick": ticks})
	else:
		velocity = Vector3.ZERO
	body["velocity"] = velocity


func _explode_pipe_bomb(pos: Vector3) -> void:
	var center := pos
	center.y = maxf(center.y, 0.2)
	var radius := 5.0
	noise.emit(center, noise_loudness("pipe_bomb"), "pipe_bomb")
	projectile_events.append({"type": "explosion", "pos": center, "tick": ticks})
	for id: int in horde.zombies:
		var z: ZombieBrain = horde.zombies[id]
		if z.is_dead():
			continue
		var distance := z.pos.distance_to(center)
		if distance > radius:
			continue
		var falloff := 1.0 - distance / radius
		var result := _damage_zombie(id, lerpf(15.0, 110.0, falloff), lerpf(1.0, 8.0, falloff), center,
				"Pipe bomb", false)
		z.stunned = maxf(z.stunned, lerpf(0.4, 2.2, falloff))
		if result["killed"]:
			stats.note("blew up a " + z.type)
	var player_distance := player_pos.distance_to(center)
	if player_distance <= radius:
		player.damage(lerpf(8.0, 80.0, 1.0 - player_distance / radius), "pipe bomb")
	for key: String in build.pieces.keys():
		var distance := build.piece_center(key).distance_to(center)
		if distance <= radius:
			build.damage(key, roundi(lerpf(2.0, 20.0, 1.0 - distance / radius)))


## R with a gun in hand: starts a reload (or switches ammo type). A reload click carries a few metres.
func reload() -> String:
	if not player_vault.is_empty():
		return "Finish climbing first"
	var msg := guns.start_reload(inventory)
	if guns.reloading > 0.0:
		noise.emit(player_pos, noise_loudness("reload"), "reload")
	return msg


## Finds a firearm by uid in your pockets/equipment or in the open container named by `container_id`.
func gun_piece(uid: int, container_id: String = "") -> Dictionary:
	var held := gear.find(uid)
	if gear.is_gun(held):
		return held
	if container_id != "":
		for piece: Dictionary in container_gear(container_id):
			if int(piece["uid"]) == uid and gear.is_gun(piece):
				return piece
	return {}


## Read-only drag/drop check for fitting a pocket part to a specific gun and slot anywhere in the field.
func can_attach_part_to_gun(gun_uid: int, part_uid: int, slot: String = "", container_id: String = "") -> String:
	return gear.can_attach(gun_piece(gun_uid, container_id), part_uid, slot)


## Fits a pocket part to a specific firearm, including one carried in pockets or lying in the open container.
## Fitting is instant but makes the small handling noise from data/noise.json.
func attach_part_to_gun(gun_uid: int, part_uid: int, slot: String = "", container_id: String = "") -> String:
	var gun := gun_piece(gun_uid, container_id)
	var part := gear.find(part_uid)
	var why := gear.attach(gun, part_uid, slot)
	if why != "":
		return why
	make_noise(player_pos, "gun_mod")
	return "%s fitted: %s" % [part["name"], gear.part_fit_text(part)]


## Legacy/workbench convenience: fits to the firearm Q most recently selected.
func attach_part(uid: int) -> String:
	var gun := gear.gun()
	return attach_part_to_gun(int(gun.get("uid", -1)), uid)


## Takes a part off a specific firearm into your pockets (with rounds that no longer fit).
func detach_part_from_gun(gun_uid: int, slot: String, container_id: String = "") -> String:
	var gun := gun_piece(gun_uid, container_id)
	var part: Dictionary = gun.get("parts", {}).get(slot, {})
	var out := gear.detach(gun, slot)
	if out["why"] != "":
		return out["why"]
	if int(out["rounds"]) > 0:
		inventory.add(gun["ammo"], int(out["rounds"]))
	make_noise(player_pos, "gun_mod")
	return "%s removed%s" % [part["name"], " · %d rounds moved to pockets" % int(out["rounds"]) if int(out["rounds"]) > 0 else ""]


## Legacy/workbench convenience: removes from the firearm Q most recently selected.
func detach_part(slot: String) -> String:
	var gun := gear.gun()
	return detach_part_from_gun(int(gun.get("uid", -1)), slot)


## The workbench's recipes (recipes.json "station": "workbench"), in file order.
func bench_recipes() -> Array:
	return data.recipes.keys().filter(func(r: String) -> bool: return data.recipes[r]["station"] == "workbench")


## "" if you can make `recipe` at a workbench at `at` now, otherwise why not (Gunsmith, materials).
func can_bench_craft(recipe: String, at: Vector3) -> String:
	var r: Dictionary = data.recipes.get(recipe, {})
	if r.is_empty() or r["station"] != "workbench":
		return "Not a workbench recipe"
	if r["perk"] != "" and skills.rank(r["perk"]) < 1:
		return "Needs the %s perk (Fighter tree, K)" % skills.perk_name(r["perk"])
	if not stock_at(at).has_all(r["in"]):
		return "Needs " + _list(r["in"])
	return ""


## Makes `recipe` by hand at a workbench at `at`, from your pockets and crates in reach: ammo goes in
## your pockets, a part (white, civilian, mint) too. Returns a message.
func bench_craft(recipe: String, at: Vector3) -> String:
	var why := can_bench_craft(recipe, at)
	if why != "":
		return why
	var r: Dictionary = data.recipes[recipe]
	stock_at(at).take_all(r["in"])
	inventory.give_all(r["out"])
	if r["gear"] != "":
		var piece := gear.make(r["gear"], "civilian", "white")
		gear.pieces.append(piece)
		return "Made " + piece["name"]
	return "Made " + _list(r["out"])


## Guns, parts and ammo a finished search turns up (guns.json "finds" for its table, plus a small
## police_find chance anywhere of a Police-tier gun or part). Its own seeded stream.
func _search_guns(found: Dictionary) -> Dictionary:
	var out := {"pieces": [], "items": {}}
	var table: Dictionary = data.guns["finds"].get(found.get("table", ""), {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, found.get("id", ""), "guns"])
	for kind: String in ["gun", "part"]:
		if rng.randf() < difficulty.chance("loot_abundance", float(table.get(kind, 0.0))):
			out["pieces"].append(_found_gun(rng, kind, false, found.get("table", "")))
	if rng.randf() < difficulty.chance("loot_abundance", float(data.guns["police_find"])):
		out["pieces"].append(_found_gun(rng, "gun" if rng.randf() < 0.5 else "part", true))
	var gun_ammo := ""
	for piece: Dictionary in out["pieces"]:
		if gear.is_gun(piece):
			gun_ammo = str(piece["ammo"])
			break
	if gun_ammo != "" or rng.randf() < difficulty.chance("loot_abundance", float(table.get("ammo", 0.0))):
		var span: Array = data.guns["ammo_found"]
		var ammo := gun_ammo if gun_ammo != "" else "ammo_standard"
		out["items"][ammo] = rng.randi_range(int(span[0]), int(span[1]))
	return out


func _found_gun(rng: RandomNumberGenerator, kind: String, police: bool, source: String = "") -> Dictionary:
	var piece := gear.roll_gun_piece(rng, kind, police, source)
	if kind == "gun":
		var span: Array = data.guns["loaded_when_found"]
		piece["loaded"] = mini(rng.randi_range(int(span[0]), int(span[1])) * int(gear.gun_stats(piece)["magazine"]) / 2,
				int(gear.gun_stats(piece)["magazine"]))
	return piece


## The equipped weapon's stats (M13: from its gear base and tier; fists with nothing equipped).
func weapon_stats() -> Dictionary:
	return gear.weapon_stats()


func _list(items: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in items:
		parts.append("%d %s" % [items[item], data.item_name(item)])
	return ", ".join(parts)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _counts_of(inv: Inventory) -> Dictionary:
	var out := {}
	for item: String in inv.items():
		out[item] = inv.count(item)
	return out


## Picks up a death bag. Returns the items it held ({} if no such bag).
func take_bag(id: int) -> Dictionary:
	for i in bags.size():
		if bags[i]["id"] == id:
			var items: Dictionary = bags[i]["items"].duplicate()
			inventory.give_all(items)
			for piece: Dictionary in bags[i].get("gear", []):
				gear.pieces.append(piece)
				_consider_better_gear(piece)
				items[piece["name"]] = 1  # so the "Took ..." message names it
			bags.remove_at(i)
			return items
	return {}


func _on_player_respawned() -> void:
	respawn_grace = float(data.survival.get("respawn_grace", 0.0))
	player_vault = {}
	clearing_glass = {}
	vault_landing = Vector3.INF
	player_pos = spawn_point


## Dying drops everything you carry in a bag where you fell, gear in your pockets too.
## What you're wearing stays on you (M13).
func _on_player_died() -> void:
	if not player_vault.is_empty():
		vault_landing = player_pos
	player_vault = {}
	clearing_glass = {}
	stats.note_death(player.last_cause, when_text())
	tally["deaths"] += 1
	if not difficulty.keeps_skills_on_death():
		skills.xp.clear()
		skills.perks.clear()
		skills.perk_points = 0
	var items := _counts_of(inventory)
	var pieces := gear.pieces.duplicate()
	if not items.is_empty() or not pieces.is_empty():
		inventory.take_all(items)
		gear.pieces.clear()
		drop_bag(player_pos, items, pieces)


func drop_bag(at: Vector3, items: Dictionary, pieces: Array = []) -> void:
	bags.append({"id": _next_bag, "pos": at, "items": items, "gear": pieces, "kind": BAG, "yaw": 0.0})
	_next_bag += 1


## How far into the next tick we are (0..1), for smoothing visuals between ticks.
func alpha() -> float:
	return clampf(_accumulator / TICK, 0.0, 1.0)


## Building a machine or belt adds it to the factory.
func _on_piece_added(key: String) -> void:
	var piece: Dictionary = build.pieces[key]
	stats.note_built(piece["id"])
	match build.kind_of(piece["id"]):
		"storage":
			storages[key] = Inventory.new()
			storage_gear[key] = []
		"turret":
			factory.add_turret(piece["id"], piece["cell"])
		"machine":
			factory.add_machine(piece["id"], piece["cell"], piece["side"])
		"belt":
			factory.add_belt(piece["cell"], piece["side"])
		"hopper", "repair_station":
			factory.add_bin(piece["id"], piece["cell"], piece["side"])


## Removing one hands back whatever it was holding, on top of the build refund.
## If zombies wrecked it, the contents are lost.
func _on_piece_removed(key: String, piece: Dictionary) -> void:
	var cans := power.take_refund(key) + climate.take_refund(key)  # M16: and a stove's waiting planks
	if cans > 0 and not piece.get("destroyed", false):
		inventory.add(data.buildables[piece["id"]]["fuel"], cans)  # unburnt fuel comes back
	if storages.has(key):
		var held := _counts_of(storages[key])
		var held_gear: Array = storage_gear.get(key, []).duplicate()
		storages.erase(key)
		storage_gear.erase(key)
		if not held.is_empty() or not held_gear.is_empty():
			drop_bag(build.center_for(piece["id"], piece["cell"], piece["side"]) * Vector3(1, 0, 1), held, held_gear)
	if piece.get("destroyed", false) and build.player_placeable(piece["id"]) and build.kind_of(piece["id"]) != "foundation":
		var at := build.center_for(piece["id"], piece["cell"], piece["side"])
		var dir := base_log.direction(at)
		var what: String = String(data.buildables[piece["id"]]["name"]).to_lower()
		base_log.add("%s destroyed" % ((dir.substr(0, 1).to_upper() + dir.substr(1) + " " + what) if dir != "middle"
				else String(data.buildables[piece["id"]]["name"])), at)
	if build.is_object(piece["id"]) and build.kind_of(piece["id"]) == "turret" and factory.turrets.has(piece["cell"]):
		var parts: Dictionary = factory.turrets[piece["cell"]].parts
		if not piece.get("destroyed", false):
			for slot: String in parts:
				gear.pieces.append(parts[slot])  # M15: a suppressor or scope comes back with the turret
	if build.is_object(piece["id"]) and build.kind_of(piece["id"]) in ["machine", "belt", "turret", "hopper", "repair_station"]:
		var m: Factory.Machine = factory.machines.get(piece["cell"])
		var muffled := m != null and m.muffled
		var held := factory.remove_at(piece["cell"])
		if not piece.get("destroyed", false):
			inventory.give_all(held)
			if muffled:
				inventory.give_all(data.noise["muffler"]["cost"])


## Practising a skill (`times` over, e.g. seconds of sprinting); says so when it levels up ("Strength 2")
## and when a perk point is earned. (A signal from Skills back to here would make a reference cycle and
## leak every SimWorld.)
func _practice(skill: String, action: String, times: float = 1.0) -> void:
	var before := skills.level(skill)
	var points := skills.perk_points
	if skills.practice(skill, action, times) > before:
		add_message("%s %d" % [skills.skill_name(skill), skills.level(skill)], 5.0)
		stats.note_level(skill, skills.level(skill))
	if skills.perk_points > points:
		add_message("Perk point! Press K to spend it", 6.0)
		stats.note_perk_points(skills.perk_points - points)


## P3: spends a perk point on `perk` (the skills screen's buttons). Returns "" or why not.
func spend_perk(perk: String) -> String:
	var why := skills.spend(perk)
	if why == "":
		stats.note_perk(perk)
	return why


## P3: learns which town cells belong to which house (TownPlan.generate's "houses"), for the session log.
func know_houses(plan: Dictionary) -> void:
	house_cells.clear()
	for h: Dictionary in plan.get("houses", []):
		var parts: PackedStringArray = str(h["name"]).split("_")  # house_3_e
		var label := "house %s (%s side)" % [parts[1], "east" if parts[2] == "e" else "west"] if parts.size() == 3 else str(h["name"])
		for c: Vector2i in h["cells"]:
			house_cells[c] = label


## Placing a piece yourself trains Building (not the town, a save or a demo base being laid).
func _on_piece_built(key: String) -> void:
	if not stats.muted:
		_practice("building", "place")
	# S4 (Playtest #1: "not able to figure out the building and machines"): a machine placed with no power
	# says so at once, instead of standing there silent.
	if build.pieces.has(key) and build.kind_of(build.pieces[key]["id"]) == "machine" and not power.free:
		var b: Dictionary = data.buildables[build.pieces[key]["id"]]
		if float(b.get("watts", 0.0)) > 0.0 and power.network_of(key).is_empty():
			add_message("%s placed. It needs power: a generator (E loads gas cans) or a solar panel, and a power pole within %d m"
					% [b["name"], int(data.buildables["power_pole"]["reach"])], 8.0)


# --- The world gets worse (M11) -------------------------------------------------

## Each new day: fresh food rots, and about three weeks in the town's gas goes stale.
func _new_day() -> void:
	for piece: Dictionary in gear.wear_day():
		add_message("Your %s is worn out: its bonuses stop until you repair it" % piece["name"], 5.0)
	var rotted := _spoil(inventory)
	for key: String in storages:
		_spoil(storages[key])
	for id: String in loot.containers:
		if loot.containers[id]["searched"]:
			_spoil(loot.inventory(id))
	if rotted > 0:
		add_message("%d of your vegetables rotted" % rotted, 5.0)
	if clock.day >= int(data.survival["gas_stale_day"]) and vehicles.go_stale() > 0:
		add_message("The gas left in the town's cars has gone stale", 6.0)


## Fresh food (items.json "spoil_days" = how long it keeps, on average) rots into rotten food.
## Returns how many rotted.
func _spoil(inv: Inventory) -> int:
	var rotted := 0
	for item: String in inv.items():
		var days := data.item_value(item, "spoil_days")
		if days <= 0.0:
			continue
		var debt: float = float(inv.spoil_debt.get(item, 0.0)) + inv.count(item) / days
		var n := mini(floori(debt), inv.count(item))
		inv.spoil_debt[item] = debt - n
		if n > 0:
			inv.remove(item, n)
			inv.add("rotten_food", n)
			rotted += n
	return rotted


## Fresh food you find in the town has been sitting there since the outbreak: after a week it's rotten.
func _rot_old_food(items: Dictionary) -> Dictionary:
	if clock.day < int(data.survival["found_food_rots_day"]):
		return items
	var out := {}
	for item: String in items:
		var key := "rotten_food" if data.item_value(item, "spoil_days") > 0.0 else item
		out[key] = int(out.get(key, 0)) + int(items[item])
	return out


const CORPSE := "corpse_"  # S4: loot container id prefix for a dead zombie


func _count_kills() -> void:
	for id: int in horde.zombies:
		if horde.zombies[id].is_dead() and not _counted_dead.has(id):
			_counted_dead[id] = true
			tally["kills"] += 1
			_add_corpse(horde.zombies[id])
	for cid: String in loot.containers.keys():  # a cleared corpse takes its container with it
		if cid.begins_with(CORPSE) and not horde.zombies.has(int(cid.trim_prefix(CORPSE))):
			loot.remove(cid)


## S4: a dead zombie becomes a searchable container where it fell (Zomboid-style): the "zombie" loot table,
## plus whatever it carried (_zombie_drop).
func _add_corpse(z: ZombieBrain) -> void:
	var cid := CORPSE + str(z.id)
	loot.add(cid, "zombie", z.pos)
	if int(embedded_bolts.get(z.id, 0)) > 0:
		loot.add_extra(cid, {"bolt": int(embedded_bolts[z.id])})
		embedded_bolts.erase(z.id)
	_zombie_drop(z, cid)
	if not _told_corpse:
		_told_corpse = true
		add_message("Dead zombies can be searched (E on the body)", 5.0)


# --- Loot (M13) --------------------------------------------------------------------

## Gear a finished search turns up: the container's chance (gear.json "containers"), rolled again on
## a Lucky Find. Its own seeded stream, so the same seed finds the same gear.
func _search_gear(found: Dictionary) -> Array:
	var chance := difficulty.chance("loot_abundance",
			float(data.gear["containers"].get(found.get("table", ""), 0.0)))
	var out := []
	if chance <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, found["id"], "gear"])
	for i in (2 if found.get("lucky", false) else 1):
		if rng.randf() < chance:
			out.append(gear.roll_piece(rng, found["table"]))
	return out


## A dead zombie may carry a piece (S4: in its corpse, searched with E; it used to drop a bag): zombie_drop
## chance by type (runners more), and a named zombie always carries its unique (Old Pete: Pete's Fire Axe).
func _zombie_drop(z: ZombieBrain, cid: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "drop", z.id])
	var piece := {}
	var unique: String = data.gear["zombie_uniques"].get(z.type, "")
	if unique != "":
		piece = gear.roll_unique(rng, unique)
	elif rng.randf() < difficulty.chance("loot_abundance",
			float(data.gear["zombie_drop"].get(z.type, data.gear["zombie_drop"]["default"]))):
		piece = gear.roll_piece(rng, "zombie")
	if piece.is_empty():
		return
	stats.note_gear(piece.get("rarity", "white"))
	var extra: Dictionary = data.guns["zombie_extra_uniques"].get(z.type, {})
	if not extra.is_empty():  # M14: Old Pete also carries his deer rifle and some rounds
		loot.add_extra(cid, extra.get("ammo", {}).duplicate())
		loot.add_gear(cid, [piece, gear.roll_unique(rng, extra["unique"])])
	else:
		loot.add_gear(cid, [piece])
	if unique != "" or piece["rarity"] in ["gold", "set"]:
		add_message("%s is carrying something %s: search the body" % [data.zombies[z.type]["name"] if unique != "" else "That one",
				Gear.rarity_word(piece["rarity"])], 6.0)


## A message when you find a unique or set piece in a search.
func _announce(piece: Dictionary, who: String) -> void:
	if piece["rarity"] in ["gold", "set"]:
		add_message("%s something %s: %s" % [who, Gear.rarity_word(piece["rarity"]), piece["name"]], 6.0)


## M13: Old Pete, the named zombie, standing in the factory hall (TownPlan.factory()["pete"]).
func spawn_old_pete() -> ZombieBrain:
	var at: Dictionary = TownPlan.factory()["pete"]
	var z := horde.spawn("old_pete", at["pos"])
	z.facing = at["facing"]
	z.set_guard(at["guard"], at["pos"])  # Q4: he never leaves the hall
	return z


## R on a machine that can make more than one thing (the Press: nails or repair kits): switches to the
## next recipe. What's waiting in its input, and a craft in progress, go back in your pockets.
## Returns a message ("" if the machine has only one recipe).
func cycle_recipe(cell: Vector2i) -> String:
	var m: Factory.Machine = factory.machines.get(cell)
	if m == null:
		return ""
	var ids: Array = data.buildables[m.id].get("recipes", [])
	if ids.size() < 2:
		return ""
	var back := m.input.duplicate()
	if m.crafting:
		for item: String in m.recipe["in"]:
			back[item] = int(back.get(item, 0)) + int(m.recipe["in"][item])
	inventory.give_all(back)
	m.input = {}
	m.crafting = false
	m.progress = 0.0
	factory.set_recipe(m, ids[(ids.find(m.recipe_id) + 1) % ids.size()])
	return "%s now makes %s" % [data.buildables[m.id]["name"], m.recipe["name"]]


## Days survived, deaths, kills and noise made (infamy), for the pause menu.
func stats_text() -> String:
	return "Day %d    Deaths %d    Zombies killed %d    Noise made %d" % [clock.day, tally["deaths"], tally["kills"],
			roundi(director.infamy)]
