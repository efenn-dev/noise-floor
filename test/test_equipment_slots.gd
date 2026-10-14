extends "res://test/base_test.gd"
## V14 equipment: the full slot set, two firearm slots and hand cycling, wearable bags, clothing drops,
## version-14 migration, and the paper doll inventory screen.


func _gun(sim: SimWorld, base: String) -> Dictionary:
	var piece := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(piece)
	eq(sim.equip_gear(piece["uid"]), "Equipped " + piece["name"], "equip " + base)
	return piece


func test_slot_list_and_firearm_slots() -> void:
	var sim := SimWorld.new()
	eq(sim.gear.slots(), ["head", "body", "hands", "legs", "feet", "back", "light", "weapon", "primary", "sidearm"],
			"the character has every requested slot")
	var pistol := _gun(sim, "pistol")
	var rifle := _gun(sim, "hunting_rifle")
	eq(sim.gear.equipped["sidearm"], pistol, "a pistol equips as the sidearm")
	eq(sim.gear.equipped["primary"], rifle, "a rifle equips as the primary")
	check(not sim.gear.equipped.has("gun"), "there is no current-save gun slot")


func test_q_cycles_and_skips_empty_slots() -> void:
	var sim := SimWorld.new()
	var pistol := _gun(sim, "pistol")
	eq(sim.swap_hands(), "Pistol in hand", "empty primary is skipped")
	eq(sim.guns.hands, "sidearm", "sidearm in hand")
	eq(sim.swap_hands(), "Pipe in hand", "then back to melee")
	sim.gear.unequip("weapon")
	eq(sim.swap_hands(), "Pistol in hand", "fists still have a place in the cycle")
	eq(sim.swap_hands(), "Fists in hand", "empty melee means fists")
	sim.gear.unequip("sidearm")
	eq(sim.swap_hands(), "No firearm equipped (Tab)", "with no firearm Q stays on fists")
	check(not sim.gear.find(pistol["uid"]).is_empty(), "the unequipped pistol was not lost")


func test_current_hand_drives_gun_stats_and_firing() -> void:
	var sim := SimWorld.new()
	var pistol := _gun(sim, "pistol")
	var rifle := _gun(sim, "hunting_rifle")
	pistol["loaded"] = 2
	rifle["loaded"] = 2
	eq(sim.swap_hands(), "Hunting rifle in hand", "primary comes first")
	sim.guns.raising = 0.0
	eq(sim.gear.gun()["base"], "hunting_rifle", "Gear.gun is the primary in hand")
	near(float(sim.guns.stats()["damage"]), float(sim.data.guns["guns"]["hunting_rifle"]["damage"]), "rifle stats")
	eq(sim.fire(), "", "fires the primary")
	eq(rifle["loaded"], 1, "the rifle used the round")
	eq(pistol["loaded"], 2, "the sidearm did not")
	eq(sim.swap_hands(), "Pistol in hand", "then the sidearm")
	sim.guns.raising = 0.0
	sim.guns.cooldown = 0.0
	eq(sim.gear.gun()["base"], "pistol", "Gear.gun follows the sidearm hand")
	near(float(sim.guns.stats()["damage"]), float(sim.data.guns["guns"]["pistol"]["damage"]), "pistol stats")
	eq(sim.fire(), "", "fires the sidearm")
	eq(pistol["loaded"], 1, "the pistol used its round")


func test_only_the_worn_bag_counts_and_unequips() -> void:
	var sim := SimWorld.new()
	sim.inventory.give_all({"school_bag": 1, "hiking_pack": 1, "military_rucksack": 1})
	near(sim.carry_limit(), 20.0, "bags in pockets give no capacity")
	sim.equip_bag("school_bag")
	near(sim.carry_limit(), 28.0, "the school bag counts while worn")
	sim.equip_bag("hiking_pack")
	near(sim.carry_limit(), 38.0, "the replacement hiking pack counts")
	eq(sim.inventory.count("school_bag"), 1, "the old bag returned to pockets")
	eq(sim.inventory.count("military_rucksack"), 1, "a better bag in pockets still does not count")
	eq(sim.unequip_gear("back"), "Took off Hiking pack", "unequip the back slot")
	near(sim.carry_limit(), 20.0, "capacity goes back to the base")
	eq(sim.inventory.count("hiking_pack"), 1, "the bag fits back in pockets")
	check(not sim.gear.equipped.has("back"), "the back slot is empty")


func test_unequipped_bag_drops_when_pockets_are_too_heavy() -> void:
	var sim := SimWorld.new()
	sim.inventory.add("hiking_pack", 1)
	sim.equip_bag("hiking_pack")
	sim.inventory.add("plank", 30)
	check("dropped at your feet" in sim.unequip_gear("back"), "the message explains the drop")
	eq(sim.inventory.count("hiking_pack"), 0, "it did not overfill pockets")
	eq(sim.bags[0]["items"].get("hiking_pack", 0), 1, "the bag is recoverable on the ground")


