class_name Gunplay
extends RefCounted
## Guns in your hands (M14): what you're holding (Q swaps melee and gun), raising the gun, the spread
## that grows with each shot's recoil and settles back, the magazine and reloading, hit chance by distance,
## and how loud each shot is. Numbers come from Gear.gun_stats() (base + parts) and data/guns.json; skills
## and perks come in through Skills.bonus(): spread_cut (Firearms), recoil_cut (Steady Hands),
## reload_speed (Quick Hands), suppressed_quiet (Gunsmith), gun_damage (gear later). SimWorld owns one and
## does the world side (noise, zombies, XP, messages).

var data: GameData
var gear: Gear
var skills: Skills
var hands := "melee"   # "melee" or "gun"; saved
var bloom := 0.0       # extra spread in degrees from recent shots; settles back over time
var cooldown := 0.0    # seconds until the next shot
var raising := 0.0     # seconds until the gun is up after Q
var reloading := 0.0   # seconds left of a reload (0 = not reloading)


func _init(p_data: GameData, p_gear: Gear, p_skills: Skills) -> void:
	data = p_data
	gear = p_gear
	skills = p_skills


func gun() -> Dictionary:
	return gear.gun()


func in_hand() -> bool:
	return hands == "gun" and not gun().is_empty()


func stats() -> Dictionary:
	return gear.gun_stats(gun())


## Q: swaps between your melee weapon and your gun. Returns a message.
func swap() -> String:
	if hands == "melee":
		if gun().is_empty():
			return "No gun (equip one from Tab)"
		hands = "gun"
		raising = float(stats()["handling"])
		reloading = 0.0
		return "%s in hand" % gear.gun_name()
	hands = "melee"
	reloading = 0.0
	return "%s in hand" % gear.weapon_name()


## One tick: timers run down, the spread settles, a finished reload loads the rounds from `inv`.
## Returns the rounds loaded this tick (0 if no reload finished).
func tick(dt: float, inv: Inventory) -> int:
	if hands == "gun" and gun().is_empty():
		hands = "melee"  # the gun was taken off
	cooldown = maxf(0.0, cooldown - dt)
	raising = maxf(0.0, raising - dt)
	var settle := float(stats()["settle"]) if not gun().is_empty() else 8.0
	bloom = maxf(0.0, bloom - settle * dt)
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			reloading = 0.0
			return _load(inv)
	return 0


## Spread multiplier from Firearms (3% tighter per level), never below min_spread_mult.
func spread_mult() -> float:
	return maxf(float(data.guns["min_spread_mult"]), 1.0 - skills.bonus("spread_cut"))


## The cone the world shoots into, in degrees: the gun's spread plus the recoil bloom, times spread_mult.
func spread_deg() -> float:
	if gun().is_empty():
		return 0.0
	return (float(stats()["spread"]) + bloom) * spread_mult()


## Chance a shot that's on target hits at `distance` m: 1 - 0.5 * (d / reach)^2, clamped to hit_chance,
## where reach = the gun's range (scope and accuracy stats raise it) / spread_mult (Firearms raises it).
## So at the gun's range a shot hits half the time, inside it nearly always.
func hit_chance(distance: float) -> float:
	if gun().is_empty():
		return 0.0
	var reach := float(stats()["range"]) / spread_mult()
	var span: Array = data.guns["hit_chance"]
	return clampf(1.0 - 0.5 * pow(distance / reach, 2.0), float(span[0]), float(span[1]))


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
func damage() -> float:
	var ammo: Dictionary = data.guns["ammo"][gun()["ammo"]]
	return float(stats()["damage"]) * (1.0 + skills.bonus("gun_damage")) * float(ammo["damage"])


## "" if a shot can be fired now, otherwise why not.
func can_fire() -> String:
	if not in_hand():
		return "No gun in hand (Q)"
	if reloading > 0.0:
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
	piece["loaded"] = int(piece["loaded"]) - 1
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
		reloading = reload_time()
		return "Reloading %s..." % data.item_name(piece["ammo"]).to_lower()
	if other == "":
		return "Magazine full" if full else "No %s (the workbench makes them)" % data.item_name(piece["ammo"]).to_lower()
	inv.add(piece["ammo"], int(piece["loaded"]))
	piece["loaded"] = 0
	piece["ammo"] = other
	reloading = reload_time()
	return "Switching to %s..." % data.item_name(other).to_lower()


func _other_ammo(inv: Inventory, current: String) -> String:
	var order: Array = data.guns["ammo_order"]
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


## The HUD line: "Pistol 6/8 standard (R reload, Q pipe)" or "Pipe (Q: Pistol)".
func hands_text() -> String:
	if not in_hand():
		return "Weapon: %s%s" % [gear.weapon_name(), ("   (Q: %s)" % gear.gun_name()) if not gun().is_empty() else ""]
	var piece := gun()
	var state := ""
	if reloading > 0.0:
		state = "  reloading"
	elif raising > 0.0:
		state = "  raising"
	return "Gun: %s  %d/%d %s%s   (Q: %s)" % [piece["name"], int(piece["loaded"]), int(stats()["magazine"]),
			data.item_name(piece["ammo"]).to_lower(), state, gear.weapon_name()]
