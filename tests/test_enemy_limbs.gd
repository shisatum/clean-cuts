## Verifies the multi-part enemy assembly: structure (torso + 2 welded limbs),
## that the welds actually hold the limbs in place, and that a limb detaches
## (its weld is freed) when shot past the detach threshold.
##
## Run via:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/test_enemy_limbs.tscn
## Pass = exit code 0.  Fail = exit code 1.
extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

var _fail := false
var _enemy: Enemy

func _ready() -> void:
	_enemy = ENEMY_SCENE.instantiate() as Enemy
	_enemy.position = Vector3(0.0, 0.9, 0.0)
	add_child(_enemy)
	# Let the _ready cascade run and the welded assembly settle on the floor.
	for _i: int in range(10):
		await get_tree().physics_frame
	_run()

func _run() -> void:
	if _enemy == null:
		_fail_msg("enemy.tscn did not instantiate as Enemy")
		_quit()
		return

	# ── 1. Structure: 1 torso, 2 limbs, 2 welds ──────────────────────────────
	var torso := _enemy.get_node_or_null("Torso") as EnemyTorso
	var arm_l := _enemy.get_node_or_null("ArmL") as DestructibleBody
	var arm_r := _enemy.get_node_or_null("ArmR") as DestructibleBody
	var weld_l := _enemy.get_node_or_null("WeldL") as Generic6DOFJoint3D
	var weld_r := _enemy.get_node_or_null("WeldR") as Generic6DOFJoint3D
	_check(torso != null, "torso (EnemyTorso) present")
	_check(arm_l != null and arm_r != null, "two limb bodies present")
	_check(weld_l != null and weld_r != null, "two welds present")
	if torso == null or arm_l == null or weld_l == null:
		_quit()
		return
	_check(weld_l.node_a == NodePath("../Torso"), "weld node_a points at torso")
	_check(weld_l.node_b == NodePath("../ArmL"), "weld node_b points at limb")
	_check(_enemy._limbs.size() == 2, "container tracks 2 limbs (got %d)" % _enemy._limbs.size())
	_check(_enemy._joints.has(arm_l) and _enemy._joints.has(arm_r), "both arm welds mapped")

	# ── 2. The weld holds: arm keeps its offset in the TORSO'S LOCAL frame. ──
	# Measured local so it's invariant under the assembly chasing/yawing as a
	# rigid unit (world-space offset rotates with the body even on a perfect weld).
	var off_a: Vector3 = torso.to_local(arm_l.global_position)
	for _i: int in range(25):
		await get_tree().physics_frame
	var off_b: Vector3 = torso.to_local(arm_l.global_position)
	var drift: float = (off_b - off_a).length()
	print("[TEST] local off_a=%s off_b=%s" % [
		off_a.snapped(Vector3.ONE * 0.001), off_b.snapped(Vector3.ONE * 0.001)])
	_check(drift < 0.05, "weld holds limb to torso (local drift = %.3f m)" % drift)

	# ── 3. Shooting a limb past the detach threshold frees its weld ──────────
	_enemy._on_limb_mass_changed(0, arm_l)   # 0 solid → below limb_detach_fraction
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _enemy._joints.has(arm_l), "detached limb removed from weld map")
	_check(not is_instance_valid(weld_l), "detached limb's weld was freed")
	_check(is_instance_valid(weld_r), "other limb's weld still intact")
	_check(not torso._dead, "torso still alive after a limb drops")
	_check(not _enemy._dead, "enemy still alive after a limb drops")

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
