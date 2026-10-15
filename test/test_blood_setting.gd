extends "res://test/base_test.gd"
## V32 (Emmitt: "add the blood toggle"): blood can be turned off in Settings. Off, a hit puffs dust instead of
## spraying blood and leaves no stains, for every caller (guns, melee, thrown things, bodies).


func test_blood_off_turns_sprays_to_dust_and_skips_stains() -> void:
	var was := Settings.blood
	Settings.blood = true
	eq(ImpactFx.shown_kind("blood"), "blood", "on: a hit sprays blood")
	eq(ImpactFx.shown_kind("blood_head"), "blood_head", "on: a headshot sprays more")
	Settings.blood = false
	eq(ImpactFx.shown_kind("blood"), "dust", "off: a body hit puffs dust")
	eq(ImpactFx.shown_kind("blood_head"), "dust", "off: so does a headshot")
	eq(ImpactFx.shown_kind("glass"), "glass", "other impacts are unchanged")
	var parent := Node3D.new()
	tree.root.add_child(parent)
	check(ImpactFx.stain(parent, Vector3.ZERO, Vector3.UP, 1.0) == null, "off: no blood stain")
	var puff := ImpactFx.spawn(parent, Vector3.ZERO, Vector3.UP, "blood")
	eq(puff.name, "Impact_dust", "off: the spawned puff is dust")
	Settings.blood = true
	var stain := ImpactFx.stain(parent, Vector3.ZERO, Vector3.UP, 1.0)
	check(stain != null, "on: stains are made")
	ImpactFx.clear_stains()
	check(stain.is_queued_for_deletion(), "turning blood off clears the stains already on the ground")
	Settings.blood = was
	parent.queue_free()
