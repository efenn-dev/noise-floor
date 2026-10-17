extends SceneTree
## V37: renders the right first-person arm (Hands.make, so with the engine-built finger poses and the game's
## materials) in each of its six hand poses, side on and from the player's eye, into one contact sheet at
## .shots/hand_poses.png (rows: front, the player's eye, the index-finger side; a column per pose). For tuning Hands.POSE_BENDS against a new arm
## model without playing. Needs a window, like piece_icons.gd:
##     bash tools/godot.sh --path . --script res://tools/art/hand_poses.gd

const TILE := 360
const POSES := ["Grip", "Open", "Flat", "HoldMag", "Pinch", "Fist"]
## Camera positions in the arm's own space (grip at the origin, handle along +Y, forearm toward +Z, the right
## hand's back facing +X), each looking at the hand.
const VIEWS := [Vector3(0.0, 0.05, -0.42), Vector3(0.18, 0.22, 0.34), Vector3(0.03, -0.42, 0.01)]
const UPS := [Vector3.UP, Vector3.UP, Vector3(0, 0, -1)]
const LOOK_AT := Vector3(0.02, 0.0, 0.03)


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var sheet := Image.create(TILE * POSES.size(), TILE * VIEWS.size(), false, Image.FORMAT_RGBA8)
	for row in VIEWS.size():
		for column in POSES.size():
			var sub := SubViewport.new()
			sub.size = Vector2i(TILE, TILE)
			sub.own_world_3d = true
			sub.msaa_3d = Viewport.MSAA_4X
			sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(sub)
			var env := WorldEnvironment.new()
			var e := Environment.new()
			e.background_mode = Environment.BG_COLOR
			e.background_color = Color(0.16, 0.17, 0.19)
			e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			e.ambient_light_color = Color(0.85, 0.88, 0.95)
			e.ambient_light_energy = 0.6
			env.environment = e
			sub.add_child(env)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
			sub.add_child(sun)
			var arm := Hands.make("right")
			sub.add_child(arm)
			var handle := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.017
			cylinder.bottom_radius = 0.017
			cylinder.height = 0.3
			handle.mesh = cylinder
			handle.visible = POSES[column] == "Grip"
			sub.add_child(handle)
			Hands.set_pose(arm, POSES[column], 0.0)
			var cam := Camera3D.new()
			cam.fov = 40.0
			cam.near = 0.01
			sub.add_child(cam)
			cam.look_at_from_position(VIEWS[row], LOOK_AT, UPS[row])
			cam.current = true
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := sub.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i(column * TILE, row * TILE))
			sub.queue_free()
			await process_frame
	var out := ProjectSettings.globalize_path("res://.shots/hand_poses.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	print("hand_poses: ", "saved " + out if sheet.save_png(out) == OK else "FAILED")
	quit()
