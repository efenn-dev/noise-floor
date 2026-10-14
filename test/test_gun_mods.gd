extends "res://test/base_test.gd"
## V23 Tarkov-style firearm slots: field fitting, visible stat deltas, inventory drag/drop, held models,
## loot availability and save compatibility. Gun rules remain in Gear/Gunplay; the screen only presents them.


func _gun(sim: SimWorld, base: String, equip: bool = false) -> Dictionary:
	var gun := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(gun)
	if equip:
		sim.equip_gear(int(gun["uid"]))
		sim.swap_hands()
		sim.guns.raising = 0.0
	return gun


func _part(sim: SimWorld, base: String) -> Dictionary:
	var part := sim.gear.make(base, "civilian", "white")
	sim.gear.pieces.append(part)
	return part


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / SimWorld.TICK):
		sim.step()


func _row(rows: Array, label: String) -> Dictionary:
	for row: Dictionary in rows:
		if row["label"] == label:
			return row
	return {}


func test_each_gun_owns_its_slots_in_data() -> void:
	var data := GameData.load_default()
	eq(Array(data.guns["guns"]["pistol"]["part_slots"]), ["muzzle", "magazine", "sight"],
			"the pistol has exactly its three attachment points")
	eq(Array(data.guns["guns"]["hunting_rifle"]["part_slots"]), ["muzzle", "magazine", "sight", "stock"],
			"the rifle adds a stock point")
	eq(data.validate(), PackedStringArray(), "per-gun slots and every part validate")


func test_field_fitting_targets_carried_equipped_and_container_guns() -> void:
	var sim := SimWorld.new(12.0)
	var pocket_gun := _gun(sim, "pistol")
	var suppressor := _part(sim, "oil_filter_suppressor")
	check(sim.attach_part_to_gun(int(pocket_gun["uid"]), int(suppressor["uid"]), "muzzle").begins_with(
			"Oil-filter suppressor fitted"), "a carried gun can be modified without a bench")
	sim.step()
	eq(sim.noise.recent.back()["kind"], "gun_mod", "fitting makes the small data-driven handling noise")
	near(float(sim.noise.recent.back()["loudness"]), float(sim.data.noise["sounds"]["gun_mod"]),
			"the handling noise uses data/noise.json")
	eq(sim.detach_part_from_gun(int(pocket_gun["uid"]), "muzzle"), "Oil-filter suppressor removed",
			"a carried gun can be stripped into pockets")

	var equipped := _gun(sim, "hunting_rifle", true)
	var stock := _part(sim, "padded_stock")
	check(sim.attach_part_to_gun(int(equipped["uid"]), int(stock["uid"]), "stock").contains("fitted"),
			"an equipped Primary can be modified")

	var container_gun := sim.gear.make("pistol", "civilian", "white")
	sim.loot.add("test_case", "car_trunk", Vector3.ZERO)
	sim.loot.containers["test_case"]["searched"] = true
	sim.loot.add_gear("test_case", [container_gun])
	var scope := _part(sim, "scope")
	check(sim.attach_part_to_gun(int(container_gun["uid"]), int(scope["uid"]), "sight", "test_case").contains("fitted"),
			"a gun in the open container can be modified")
	eq(container_gun["parts"]["sight"]["uid"], scope["uid"], "the container's actual gun changed")


func test_wrong_slot_and_wrong_gun_are_refused() -> void:
	var sim := SimWorld.new()
	var pistol := _gun(sim, "pistol")
	var scope := _part(sim, "scope")
	var melee: Dictionary = sim.gear.equipped["weapon"]
	eq(sim.can_attach_part_to_gun(int(melee["uid"]), int(scope["uid"])), "Select a firearm first",
			"a melee weapon is not a mod target")
	check(sim.can_attach_part_to_gun(int(pistol["uid"]), int(scope["uid"]), "muzzle").contains(
			"sight slot, not muzzle"), "a sight refuses the muzzle tile")
	var stock := _part(sim, "padded_stock")
	check(sim.attach_part_to_gun(int(pistol["uid"]), int(stock["uid"]), "stock").contains("no stock slot"),
			"a rifle stock refuses a pistol")
	check(pistol["parts"].is_empty(), "refused fits change nothing")