func test_new_clothing_rolls_and_is_listed_in_its_loot_tables() -> void:
	var sim := SimWorld.new()
	var wanted := {"work_pants": false, "cargo_pants": false, "work_boots": false, "sneakers": false}
	for base: String in wanted:
		var def: Dictionary = sim.data.gear["bases"][base]
		check(def["slot"] in ["legs", "feet"], base + " uses a new clothing slot")
		for stat: String in def["base"]:
			check(sim.data.gear["stats"].has(stat), "%s uses existing stat %s" % [base, stat])
		for source: String in def["sources"]:
			check(base in sim.data.loot[source]["gear"], "%s is listed in %s loot" % [base, source])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1414
	for base: String in wanted:
		var rare := sim.gear._roll_as(rng, base, "civilian", "yellow")
		check(rare["stats"].size() >= 3 and rare["stats"].size() <= 5, base + " uses clothing rarity roll ranges")
	var sources := ["bathroom", "car_trunk", "factory_crate", "industrial", "zombie"]
	for i in 1000:
		var source: String = sources[i % sources.size()]
		sim.data.gear["containers"][source] = 1.0
		for piece: Dictionary in sim._search_gear({"id": "clothes_%d" % i, "table": source}):
			if wanted.has(piece["base"]):
				wanted[piece["base"]] = true
	check(wanted.values().all(func(found: bool) -> bool: return found), "every new base drops from its listed loot")
	var cargo := sim.gear.make("cargo_pants", "civilian", "white")
	sim.gear.pieces.append(cargo)
	var limit := sim.carry_limit()
	sim.gear.equip(cargo["uid"])
	near(sim.carry_limit(), limit + 3.0, "cargo pockets add a little carry capacity")
	var shoes := sim.gear.make("sneakers", "civilian", "white")
	sim.gear.pieces.append(shoes)
	var footstep := sim.noise_loudness("footstep_walk")
	sim.gear.equip(shoes["uid"])
	near(sim.noise_loudness("footstep_walk"), footstep - 2.0, "sneakers make footsteps quieter")


func test_version_14_fixture_moves_gun_and_best_bag_without_loss() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v14.json")
	eq(int(d.get("version", 0)), 14, "the fixture is a version-14 save")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	eq(sim.gear.equipped["sidearm"]["base"], "pistol", "the old pistol moved to sidearm")
	check(not sim.gear.equipped.has("gun"), "the old key is gone")
	eq(sim.guns.hands, "sidearm", "the held gun stays in hand")
	eq(sim.gear.equipped["back"], "hiking_pack", "the best carried bag is worn")
	eq(sim.inventory.count("hiking_pack"), 0, "one hiking pack moved out of pockets")
	eq(sim.inventory.count("school_bag"), 1, "the other bag was kept")
	near(sim.carry_limit(), float(sim.data.survival["carry_base"]) + sim.skills.bonus("carry_kg") + 18.0,
			"the migrated worn bag supplies capacity (the fixture's Strength adds its bonus too)")
	var current := SaveGame.to_dict(sim)
	eq(int(current["version"]), 15, "it saves back as version 15")
	var round_trip := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(round_trip, current), "", "the version-15 result loads again")
	eq(round_trip.gear.equipped["back"], "hiking_pack", "the worn bag survives a current round trip")
	eq(round_trip.gear.equipped["sidearm"]["base"], "pistol", "the sidearm survives too")
	var rifle_save := d.duplicate(true)
	rifle_save["gear"]["equipped"]["gun"]["base"] = "hunting_rifle"
	rifle_save["gear"]["equipped"]["gun"]["name"] = "Hunting rifle"
	var rifle_sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(rifle_sim, rifle_save), "", "a version-14 rifle save loads")
	eq(rifle_sim.gear.equipped["primary"]["base"], "hunting_rifle", "an old rifle moves to primary")


func test_character_screen_has_every_tile_and_uses_existing_icons() -> void:
	var sim := SimWorld.new()
	var screen := InventoryScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open()
	for slot: String in sim.gear.slots():
		check(screen.find_child("Slot_" + slot, true, false) is Button, "paper doll tile " + slot)
	var melee: Button = screen.find_child("Slot_weapon", true, false)
	var icon := melee.find_child("Icon", true, false) as TextureRect
	check(icon != null and icon.texture != null, "the pipe tile uses assets/icons/pipe.png")
	if icon != null:
		var frame := icon.get_parent() as Panel
		var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
		eq(style.border_color, sim.gear.color(sim.gear.equipped["weapon"]), "its border is the rarity colour")
	check(melee.find_child("Condition", true, false) is ColorRect, "filled gear tiles have a condition bar")
	screen.close()
	screen.free()


func test_double_click_equips_and_unequips_gear_and_bags() -> void:
	var sim := SimWorld.new()
	var hat := sim.gear.make("hard_hat", "civilian", "white")
	sim.gear.pieces.append(hat)
	sim.inventory.add("school_bag", 1)
	var screen := InventoryScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open()
	var double_click := InputEventMouseButton.new()
	double_click.button_index = MOUSE_BUTTON_LEFT
	double_click.double_click = true
	double_click.pressed = true
	screen._on_gear_input(double_click, int(hat["uid"]), InventoryScreen.POCKETS)
	eq(sim.gear.equipped["head"]["uid"], hat["uid"], "double-click equips gear")
	screen._on_gear_input(double_click, int(hat["uid"]), InventoryScreen.WORN)
	check(not sim.gear.equipped.has("head"), "double-clicking its character tile unequips it")
	screen._on_item_input(double_click, "school_bag", InventoryScreen.POCKETS)
	eq(sim.gear.equipped["back"], "school_bag", "double-click equips a bag")
	screen._on_equipment_input(double_click, "back")
	check(not sim.gear.equipped.has("back"), "double-clicking the back tile unequips it")
	screen.close()
	screen.free()
