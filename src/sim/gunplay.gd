class_name Gunplay
extends RefCounted
## Guns in your hands (M14): what you're holding (Q swaps melee and gun), raising the gun, the spread
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


## How much a gun's range (the scope, "+% accuracy at range" rolls) tightens its cone: the base gun's range
## over this one's, so a scope's +60% range is a cone 1/1.6 as wide. 1.0 without range bonuses.
func sight_mult() -> float:
	if gun().is_empty():
		return 1.0
	var base: Dictionary = data.guns["guns"].get(gun().get("base", ""), {})
	var reach := float(stats()["range"])
	if base.is_empty() or reach <= 0.0:
		return 1.0
	return clampf(float(base["range"]) / reach, 0.1, 1.0)


## The cone the world shoots into, in degrees (half-angle): the gun's spread plus the recoil bloom, times
## spread_mult (Firearms) and sight_mult (scope and range). The ray is the only roll: what it meets is hit.
func spread_deg() -> float:
	if gun().is_empty():
		return 0.0
	return (float(stats()["spread"]) + bloom) * spread_mult() * sight_mult()


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


## V9: " 60%" once the melee weapon has some wear, " 20% worn out" when it's about to break; "" when mint.
func weapon_condition_text() -> String:
	if not gear.equipped.has("weapon"):
		return ""
	var piece: Dictionary = gear.equipped["weapon"]
	var c := float(piece["condition"])
	if c >= 0.995:
		return ""
	return " %d%%%s" % [roundi(c * 100.0), "" if gear.working(piece) else " worn out"]


## The HUD line: "Pistol 6/8 standard (R reload, Q pipe)" or "Pipe (Q: Pistol)".
func hands_text() -> String:
	if not in_hand():
		return "Weapon: %s%s%s" % [gear.weapon_name(), weapon_condition_text(),
				("   (Q: %s)" % gear.gun_name()) if not gun().is_empty() else ""]
	var piece := gun()
	var state := ""
	if reloading > 0.0:
		state = "  reloading"
	elif raising > 0.0:
		state = "  raising"
	return "Gun: %s  %d/%d %s%s   (Q: %s)" % [piece["name"], int(piece["loaded"]), int(stats()["magazine"]),
			data.item_name(piece["ammo"]).to_lower(), state, gear.weapon_name()]
