## Windowed visual capture (NOT headless — CSG needs a real renderer).
## Drills a diagonal burst into a plank, lets the fragments part, screenshots the
## viewport to tests/capture.png, then quits. Used to eyeball that fragments cut
## on the correct (diagonal) axis with no cloned/overlapping geometry.
##
## Run: Godot_..._console.exe --path <proj> --resolution 1280x720 res://tests/visual_capture.tscn
extends Node3D

const OUT := "res://tests/capture_multi.png"

func _ready() -> void:
	# Lighting + environment so the plank is clearly visible.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.18, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(2.6, 1.3, 2.6), Vector3(0.0, 0.0, 0.0), Vector3.UP)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.45, 0.15)  # wood-ish, matches the user's view

	var body := DestructibleBody.new()
	add_child(body)
	body.setup(Vector3(0.15, 0.8, 2.5), null, mat, true)
	body.freeze = true   # keep it still until it severs

	await get_tree().physics_frame

	# Two vertical cuts (machine-gun sweep) at z=-0.5 and z=+0.5 -> three slabs.
	# This is the multi-island case that previously showed cloned geometry.
	for z0: float in [-0.5, 0.5]:
		for yi: int in range(-4, 5):
			body.apply_hole(Vector3(0.0, yi * 0.1, z0), Vector3(1.0, 0.0, 0.0), 100.0)

	# Let the split happen and the fragments part a little.
	for _i: int in range(12):
		await get_tree().process_frame
	# Freeze every fragment in place so the cut faces hold still for the shot.
	for ch: Node in get_children():
		if ch is DestructibleBody:
			var rb := ch as RigidBody3D
			rb.freeze = true
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
	for _i: int in range(4):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT)
	print("[CAPTURE] save_png -> %s err=%d  size=%s" % [OUT, err, str(img.get_size())])
	get_tree().quit(0)
