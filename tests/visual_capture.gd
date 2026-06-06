## Windowed visual capture (NOT headless — CSG needs a real renderer).
## Tests three fracture scenarios side-by-side, freezes the fragments, screenshots.
## Verify: no ghost geometry, fragments sit flush (no hovering gap), correct shapes.
##
## Left  (-3 offset): two straight cuts -> three slabs.
## Centre (0 offset):  L-shaped cut     -> main body + top-right corner piece.
## Right (+3 offset):  circle of holes  -> inner disc + outer ring.
##
## Run: Godot_..._console.exe --path <proj> --resolution 1280x720 res://tests/visual_capture.tscn
extends Node3D

const OUT := "res://tests/capture_multi.png"

func _ready() -> void:
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
	# Looking along -X so the cut faces (in the YZ plane) are front-on.
	cam.look_at_from_position(Vector3(6.0, 1.5, 0.0), Vector3(0.0, 0.0, 0.0), Vector3.UP)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.45, 0.15)

	await get_tree().physics_frame

	# ── Scenario 1: two straight cuts -> three slabs ──────────────────────────
	var b1 := _make_plank(mat, Vector3(-3.0, 0.0, 0.0))
	for z0: float in [-0.5, 0.5]:
		for yi: int in range(-4, 5):
			b1.apply_hole(b1.global_position + Vector3(0.0, yi * 0.1, z0),
				Vector3(1.0, 0.0, 0.0), 100.0)

	# ── Scenario 2: L-shaped cut -> main body + corner ────────────────────────
	var b2 := _make_plank(mat, Vector3(0.0, 0.0, 0.0))
	# Horizontal row at y=0, right half (z: 0.4 to 1.25)
	for k: int in range(0, 10):
		b2.apply_hole(b2.global_position + Vector3(0.0, 0.0, 0.4 + k * 0.1),
			Vector3(1.0, 0.0, 0.0), 100.0)
	# Vertical row at z=0.4, upper half (y: 0.1 to 0.4)
	for k: int in range(1, 5):
		b2.apply_hole(b2.global_position + Vector3(0.0, k * 0.1, 0.4),
			Vector3(1.0, 0.0, 0.0), 100.0)

	# ── Scenario 3: ring of holes -> inner disc + outer ring ──────────────────
	var b3 := _make_plank(mat, Vector3(3.0, 0.0, 0.0))
	var ring_r: float = 0.22
	for k: int in range(12):
		var angle: float = k * TAU / 12.0
		b3.apply_hole(b3.global_position + Vector3(0.0, sin(angle) * ring_r, cos(angle) * ring_r),
			Vector3(1.0, 0.0, 0.0), 100.0)

	# Short wait: just enough for pieces to visibly separate, not tumble.
	for _i: int in range(8):
		await get_tree().process_frame
	for ch: Node in get_children():
		if ch is DestructibleBody:
			(ch as RigidBody3D).freeze = true
			(ch as RigidBody3D).linear_velocity  = Vector3.ZERO
			(ch as RigidBody3D).angular_velocity = Vector3.ZERO
	for _i: int in range(4):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT)
	print("[CAPTURE] save_png -> %s err=%d  size=%s" % [OUT, err, str(img.get_size())])
	get_tree().quit(0)

func _make_plank(mat: Material, pos: Vector3) -> DestructibleBody:
	var body := DestructibleBody.new()
	add_child(body)
	body.setup(Vector3(0.15, 0.8, 2.5), null, mat, true)
	body.global_position = pos
	body.freeze = true
	return body
