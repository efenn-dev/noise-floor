class_name Gunplay
extends RefCounted
## Guns in your hands (M14): what you're holding (Q cycles melee, primary and sidearm), raising the gun, the spread
## that grows with each shot's recoil and settles back, the magazine and reloading, and how loud each shot is.
## Since P2 the spread cone is the only thing that decides a hit: the world's ray lands or it doesn't, and
## Firearms, the scope (range), recoil and distance (a fixed angle covers more ground further out) all act
## on that cone. Numbers come from Gear.gun_stats() (base + parts) and data/guns.json; skills
## and perks come in through Skills.bonus(): spread_cut (Firearms), recoil_cut (Steady Hands),
## reload_speed (Quick Hands), suppressed_quiet (Gunsmith), gun_damage (gear later). SimWorld owns one and
## does the world side (noise, zombies, XP, messages).

var data: GameData
var gear: Gear
var skills: Skills
var hands := "melee"   # "melee", "primary" or "sidearm"; saved
var bloom := 0.0       # extra spread in degrees from recent shots; settles back over time
var cooldown := 0.0    # seconds until the next shot
var raising := 0.0     # seconds until the gun is up after Q
var reloading := 0.0   # seconds left of a reload (0 = not reloading)
var aiming := false    # V15: written by the world; spread remains a deterministic sim rule
var _rng := RandomNumberGenerator.new()  # deterministic pellet cone and projectile launch spread
var _last_fired_spread := 0.0  # cone captured before this trigger pull adds recoil bloom


func _init(p_data: GameData, p_gear: Gear, p_skills: Skills) -> void:
	data = p_data
	gear = p_gear
	skills = p_skills
	_rng.seed = 30030


func gun() -> Dictionary:
	if hands in Gear.FIREARM_SLOTS:
		gear.set_active_gun(hands)
	return gear.gun()


func in_hand() -> bool:
	return hands in Gear.FIREARM_SLOTS and not gun().is_empty()


func stats() -> Dictionary:
	return gear.gun_stats(gun())


## Q: cycles melee -> primary -> sidearm -> melee, skipping empty firearm slots.
func swap() -> String:
	gear.migrate_legacy_gun()
	var order := ["melee", "primary", "sidearm"]
	var at := order.find(hands)
	for step in range(1, order.size() + 1):
		var slot: String = order[(at + step) % order.size()]
		if slot != "melee" and not gear.equipped.get(slot) is Dictionary:
			continue
		if slot == hands:
			return "No firearm equipped (Tab)"
		hands = slot
		aiming = false  # V15: a swap always drops the aim
		reloading = 0.0
		if slot == "melee":
			return "%s in hand" % gear.weapon_name()
		gear.set_active_gun(slot)
		raising = float(stats()["handling"])
		return "%s in hand" % gear.gun_name()
	aiming = false
	reloading = 0.0
	return ""


## V19: a hands-bar key draws one weapon slot ("weapon" = melee, "primary", "sidearm") directly, with the same
## raise, aim and reload rules as Q. Returns a message.
func draw(slot: String) -> String:
	gear.migrate_legacy_gun()
	var want := "melee" if slot == "weapon" else slot
	if want != "melee" and not gear.equipped.get(want) is Dictionary:
		return "No %s equipped (Tab)" % ("rifle" if want == "primary" else "pistol")
	if want == hands:
		return "%s in hand" % (gear.weapon_name() if want == "melee" else gear.gun_name())
	hands = want
	aiming = false
	reloading = 0.0
	if want == "melee":
		return "%s in hand" % gear.weapon_name()
	gear.set_active_gun(want)
	raising = float(stats()["handling"])
	return "%s in hand" % gear.gun_name()


## One tick: timers run down, the spread settles, a finished reload loads the rounds from `inv`.
## Returns the rounds loaded this tick (0 if no reload finished).
func tick(dt: float, inv: Inventory) -> int:
	if hands in Gear.FIREARM_SLOTS and gun().is_empty():
		hands = "melee"  # the gun was taken off
		aiming = false
	cooldown = maxf(0.0, cooldown - dt)
	raising = maxf(0.0, raising - dt)
	var settle := float(stats()["settle"]) if not gun().is_empty() else 8.0
	bloom = maxf(0.0, bloom - settle * dt)
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			reloading = 0.0
			var loaded := _load_step(inv)
			if reload_mode() == "shell" and loaded > 0 and int(gun()["loaded"]) < int(stats()["magazine"]) \
					and inv.count(str(gun()["ammo"])) > 0:
				reloading = reload_time()  # another short, independently interruptible shell step
			return loaded
	return 0


## Spread multiplier from Firearms (3% tighter per level), never below min_spread_mult.
func spread_mult() -> float:
	return maxf(float(data.guns["min_spread_mult"]), 1.0 - skills.bonus("spread_cut"))


