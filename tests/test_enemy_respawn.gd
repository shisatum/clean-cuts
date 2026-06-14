## Verifies death/respawn decoupling: with despawn_on_death = false, a killed
## enemy's corpse PERSISTS, yet the spawner still spawns the next enemy (driven
## by the `died` signal, not the corpse being freed).
##
## Run via:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/test_enemy_respawn.tscn
## Pass = exit code 0.  Fail = exit code 1.
extends Node3D

var _fail := false

func _ready() -> void:
	# EnemySpawner defers its first spawn; wait for the enemy to appear + settle.
	for _i: int in range(12):
		await get_tree().physics_frame
	_run()

func _run() -> void:
	var first: Array[Enemy] = _find_enemies()
	if first.size() != 1:
		_fail_msg("expected exactly 1 enemy after first spawn, got %d" % first.size())
		_quit()
		return
	_check(true, "first enemy spawned")
	var corpse: Enemy = first[0]
	var corpse_id: int = corpse.get_instance_id()

	# Kill it. despawn_on_death is false (default), so the corpse must persist;
	# `died` must still drive a respawn.
	corpse._kill()
	_check(corpse._dead, "killed enemy reports dead")

	# Wait past the (lowered) respawn_delay for the next spawn.
	for _i: int in range(40):
		await get_tree().physics_frame

	_check(is_instance_valid(corpse) and corpse.is_inside_tree(), "corpse persists (not despawned)")
	var now: Array[Enemy] = _find_enemies()
	_check(now.size() == 2, "corpse + respawned enemy both present (got %d)" % now.size())
	var has_new: bool = false
	for e: Enemy in now:
		if e.get_instance_id() != corpse_id:
			has_new = true
	_check(has_new, "respawned enemy is a new instance")
	_quit()

func _find_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for c: Node in get_children():
		if c is Enemy:
			out.append(c as Enemy)
	return out

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