func test_every_part_changes_the_live_gun_rule() -> void:
	var quiet := SimWorld.new(12.0)
	var quiet_gun := _gun(quiet, "pistol", true)
	quiet_gun["loaded"] = 1
	var suppressor := _part(quiet, "machined_suppressor")
	quiet.attach_part_to_gun(int(quiet_gun["uid"]), int(suppressor["uid"]), "muzzle")
	eq(quiet.fire(), "", "the suppressed gun fires")
	quiet.step()
	near(float(quiet.noise.recent.back()["loudness"]), 55.0, "the shot entering the noise sim is 30 quieter")

	var magazine := SimWorld.new()
	var mag_gun := _gun(magazine, "pistol", true)
	var extended := _part(magazine, "extended_mag")
	magazine.attach_part_to_gun(int(mag_gun["uid"]), int(extended["uid"]), "magazine")
	magazine.inventory.add("ammo_standard", 20)
	magazine.reload()
	_run(magazine, 2.0)
	eq(mag_gun["loaded"], 12, "the extended magazine really loads twelve rounds")

	var aimed := SimWorld.new()
	var aimed_gun := _gun(aimed, "pistol", true)
	aimed.guns.aiming = true
	var iron_cone := aimed.guns.spread_deg()
	var scope := _part(aimed, "scope")
	aimed.attach_part_to_gun(int(aimed_gun["uid"]), int(scope["uid"]), "sight")
	near(aimed.guns.spread_deg(), iron_cone / 1.6, "the scope tightens the live aimed cone")

	var recoil := SimWorld.new()
	var rifle := _gun(recoil, "hunting_rifle", true)
	rifle["loaded"] = 2
	var bare_kick := float(recoil.gear.gun_stats(rifle)["recoil"])
	var stock := _part(recoil, "padded_stock")
	recoil.attach_part_to_gun(int(rifle["uid"]), int(stock["uid"]), "stock")
	recoil.guns.fire()
	near(recoil.guns.bloom, bare_kick * 0.65, "the stock cuts the recoil bloom applied by Gunplay.fire")


func test_stat_rows_are_sim_computed_with_better_and_worse_deltas() -> void:
	var sim := SimWorld.new()
	var gun := _gun(sim, "hunting_rifle")
	for base: String in ["machined_suppressor", "extended_mag", "scope", "padded_stock"]:
		var part := _part(sim, base)
		if base == "scope":
			part["stats"]["recoil_cut"] = -1.0  # exercise the panel's red path as well as current good parts
		sim.attach_part_to_gun(int(gun["uid"]), int(part["uid"]))
	var rows := sim.gear.gun_stat_rows(gun)
	eq(rows.size(), 6, "damage, recoil, accuracy, handling, magazine and loudness are shown")
	for label: String in ["Accuracy cone", "Magazine", "Loudness"]:
		var row := _row(rows, label)
		check(not row.is_empty() and row["delta_text"] != "" and row["better"], label + " has a green improvement")
	var recoil_row := _row(rows, "Recoil")
	check(recoil_row["delta_text"] != "" and not recoil_row["better"], "an adverse aggregate recoil delta is marked red")
	eq(_row(rows, "Damage")["delta_text"], "", "unchanged damage has no invented UI delta")
	eq(_row(rows, "Raise time")["delta_text"], "", "unchanged handling still has a row")


func test_inventory_panel_builds_slots_icons_and_drag_drop() -> void:
	var sim := SimWorld.new()
	var gun := _gun(sim, "pistol")
	var suppressor := _part(sim, "oil_filter_suppressor")
	var screen := InventoryScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open()
	screen.select_gear(int(gun["uid"]), InventoryScreen.POCKETS)
	check(screen.mod_panel_visible(), "selecting a pocket gun opens MODDING")
	eq(screen._mod_slots.get_child_count(), 3, "one tile per pistol slot")
	check(screen.mod_slot("muzzle") != null and screen.mod_slot("stock") == null, "the panel follows that gun's data")
	var payload := screen.drag_data(InventoryScreen.GEAR + str(suppressor["uid"]), InventoryScreen.POCKETS)
	check(screen.can_drop(payload, "mod:muzzle"), "a pocket suppressor can drop on muzzle")
	check(screen.drop_data(payload, "mod:muzzle").begins_with("Oil-filter suppressor fitted"), "the drop fits it")
	var fitted := screen.mod_slot("muzzle")
	check(fitted != null and fitted.find_child("Icon", true, false) != null, "the fitted tile shows the part icon")
	var off := screen.drag_data(InventoryScreen.MOD_PART + "muzzle", InventoryScreen.MOD)
	check(screen.can_drop(off, InventoryScreen.POCKETS), "a fitted part can be dragged off")
	screen.drop_data(off, InventoryScreen.POCKETS)
	check(gun["parts"].is_empty() and sim.gear.pieces.has(suppressor), "dragging off returns it to pockets")
	sim.equip_gear(int(gun["uid"]))
	screen.select_gear(int(gun["uid"]), InventoryScreen.WORN)
	check(screen.mod_panel_visible() and screen.mod_slot("sight") != null,
			"selecting the Sidearm character tile opens the same panel")
	var crate_gun := sim.gear.make("hunting_rifle", "civilian", "white")
	sim.loot.add("mod_panel_crate", "factory_crate", Vector3.ZERO)
	sim.loot.containers["mod_panel_crate"]["searched"] = true
	sim.loot.add_gear("mod_panel_crate", [crate_gun])
	screen.open_container("mod_panel_crate")
	screen.select_gear(int(crate_gun["uid"]), InventoryScreen.CRATE)
	check(screen.mod_panel_visible() and screen.mod_slot("stock") != null,
			"selecting a container rifle opens its four-slot panel")
	screen.queue_free()
	await tree.process_frame