## How much a gun's range (the scope, "+% accuracy at range" rolls) tightens its cone while aimed: the base
## gun's range over this one's, so a scope's +60% range is a cone 1/1.6 as wide. 1.0 without range bonuses.
func sight_mult() -> float:
	if gun().is_empty():
		return 1.0
	var base: Dictionary = data.guns["guns"].get(gun().get("base", ""), {})
	var reach := float(stats()["range"])
	if base.is_empty() or reach <= 0.0:
		return 1.0
	return clampf(float(base["range"]) / reach, 0.1, 1.0)


## V15: the cone the world shoots into, in degrees (half-angle). ADS applies the gun's data multiplier;
## a scope's range multiplier only helps while the player is actually looking through it.
func spread_deg() -> float:
	if gun().is_empty():
		return 0.0
	var st := stats()
	var ads := float(st["ads_spread"]) if aiming else 1.0
	var sight := sight_mult() if aiming and scoped() else 1.0
	return (float(st["spread"]) + bloom) * spread_mult() * ads * sight


## The radius in metres of the cone `distance` m out: why the same cone lands less often further away.
func cone_radius(distance: float) -> float:
	return tan(deg_to_rad(spread_deg())) * distance


## True when the gun in hand has a working sight part (the scope): right click zooms with it.
func scoped() -> bool:
	if not in_hand():
		return false
	var sight: Dictionary = gun().get("parts", {}).get("sight", {})
	return not sight.is_empty() and gear.working(sight)


## How loud the next shot is: the gun with its parts, the loaded ammo (subsonic quieter), and Gunsmith's
## 2 per rank off a suppressed shot. (SimWorld takes off the Night Shift set's quiet_all too.)
func shot_loudness() -> float:
	var st := stats()
	var loud := float(st["loudness"]) + float(data.guns["ammo"][gun()["ammo"]]["loudness"])
	if st["suppressed"]:
		loud -= skills.bonus("suppressed_quiet")
	return maxf(0.0, loud)


## The noise kind of a shot ("gunshot_pistol", "gunshot_rifle_suppressed", ...): what SoundView plays.
func shot_kind() -> String:
	var st := stats()
	return "gunshot_%s%s" % [st["sound"], "_suppressed" if st["suppressed"] else ""]


## Damage of one body hit: the gun (base + parts) times gun_damage bonuses times the ammo.
func damage(distance: float = -1.0) -> float:
	var ammo: Dictionary = data.guns["ammo"][gun()["ammo"]]
	var out := float(stats()["damage"]) * (1.0 + skills.bonus("gun_damage")) * float(ammo["damage"])
	var st := stats()
	if distance >= 0.0 and st.has("falloff_start") and distance > float(st["falloff_start"]):
		var span := maxf(0.001, float(st["falloff_end"]) - float(st["falloff_start"]))
		var t := clampf((distance - float(st["falloff_start"])) / span, 0.0, 1.0)
		out *= lerpf(1.0, float(st.get("min_damage", 0.25)), t)
	return out


func base_id() -> String:
	return str(gun().get("base", ""))


func reload_mode() -> String:
	return str(stats().get("reload_mode", "magazine")) if not gun().is_empty() else "magazine"


func pellet_count() -> int:
	return int(stats().get("pellets", 1)) if not gun().is_empty() else 0


## Deterministic directions for every pellet/bolt, owned by the sim rather than presentation physics.
func shot_directions(forward: Vector3, from_fired_shot: bool = false) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var count := pellet_count()
	var half_angle := deg_to_rad(_last_fired_spread if from_fired_shot else spread_deg())
	for _i in count:
		out.append(_in_cone(forward.normalized(), half_angle))
	return out


func _in_cone(dir: Vector3, half_angle: float) -> Vector3:
	if half_angle <= 0.0:
		return dir
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var r := tan(half_angle) * sqrt(_rng.randf())
	var a := _rng.randf() * TAU
	return (dir + side * cos(a) * r + up * sin(a) * r).normalized()


## "" if a shot can be fired now, otherwise why not.
func can_fire() -> String:
	if not in_hand():
		return "No firearm in hand (Q)"
	if reloading > 0.0 and not (reload_mode() == "shell" and int(gun()["loaded"]) > 0):
		return "Reloading..."
	if raising > 0.0 or cooldown > 0.0:
		return "Not ready"
	if int(gun()["loaded"]) <= 0:
		return "Click. Empty (R to reload)"
	return ""


