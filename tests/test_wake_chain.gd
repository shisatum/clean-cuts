## Headless wake-chain test.
## Verifies that waking a DestructibleBody propagates to nearby sleeping RigidBody3D nodes.
##
## Scenario A — _wake_nearby_sleeping() directly wakes a sleeping body in range.
## Scenario B — sleeping_state_changed(false) propagates through the signal path.
##
## Run: Godot_..._console.exe --headless --path <proj> res://tests/test_wake_chain.tscn
## Pass = exit 0, Fail = exit 1.
extends Node

var _fail := false

func _ready() -> void:
	await _test_direct_wake()
	await _test_signal_wake()
	_quit()

# A: _wake_nearby_sleeping() should set sleeping=false on a sleeping RigidBody3D in range.
func _test_direct_wake() -> void:
	var db := _make_db(Vector3.ZERO)
	# Remove db from the physics broadphase so it doesn't touch rb and wake it via
	# penetration resolution. The query in _wake_nearby_sleeping() doesn't need db
	# to be collidable — it uses its position and body_size, not its physics layer.
	db.collision_layer = 0
	db.collision_mask  = 0
	var rb := _make_rb(Vector3(0.3, 0.0, 0.0))  # within db's 0.275m query half-extent
	await get_tree().physics_frame
	rb.sleeping = true
	await get_tree().physics_frame
	if not rb.sleeping:
		_failm("A: rb not sleeping after manual set — Jolt overrode it (test setup issue)")
		return
	db._wake_nearby_sleeping()
	await get_tree().physics_frame
	if rb.sleeping:
		_failm("A: rb still sleeping after _wake_nearby_sleeping() — intersect_shape did not reach it")
	else:
		_pass("A: _wake_nearby_sleeping() woke nearby sleeping body")
	db.queue_free(); rb.queue_free()
	await get_tree().physics_frame

# B: setting sleeping=false on a DestructibleBody should chain-wake a nearby sleeping body
# via sleeping_state_changed → _on_sleeping_state_changed → _wake_nearby_sleeping().
func _test_signal_wake() -> void:
	var db := _make_db(Vector3(0.0, 0.0, 3.0))
	var rb := _make_rb(Vector3(0.3, 0.0, 3.0))
	await get_tree().physics_frame
	db.sleeping = true
	rb.sleeping = true
	await get_tree().physics_frame
	if not db.sleeping or not rb.sleeping:
		_failm("B: both bodies should be sleeping after manual set")
		return
	db.sleeping = false  # fires sleeping_state_changed → _on_sleeping_state_changed → _wake_nearby_sleeping
	await get_tree().physics_frame
	if rb.sleeping:
		_failm("B: rb still sleeping after db.sleeping = false — signal chain did not propagate")
	else:
		_pass("B: sleeping_state_changed chain-woke nearby sleeping body")
	db.queue_free(); rb.queue_free()
	await get_tree().physics_frame

func _make_db(pos: Vector3) -> DestructibleBody:
	var db := DestructibleBody.new()
	db.body_size = Vector3(0.5, 0.5, 0.5)
	db.gravity_scale = 0.0  # keep in place so sleeping state is controllable
	add_child(db)
	db.setup(db.body_size, null, StandardMaterial3D.new(), false)
	db.global_position = pos
	return db

func _make_rb(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.gravity_scale = 0.0
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(0.5, 0.5, 0.5)
	rb.add_child(col)
	add_child(rb)
	rb.global_position = pos
	return rb

func _pass(m: String) -> void:
	print("[TEST] PASS: %s" % m)

func _failm(m: String) -> void:
	print("[TEST] FAIL: %s" % m)
	_fail = true

func _quit() -> void:
	print("[TEST] done — %s" % ("FAIL" if _fail else "PASS"))
	get_tree().quit(1 if _fail else 0)
