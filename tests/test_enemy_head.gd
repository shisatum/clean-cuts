## Verifies the vital-part death model:
##   * head is a VITAL part (tracked for death), not a detachable limb
##   * losing every limb does NOT kill the enemy
##   * a vital part (head) above the death threshold keeps it alive
##   * a vital part (head) at/below the threshold kills it (torso goes limp)
##
## Run via:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/test_enemy_head.tscn
## Pass = exit code 0.  Fail = exit code 1.
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
	var arm_l := _enemy.get_node_or_null("ArmL") as DestructibleBody
	var arm_r := _enemy.get_node_or_null("ArmR") as DestructibleBody
	if torso == null or head == null or arm_l == null or arm_r == null:
		_fail_msg("missing torso/head/arms in assembly")
		_quit()
		return

	# ── 1. Head is a vital part, not a limb ──────────────────────────────────
	_check(not _enemy._limbs.has(head), "head is not tracked as a limb")
	_check(_enemy._vital_initial.has(head), "head is tracked as a vital part")
	_check(_enemy._vital_initial.has(torso), "torso is tracked as a vital part")
	var head_init: int = _enemy._vital_initial.get(head, 0)
	_check(head_init > 0, "head has an initial voxel count (%d)" % head_init)

	# ── 2. Losing every limb does NOT kill the enemy ─────────────────────────
	_enemy._on_limb_mass_changed(0, arm_l)
	_enemy._on_limb_mass_changed(0, arm_r)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _enemy._dead, "enemy alive after BOTH arms detached")
	_check(not torso._dead, "torso still upright after both arms detached")

	# ── 3. Head above the death threshold → still alive ──────────────────────
	_enemy._on_vital_mass_changed(int(head_init * 0.6), head)   # 60% > 50% remaining
	await get_tree().physics_frame
	_check(not _enemy._dead, "enemy alive with head above death threshold")

	# ── 4. Head at/below the threshold → dead (torso goes limp) ──────────────
	_enemy._on_vital_mass_changed(int(head_init * 0.4), head)   # 40% <= 50% remaining
	await get_tree().physics_frame
	_check(_enemy._dead, "enemy dead after head dropped below threshold")
	_check(torso._dead, "torso went limp on head destruction")

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
