extends "res://test/base_test.gd"
## S4: jumpscare stings. A zombie you hadn't seen that is suddenly in front of you within 6 m fires "close"
## (once, with a cooldown; again only after it has been out of sight for a while); one you watched walk up
## doesn't. Four or more zombies starting to chase within three seconds fire "horde". SoundView plays each
## fired sting once.

const TICK := SimWorld.TICK
const AHEAD := Vector3(0, 0, -1)


func _zombie(h: Horde, pos: Vector3, los := true) -> ZombieBrain:
	var z := h.spawn("shambler", pos)
	z.los_clear = los
	return z


func test_a_zombie_suddenly_close_in_front_stings_once() -> void:
	var data := GameData.load_default()
	var h := Horde.new(data)
	var s := Scares.new()
	var me := Vector3.ZERO
	var z := _zombie(h, Vector3(0, 0, -4), false)  # 4 m ahead, behind a door (no line of sight)
	for i in 10:
		eq(s.tick(TICK, h.zombies, me, AHEAD, false).size(), 0, "nothing while it's out of sight")
	z.los_clear = true  # the door opens
	var fired := s.tick(TICK, h.zombies, me, AHEAD, false)
	eq(fired.size(), 1, "it's in your face: a sting")
	eq(fired[0]["kind"], "close", "a close one")
	eq(fired[0]["zombie"], z.id, "from that zombie")
	for i in 40:
		eq(s.tick(TICK, h.zombies, me, AHEAD, false).size(), 0, "not again while it stays in view")
	eq(s.count("close"), 1, "one on record")
	# Behind you: no sting, however close.
	var s2 := Scares.new()
	var h2 := Horde.new(data)
	_zombie(h2, Vector3(0, 0, 3))  # 3 m behind
	for i in 5:
		eq(s2.tick(TICK, h2.zombies, me, AHEAD, false).size(), 0, "a zombie behind you doesn't sting (you can't see it)")
	# Far away in view: no sting; walking up to you in view: still none (you watched it come).
	var s3 := Scares.new()
	var h3 := Horde.new(data)
	var far := _zombie(h3, Vector3(0, 0, -20))
	eq(s3.tick(TICK, h3.zombies, me, AHEAD, false).size(), 0, "20 m away is no surprise")
	var stung := 0
	for i in 100:
		far.pos.z += 0.17  # 17 m closer over 5 s, in plain view the whole way
		stung += s3.tick(TICK, h3.zombies, me, AHEAD, false).size()
	eq(stung, 0, "one you watched walk up never stings")
	# The dead don't sting.
	var s4 := Scares.new()
	var h4 := Horde.new(data)
	var d := _zombie(h4, Vector3(0, 0, -3))
	d.take_hit(1000.0, Vector3.ZERO, 0.0)
	eq(s4.tick(TICK, h4.zombies, me, AHEAD, false).size(), 0, "a corpse in front of you doesn't sting")
	# Nor does anything while you're dead.
	var s5 := Scares.new()
	var h5 := Horde.new(data)
	_zombie(h5, Vector3(0, 0, -3))
	eq(s5.tick(TICK, h5.zombies, me, AHEAD, true).size(), 0, "no stings while you're dead")


func test_out_of_sight_then_back_stings_again_after_the_cooldown() -> void:
	var h := Horde.new(GameData.load_default())
	var s := Scares.new()
	var z := _zombie(h, Vector3(0, 0, -4))
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 1, "first sight: a sting")
	z.los_clear = false  # it goes behind a wall
	for i in roundi(1.0 / TICK):
		s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false)
	z.los_clear = true
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 0, "back after one second: you knew it was there")
	z.los_clear = false
	for i in roundi((Scares.CLOSE_COOLDOWN + 0.5) / TICK):
		s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false)
	z.los_clear = true
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 1, "gone long enough and the cooldown over: it surprises you again")
	eq(s.count("close"), 2, "two on record")
	eq(s.fired.size(), 2, "kept for the world")


func test_a_mob_turning_on_you_stings() -> void:
	var h := Horde.new(GameData.load_default())
	var s := Scares.new()
	var zs: Array[ZombieBrain] = []
	for i in 5:
		zs.append(_zombie(h, Vector3(-10 - i * 2, 0, -30), false))  # out of sight, idle
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 0, "idle: nothing")
	for i in 3:
		zs[i].state = ZombieBrain.State.CHASE
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 0, "three chasing is not a mob")
	zs[3].state = ZombieBrain.State.CHASE
	var fired := s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false)
	eq(fired.size(), 1, "four within three seconds: a sting")
	eq(fired[0]["kind"], "horde", "a horde one")
	zs[4].state = ZombieBrain.State.CHASE
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 0, "a fifth right after doesn't sting again")
	for z in zs:
		z.state = ZombieBrain.State.IDLE
	for i in roundi(Scares.HORDE_WINDOW / TICK) + 2:
		s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false)
	for z in zs:
		z.state = ZombieBrain.State.CHASE
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 0, "all five again inside the cooldown: nothing")
	for i in roundi(Scares.HORDE_COOLDOWN / TICK) + 2:
		s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false)
	for z in zs:
		z.state = ZombieBrain.State.IDLE
	s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false)
	for z in zs:
		z.state = ZombieBrain.State.CHASE
	eq(s.tick(TICK, h.zombies, Vector3.ZERO, AHEAD, false).size(), 1, "after the cooldown a new mob stings again")
	eq(s.count("horde"), 2, "two on record")


func test_the_sim_feeds_it_and_the_world_plays_each_once() -> void:
	var sim := SimWorld.new()
	sim.player_pos = Vector3.ZERO
	sim.player_facing = AHEAD
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -3))
	z.los_clear = true
	sim.step()
	eq(sim.scares.count("close"), 1, "SimWorld runs the scares each tick")
	var view := SoundView.new()
	tree.root.add_child(view)
	view.setup(sim)
	view._process(0.0)
	eq(view.scares_played, 1, "SoundView plays the sting")
	view._process(0.0)
	sim.step()
	view._process(0.0)
	eq(view.scares_played, 1, "once")
	check(SoundView.stream("sting_close") != null and SoundView.stream("sting_horde") != null, "both stings exist (tools/audio/synth.py)")
	view.free()
	await tree.process_frame