## Fires one round: uses it, kicks the spread up by the recoil (less with Steady Hands), starts the
## cooldown, wears the gun and its muzzle part. Returns the pieces that wore out. Call can_fire() first.
func fire() -> Array:
	var st := stats()
	var piece := gun()
	_last_fired_spread = spread_deg()
	piece["loaded"] = int(piece["loaded"]) - 1
	reloading = 0.0  # a shotgun trigger pull interrupts the next shell step
	var kick := float(st["recoil"]) * maxf(0.2, 1.0 - skills.bonus("recoil_cut"))
	bloom = minf(float(data.guns["max_bloom"]), bloom + kick)
	cooldown = float(st["cooldown"])
	return gear.wear_shot(piece)


## Seconds a reload takes: the gun's, less 10% per Quick Hands rank (never below min_reload_mult).
func reload_time() -> float:
	return float(stats()["reload"]) * maxf(float(data.guns["min_reload_mult"]), 1.0 - skills.bonus("reload_speed"))


## R: starts a reload. Loads the gun's ammo type if you carry it; if you don't (or the magazine is full and
## you carry another type), switches type: the rounds in it go back in your pockets. Returns a message.
func start_reload(inv: Inventory) -> String:
	if not in_hand():
		return ""
	if reloading > 0.0:
		return "Reloading..."
	var piece := gun()
	var full := int(piece["loaded"]) >= int(stats()["magazine"])
	var other := _other_ammo(inv, piece["ammo"])
	if inv.count(piece["ammo"]) > 0 and not full:
		aiming = false
		reloading = reload_time()
		return "Reloading %s..." % data.item_name(piece["ammo"]).to_lower()
	if other == "":
		return "Magazine full" if full else "No %s (the workbench makes them)" % data.item_name(piece["ammo"]).to_lower()
	inv.add(piece["ammo"], int(piece["loaded"]))
	piece["loaded"] = 0
	piece["ammo"] = other
	aiming = false
	reloading = reload_time()
	return "Switching to %s..." % data.item_name(other).to_lower()


func _other_ammo(inv: Inventory, current: String) -> String:
	var gun_def: Dictionary = data.guns["guns"].get(base_id(), {})
	var order: Array = gun_def.get("ammo_types", [gun_def.get("ammo", data.guns["ammo_order"][0])])
	if not gun_def.has("ammo"):
		order = data.guns["ammo_order"]
	var i := order.find(current)
	for k in range(1, order.size()):
		var a: String = order[(i + k) % order.size()]
		if inv.count(a) > 0:
			return a
	return ""


func _load(inv: Inventory) -> int:
	var piece := gun()
	if piece.is_empty():
		return 0
	var n := mini(int(stats()["magazine"]) - int(piece["loaded"]), inv.count(piece["ammo"]))
	if n <= 0:
		return 0
	inv.remove(piece["ammo"], n)
	piece["loaded"] = int(piece["loaded"]) + n
	return n


func _load_step(inv: Inventory) -> int:
	if reload_mode() in ["shell", "single"]:
		var piece := gun()
		if piece.is_empty() or int(piece["loaded"]) >= int(stats()["magazine"]) or inv.count(piece["ammo"]) <= 0:
			return 0
		inv.remove(piece["ammo"], 1)
		piece["loaded"] = int(piece["loaded"]) + 1
		return 1
	return _load(inv)


## V9: " 60%" once the held weapon has some wear, " 20% worn out" when it's about to break; "" when mint.
## V13: inspection asks for `always`, and while a gun is in hand this describes the gun instead of the
## stowed melee weapon. This is display text only; wear and reload rules are unchanged.
func weapon_condition_text(always: bool = false) -> String:
	var piece: Dictionary = gun() if in_hand() else gear.equipped.get("weapon", {})
	if piece.is_empty():
		return ""
	var c := float(piece["condition"])
	if c >= 0.995 and not always:
		return ""
	return " %d%%%s" % [roundi(c * 100.0), "" if gear.working(piece) else " worn out"]


func _next_label() -> String:
	var order := ["melee", "primary", "sidearm"]
	var at := order.find(hands)
	for step in range(1, order.size() + 1):
		var slot: String = order[(at + step) % order.size()]
		if slot == "melee":
			return gear.weapon_name()
		var piece: Variant = gear.equipped.get(slot)
		if piece is Dictionary:
			return "%s %s" % [slot.capitalize(), piece["name"]]
	return ""


## The HUD line names the held slot and the next non-empty slot Q will select.
func hands_text() -> String:
	if not in_hand():
		var next := _next_label()
		return "Melee: %s%s%s" % [gear.weapon_name(), weapon_condition_text(),
				("   (Q: %s)" % next) if next != gear.weapon_name() else ""]
	var piece := gun()
	var state := ""
	if reloading > 0.0:
		state = "  reloading"
	elif raising > 0.0:
		state = "  raising"
	return "%s: %s  %d/%d %s%s   (Q: %s)" % [hands.capitalize(), piece["name"], int(piece["loaded"]),
			int(stats()["magazine"]), data.item_name(piece["ammo"]).to_lower(), state, _next_label()]
