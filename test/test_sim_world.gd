extends "res://test/base_test.gd"


func test_ticks_are_fixed_regardless_of_frame_slicing() -> void:
	var smooth := SimWorld.new(8.0)
	var choppy := SimWorld.new(8.0)
	for i in 600:
		smooth.update(1.0 / 60.0)
	for d in [0.031, 0.002, 0.05, 0.017]:
		for i in 100:
			choppy.update(d)
	# Float rounding may leave the last tick a hair short; never more than one tick apart.
	check(absi(smooth.ticks - 200) <= 1, "10 s at 60 fps ~ 200 ticks (%d)" % smooth.ticks)
	check(absi(choppy.ticks - 200) <= 1, "10 s in uneven frames ~ 200 ticks (%d)" % choppy.ticks)
	var same := SimWorld.new(8.0)
	for i in choppy.ticks:
		same.step()
	eq(choppy.clock.time_of_day, same.clock.time_of_day, "clock depends only on tick count")


func test_clock_moves_one_hour_per_real_minute() -> void:
	var sim := SimWorld.new(8.0)
	for i in 60 * SimWorld.TICK_RATE:
		sim.step()
	near(sim.clock.time_of_day, 9.0, "60 s of ticks = 1 hour", 1e-4)


func test_partial_tick_waits() -> void:
	var sim := SimWorld.new()
	eq(sim.update(SimWorld.TICK * 0.5), 0, "half a tick runs nothing")
	eq(sim.update(SimWorld.TICK * 0.5), 1, "second half completes a tick")


func test_long_freeze_is_capped() -> void:
	var sim := SimWorld.new()
	eq(sim.update(30.0), SimWorld.MAX_TICKS_PER_UPDATE, "a 30 s hitch runs at most the cap")
	check(sim.update(0.0) <= 1, "and does not owe a backlog afterwards")


func test_paused_sim_does_not_tick() -> void:
	var sim := SimWorld.new()
	sim.paused = true
	sim.update(5.0)
	eq(sim.ticks, 0, "paused sim stays still")
