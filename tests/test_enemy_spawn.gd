## Verifies that EnemySpawner spawns a live Enemy that stays on the floor.
## Self-contained: the test scene provides its own floor and EnemySpawner.
##
## Run via:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/test_enemy_spawn.tscn
## Pass = exit code 0.  Fail = exit code 1.
extends Node

var _fail := false

func _ready() -> void:
	# EnemySpawner._ready() fires before this, so the enemy is already in the tree.
	# Wait 15 physics frames for Jolt to resolve gravity + floor contact.
	for _i: int in range(15):
		await get_tree().physics_frame
	_run()

func _run() -> void:
	var enemies: Array[Node] = []
	_collect_enemies(get_tree().get_root(), enemies)
	print("[TEST] enemies found in tree: %d" % enemies.size())

	# ── 1. At least one Enemy must exist ─────────────────────────────────────
	if enemies.size() == 0:
		_fail_msg("no Enemy node found after spawning")
		_quit()
		return
	_pass_msg("at least one Enemy exists")

	# ── 2. Enemy must be resting on the floor, not in the void ───────────────
	for e: Node in enemies:
		var enemy: Enemy = e as Enemy
		var y: float = enemy.global_position.y
		print("[TEST] enemy.global_position = %s" % str(enemy.global_position))
		if y < -1.0:
			_fail_msg("enemy fell through the floor (y = %.2f)" % y)
		elif y > 4.0:
			_fail_msg("enemy floating above floor (y = %.2f)" % y)
		else:
			_pass_msg("enemy resting on floor (y = %.2f)" % y)

	# ── 3. Enemy must not already be dead ────────────────────────────────────
	for e: Node in enemies:
		var enemy: Enemy = e as Enemy
		if enemy._dead:
			_fail_msg("enemy spawned already dead")
		else:
			_pass_msg("enemy is alive")

	_quit()

func _collect_enemies(node: Node, out: Array[Node]) -> void:
	if node is Enemy:
		out.append(node)
	for child: Node in node.get_children():
		_collect_enemies(child, out)

func _pass_msg(msg: String) -> void:
	print("[TEST] PASS: %s" % msg)

func _fail_msg(msg: String) -> void:
	print("[TEST] FAIL: %s" % msg)
	_fail = true

func _quit() -> void:
	print("[TEST] done — %s" % ("FAIL" if _fail else "PASS"))
	get_tree().quit(1 if _fail else 0)
