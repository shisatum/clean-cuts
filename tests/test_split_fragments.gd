## Headless split-fragment test.
## Drills hole-lines through a plank to sever it, then verifies each fragment
## has a finite transform, a non-empty voxel grid, no SUBTRACTION clip boxes
## (greedy-box architecture — no half-space clip planes), and >= 1 UNION body box.
##
## Scenario A — one axis-aligned cut  -> 2 fragments (each exactly 1 UNION box).
## Scenario B — two axis-aligned cuts -> 3 fragments (each exactly 1 UNION box).
## Scenario C — one DIAGONAL cut -> 2 fragments (>= 1 UNION box each, stairstepped).
## Scenario D — L-shaped cut -> 2 fragments, verifies no clip-plane ghost geometry.
##
## Run: Godot_..._console.exe --headless --path <proj> res://tests/test_split_fragments.tscn
## Pass = exit 0, Fail = exit 1.
extends Node

var _fail := false

func _ready() -> void:
	var a: Array[DestructibleBody] = await _build_and_cut(_axis_line(0.0))
	_check_common(a, 2, "A(one cut)")

	var b: Array[DestructibleBody] = await _build_and_cut(_axis_line(-0.6) + _axis_line(0.6))
	_check_common(b, 3, "B(two cuts)")

	var c: Array[DestructibleBody] = await _build_and_cut(_diagonal_line())
	_check_common(c, 2, "C(diagonal)")

	var d: Array[DestructibleBody] = await _build_and_cut(_l_line())
	_check_common(d, 2, "D(L-cut)")

	_quit()

# ── hole-line generators (all drill through the 0.15m X thickness) ────────────
func _axis_line(z0: float) -> Array:
	var out: Array = []
	for yi: int in range(-4, 5):
		out.append({p = Vector3(0.0, yi * 0.1, z0), d = Vector3(1.0, 0.0, 0.0)})
	return out

func _diagonal_line() -> Array:
	# Corner-to-corner slash in the Y-Z face: z = 1.25*y. 17 holes (< the 20-hole
	# bake threshold) so the fragments stay inspectable CSG, dense enough to sever.
	var out: Array = []
	for k: int in range(-8, 9):
		var y: float = k * 0.05
		out.append({p = Vector3(0.0, y, y * 1.25), d = Vector3(1.0, 0.0, 0.0)})
	return out

func _l_line() -> Array:
	# L-shaped cut: horizontal row at y=0 (z: 0.4..1.25) + vertical row at z=0.4
	# (y: 0..0.4). Together they sever the top-right rectangle of the plank.
	var out: Array = []
	for k: int in range(0, 10):
		out.append({p = Vector3(0.0, 0.0, 0.4 + k * 0.1), d = Vector3(1.0, 0.0, 0.0)})
	for k: int in range(1, 5):
		out.append({p = Vector3(0.0, k * 0.1, 0.4), d = Vector3(1.0, 0.0, 0.0)})
	return out

func _build_and_cut(holes: Array) -> Array[DestructibleBody]:
	var parent := Node3D.new()
	add_child(parent)
	var body := DestructibleBody.new()
	parent.add_child(body)
	body.setup(Vector3(0.15, 0.8, 2.5), null, StandardMaterial3D.new(), true)
	await get_tree().physics_frame
	for h: Dictionary in holes:
		body.apply_hole(h.p, h.d, 100.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var frags: Array[DestructibleBody] = []
	for ch: Node in parent.get_children():
		if ch is DestructibleBody and is_instance_valid(ch) and not ch.is_queued_for_deletion():
			frags.append(ch as DestructibleBody)
	return frags

func _check_common(frags: Array[DestructibleBody], want: int, tag: String) -> void:
	if frags.size() == want:
		_pass("%s severed into %d fragments" % [tag, want])
	else:
		_failm("%s expected %d fragments, got %d" % [tag, want, frags.size()])
	for idx: int in range(frags.size()):
		var f := frags[idx]
		var t := f.global_transform
		if t.origin.is_finite() and t.basis.determinant() != 0.0:
			_pass("%s frag %d transform finite" % [tag, idx])
		else:
			_failm("%s frag %d transform not finite: %s" % [tag, idx, str(t.origin)])
		var ub: int = _union_boxes(f)
		if ub >= 1:
			_pass("%s frag %d has %d solid box(es)" % [tag, idx, ub])
		else:
			_failm("%s frag %d has no UNION boxes" % [tag, idx])
		# No SUBTRACTION CSGBox3D (clip planes) — greedy boxes replace them.
		if _sub_boxes(f) == 0:
			_pass("%s frag %d no clip planes" % [tag, idx])
		else:
			_failm("%s frag %d has %d clip plane(s) — unexpected" % [tag, idx, _sub_boxes(f)])
		var solid := f._voxels.count(1)
		if not f._voxels.is_empty() and solid > 0:
			_pass("%s frag %d voxel grid non-empty (%d solid)" % [tag, idx, solid])
		else:
			_failm("%s frag %d voxel grid empty/all-carved" % [tag, idx])

func _union_boxes(f: DestructibleBody) -> int:
	return _count_boxes(f, CSGShape3D.OPERATION_UNION)

func _sub_boxes(f: DestructibleBody) -> int:
	return _count_boxes(f, CSGShape3D.OPERATION_SUBTRACTION)

func _count_boxes(f: DestructibleBody, op: int) -> int:
	var csg := f.get_node_or_null("Csg")
	if csg == null:
		return -1
	var n := 0
	for ch: Node in csg.get_children():
		if ch is CSGBox3D and (ch as CSGBox3D).operation == op:
			n += 1
	return n

func _pass(m: String) -> void:
	print("[TEST] PASS: %s" % m)

func _failm(m: String) -> void:
	print("[TEST] FAIL: %s" % m)
	_fail = true

func _quit() -> void:
	print("[TEST] done — %s" % ("FAIL" if _fail else "PASS"))
	get_tree().quit(1 if _fail else 0)
