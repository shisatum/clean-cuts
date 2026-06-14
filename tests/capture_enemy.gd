## Windowed visual capture (NOT headless — CSG needs a real renderer) for the
## multi-part enemy. Shoots two PNGs:
##   capture_enemy_before.png — intact figure (head + torso + two welded arms)
##   capture_enemy_after.png  — head shot up + destroyed -> the whole enemy
##                              topples (headshot kill, locomotion released).
## Read both and verify the head reads on top of the torso and a headshot
## topples the body.
##
## Run: Godot_..._console.exe --path <proj> --resolution 1280x720 res://tests/capture_enemy.tscn
extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const OUT_BEFORE := "res://tests/capture_enemy_before.png"
const OUT_AFTER := "res://tests/capture_enemy_after.png"

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

	# Floor.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20.0, 0.4, 20.0)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	add_child(floor_body)

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(1.7, 1.1, 2.7), Vector3(0.1, 0.55, 0.0), Vector3.UP)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.move_speed = 0.0   # stand still for the capture (don't chase the camera)
	enemy.position = Vector3(0.0, 0.9, 0.0)
	add_child(enemy)

	# Settle on the floor.
	for _i: int in range(25):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	_save(OUT_BEFORE)

	# Shoot up the head (visible holes), then destroy it — a headshot releases the
	# upright lock and the whole enemy topples.
	var head := enemy.get_node_or_null("Head") as DestructibleBody
	if head != null:
		for k: int in range(4):
			head.apply_hole(head.global_position + Vector3(-0.1 + k * 0.06, 0.04, 0.0),
				Vector3(0.0, 0.0, 1.0), 110.0)
		await get_tree().physics_frame
		enemy._on_vital_mass_changed(0, head)   # head destroyed -> death

	# Let the body topple.
	for _i: int in range(40):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	_save(OUT_AFTER)

	get_tree().quit(0)

func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[CAPTURE] save_png -> %s err=%d size=%s" % [path, err, str(img.get_size())])
