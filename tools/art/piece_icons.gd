extends SceneTree
## S4: renders every piece you can build (BuildController.PIECES) the way BuildView draws it, from a
## three-quarter angle on a transparent background, to assets/icons/piece_<id>.png (ICON px square), for the
## hotbar and the build menu. Deterministic; re-run after a model or BuildView change. Needs a window with a
## real renderer (Emmitt's PC, or Xvfb + the Compatibility renderer in the cloud):
##     bash tools/godot.sh --path . --script res://tools/art/piece_icons.gd
## Then run tools/test.sh once so Godot writes the .import files, and commit both. F5: `-- --only=a,b` renders just
## those pieces (new ones), leaving every other picture as it is.

const ICON := 160
const OUT := "res://assets/icons/piece_%s.png"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var data := GameData.load_default()
	var made := 0
	var only: Array = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1).split(",")
	for id: String in BuildController.PIECES:
		if not data.buildables.has(id) or (not only.is_empty() and not only.has(id)):
			continue
		var sub := SubViewport.new()
		sub.size = Vector2i(ICON, ICON)
		sub.transparent_bg = true
		sub.own_world_3d = true
		sub.msaa_3d = Viewport.MSAA_4X
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sub)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0, 0, 0, 0)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.85, 0.88, 0.95)
		e.ambient_light_energy = 0.7
		env.environment = e
		sub.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
		sun.light_energy = 1.3
		sub.add_child(sun)
		var grid := BuildGrid.new(data)
		var key := grid.key_for(id, Vector2i(0, 0), BuildGrid.Side.NORTH)
		grid.restore(key, {"id": id, "cell": Vector2i(0, 0), "side": BuildGrid.Side.NORTH, "hp": data.buildables[id]["hp"]})
		var view := BuildView.new()
		sub.add_child(view)
		view.setup(grid)
		var size: Vector3 = data.buildables[id]["size"]
		var center := grid.piece_center(key)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		# A flat piece (foundation, solar panel) is seen more from above; a tall one (pole) more from the side.
		var flat := size.y < 0.4 * maxf(size.x, size.z)
		var pitch := -55.0 if flat else (-18.0 if size.y > 2.0 * maxf(size.x, size.z) else -30.0)
		var dir := Basis(Vector3.UP, deg_to_rad(35.0)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Vector3(0, 0, 1)
		cam.size = size.length() * 1.05
		cam.near = 0.1
		cam.far = 60.0
		sub.add_child(cam)  # in the tree first: look_at needs a world
		cam.look_at_from_position(center + dir * 20.0, center, Vector3.UP)
		cam.current = true
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := sub.get_texture().get_image()
		var err := img.save_png(ProjectSettings.globalize_path(OUT % id))
		print("%s %s" % ["icon" if err == OK else "FAILED", id])
		if err == OK:
			made += 1
		sub.queue_free()
		await process_frame
	print("piece_icons: %d icons" % made)
	quit()
