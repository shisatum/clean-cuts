## Verifies the re-anchor LOGIC deterministically (no dependence on carving a clean
## fracture headless): given a fracture that produced a surviving fragment, the
## container moves each head/arm weld OFF the dying torso and ONTO the fragment, so
## those parts stay attached instead of being orphaned. Real in-game fractures are
## verified by playtest (CSG/voxel carving doesn't bisect reliably headless).
extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

var _fail := false
var _enemy: Enemy

func _ready() -> void:
	_enemy = ENEMY_SCENE.instantiate() as Enemy
	_enemy.position = Vector3(0.0, 0.9, 0.0)
	add_child(_enemy)
	for _i: int in range(10):
		await get_tree().physics_frame
	_run()

func _run() -> void:
	var torso := _enemy.get_node_or_null("Torso") as EnemyTorso
	var head := _enemy.get_node_or_null("Head") as DestructibleBody
	if torso == null or head == null:
		_fail_msg("missing torso/head")
		_quit()
		return

	var head_weld0: Generic6DOFJoint3D = _enemy._joints.get(head)
	_check(head_weld0 != null and head_weld0.get_node_or_null(head_weld0.node_a) == torso,
		"head weld initially anchored to the torso")

	# Simulate the fracture result: one surviving fragment where the torso is.
	var frag := DestructibleBody.new()
	_enemy.add_child(frag)
	frag.setup(Vector3(0.5, 0.7, 0.45), torso.material_data, torso.body_material, true)
	frag.global_position = torso.global_position
	await get_tree().physics_frame

	# Run the re-anchor path that torso.fractured would trigger.
	_enemy._on_torso_fractured([frag])
	await get_tree().physics_frame

	for part_name: String in ["Head", "ArmL", "ArmR"]:
		var part := _enemy.get_node_or_null(part_name) as DestructibleBody
		var weld: Generic6DOFJoint3D = _enemy._joints.get(part)
		_check(weld != null and is_instance_valid(weld), "%s weld exists after re-anchor" % part_name)
		if weld != null and is_instance_valid(weld):
			_check(weld.get_node_or_null(weld.node_a) == frag,
				"%s re-anchored onto the fragment (not the freed torso)" % part_name)
	_quit()

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("[TEST] PASS: %s" % msg)
	else:
		print("[TEST] FAIL: %s" % msg)
		_fail = true

func _fail_msg(msg: String) -> void:
	print("[TEST] FAIL: %s" % msg)
	_fail = true

func _quit() -> void:
	print("[TEST] done — %s" % ("FAIL" if _fail else "PASS"))
	get_tree().quit(1 if _fail else 0)
