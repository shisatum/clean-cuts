## Diagnoses / guards the "parts fall off on death" bug. Kills an enemy via TORSO
## mass (no parts individually shot off), then checks that the head and arm welds
## survive the death transition and the parts stay attached as the corpse topples.
## If go_limp()'s axis-lock toggle re-creates the Jolt body and severs the welds,
## the parts drift away and this FAILS.
##
## Run via:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/test_enemy_death_intact.tscn
extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

var _fail := false
var _enemy: Enemy

func _ready() -> void:
	_enemy = ENEMY_SCENE.instantiate() as Enemy
	_enemy.position = Vector3(0.0, 0.9, 0.0)
	add_child(_enemy)
	for _i: int in range(12):
		await get_tree().physics_frame
	_run()

func _run() -> void:
	var torso := _enemy.get_node_or_null("Torso") as EnemyTorso
	var head := _enemy.get_node_or_null("Head") as DestructibleBody
	var arm_l := _enemy.get_node_or_null("ArmL") as DestructibleBody
	var weld_l := _enemy.get_node_or_null("WeldL") as Generic6DOFJoint3D
	var weld_head := _enemy.get_node_or_null("WeldHead") as Generic6DOFJoint3D
	if torso == null or head == null or arm_l == null:
		_fail_msg("assembly missing parts")
		_quit()
		return

	# Local offsets are invariant under rigid motion — if a weld holds, they stay
	# constant even as the corpse tips.
	var arm_off0: Vector3 = torso.to_local(arm_l.global_position)
	var head_off0: Vector3 = torso.to_local(head.global_position)

	# Clean kill: declare the torso destroyed (no shooting of arms/head).
	_enemy._on_vital_mass_changed(0, torso)
	_check(_enemy._dead, "enemy died on torso destruction")

	for _i: int in range(20):
		await get_tree().physics_frame

	_check(is_instance_valid(weld_l), "arm weld survived death")
	_check(is_instance_valid(weld_head), "head weld survived death")
	if is_instance_valid(torso) and is_instance_valid(arm_l):
		var d: float = (torso.to_local(arm_l.global_position) - arm_off0).length()
		_check(d < 0.15, "arm stayed attached to torso after death (drift %.3f m)" % d)
	if is_instance_valid(torso) and is_instance_valid(head):
		var d2: float = (torso.to_local(head.global_position) - head_off0).length()
		_check(d2 < 0.15, "head stayed attached to torso after death (drift %.3f m)" % d2)

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