func test_part_models_use_each_guns_measured_mounts() -> void:
	for path: String in Shooter.PART_MODELS.values():
		check(ResourceLoader.exists(path), path + " exists")
	var sim := SimWorld.new()
	var camera := Camera3D.new()
	tree.root.add_child(camera)
	var shooter := Shooter.new()
	tree.root.add_child(shooter)
	var builder := BuildController.new()
	var excludes: Array[RID] = []
	shooter.setup(sim, camera, builder, excludes)
	for gun_id: String in Shooter.MODELS:
		var gun_node: Node3D = shooter._models[gun_id]
		for part_id: String in Shooter.PART_MODELS:
			var slot := str(sim.data.guns["parts"][part_id]["slot"])
			if not slot in sim.data.guns["guns"][gun_id]["part_slots"]:
				continue
			var mount := gun_node.find_child("AttachmentMount_" + part_id, true, false) as Node3D
			check(mount != null, "%s has a mount for %s" % [gun_id, part_id])
			if mount != null:
				check(mount.position.is_equal_approx(Shooter.ATTACHMENT_ANCHORS[gun_id][slot]),
						"%s %s is on its measured %s anchor" % [gun_id, part_id, slot])
				check(mount.find_child("Attachment_" + part_id, true, false) != null, "the part model is below that mount")
	shooter.free()
	camera.free()
	builder.free()


func test_scoped_ads_centres_the_optic_within_three_mm() -> void:
	for gun_id: String in Shooter.MODELS:
		var pose := Shooter.aim_pose(gun_id, true)
		var position: Vector3 = pose["position"]
		var rotation: Vector3 = pose["rotation"]
		var basis := Basis.from_euler(rotation)
		var points: Dictionary = Shooter.SCOPE_SIGHT_POINTS[gun_id]
		var rear := position + basis * (points["rear"] as Vector3)
		var front := position + basis * (points["front"] as Vector3)
		near(rear.x, 0.0, gun_id + " scope rear horizontal", 0.003)
		near(rear.y, 0.0, gun_id + " scope rear vertical", 0.003)
		near(front.x, 0.0, gun_id + " scope front horizontal", 0.003)
		near(front.y, 0.0, gun_id + " scope front vertical", 0.003)
		check(front.z < rear.z, gun_id + " optic looks forward")


func test_every_loot_area_can_drop_every_part() -> void:
	var sim := SimWorld.new()
	var expected: Array = sim.data.guns["parts"].keys()
	expected.sort()
	for source: String in ["car_trunk", "factory_crate", "industrial", "zombie"]:
		var seen := {}
		for i in 6000:
			var out := sim._search_guns({"id": "%s_mod_%d" % [source, i], "table": source})
			for piece: Dictionary in out["pieces"]:
				if sim.gear.slot_of(piece) == "part":
					seen[piece["base"]] = true
		var found: Array = seen.keys()
		found.sort()
		eq(found, expected, source + " can produce every firearm part")


func test_fitted_parts_save_round_trip() -> void:
	var sim := SimWorld.new()
	var gun := _gun(sim, "hunting_rifle", true)
	for base: String in ["machined_suppressor", "extended_mag", "scope", "padded_stock"]:
		var part := _part(sim, base)
		sim.attach_part_to_gun(int(gun["uid"]), int(part["uid"]))
	gun["loaded"] = 7
	var saved := SaveGame.to_dict(sim)
	var loaded := SimWorld.new()
	eq(SaveGame.apply(loaded, saved), "", "the current save loads")
	var restored := loaded.gear.gun()
	eq(restored["parts"].keys().size(), 4, "all four fitted slots survive")
	for slot: String in ["muzzle", "magazine", "sight", "stock"]:
		eq(restored["parts"][slot]["base"], gun["parts"][slot]["base"], slot + " part survives")
	eq(restored["loaded"], 7, "the extended magazine's rounds survive too")


func test_old_unsupported_pistol_stock_returns_to_pockets_on_load() -> void:
	var sim := SimWorld.new()
	var pistol := _gun(sim, "pistol")
	var stock := _part(sim, "padded_stock")
	sim.gear.take(int(stock["uid"]))
	pistol["parts"]["stock"] = stock  # legal before V23's per-gun slot data
	var saved := SaveGame.to_dict(sim)
	var loaded := SimWorld.new()
	eq(SaveGame.apply(loaded, saved), "", "the legacy-shaped version 18 save still loads")
	var restored := loaded.gear.find(int(pistol["uid"]))
	check(not restored["parts"].has("stock"), "the pistol no longer keeps an unsupported hidden slot")
	check(loaded.gear.pieces.any(func(piece: Dictionary) -> bool: return piece["uid"] == stock["uid"]),
			"the legacy stock is safely returned to pockets")
