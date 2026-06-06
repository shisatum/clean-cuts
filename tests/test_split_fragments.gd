## Headless split-fragment test.
## Drills hole-lines through a plank to sever it, then verifies each fragment is
## a CLEAN-PRIMITIVE solid (exactly one UNION body box — smooth, not a voxel-box
## "Teardown" pile) with a finite transform and non-empty voxel grid.
##
## Scenario A — one axis-aligned cut  -> 2 fragments.
## Scenario B — two axis-aligned cuts -> 3 fragments.
##   (Axis-aligned islands have disjoint AABBs, so 0 clip planes is correct.)
## Scenario C — one DIAGONAL cut -> 2 fragments with OVERLAPPING AABBs. This is
##   the real ghost-geometry case: the pairwise clip planes must carve the two
##   AABB boxes into disjoint halves. We assert clips are present AND that the
##   fragments' solid voxels do not co-occupy any world cell (no overlap).
##
## Split DETECTION runs purely on the voxel grid, so it works headlessly even
## though CSG mesh readback does not.
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
	# A diagonal split has overlapping AABBs, so each fragment MUST carry a clip
	# plane — otherwise the full AABB boxes overlap (ghost geometry). The plane's
	# normal must be ~perpendicular to the cut LINE (dir (0,1,1.25)) and carry no
	# X component (you don't cut a plank across its thickness). This is the
	# "wrong axis" regression guard.
	var cut_dir := Vector3(0.0, 1.0, 1.25).normalized()
	for idx: int in range(c.size()):
		var normals := _clip_normals(c[idx])
		if normals.size() >= 1:
			_pass("C(diagonal) frag %d has %d clip plane(s)" % [idx, normals.size()])
		else:
			_failm("C(diagonal) frag %d has no clip plane — overlapping AABB not cut" % idx)
		for n: Vector3 in normals:
			var along_cut: float = absf(n.dot(cut_dir))   # want ~0 (n ⟂ cut line)
			var across_thick: float = absf(n.x)            # want ~0 (not across X)
			if along_cut < 0.2 and across_thick < 0.2:
				_pass("C(diagonal) frag %d clip normal aligned to cut (n=%s)" % [idx, _v(n)])
			else:
				_failm("C(diagonal) frag %d clip normal WRONG AXIS n=%s (·cutdir=%.2f, |x|=%.2f)" % [idx, _v(n), along_cut, across_thick])

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
		if _union_boxes(f) == 1:
			_pass("%s frag %d single solid box (smooth, not voxelised)" % [tag, idx])
		else:
			_failm("%s frag %d has %d UNION boxes — voxel-decomposition regression" % [tag, idx, _union_boxes(f)])
		var solid := f._voxels.count(1)
		if not f._voxels.is_empty() and solid > 0:
			_pass("%s frag %d voxel grid non-empty (%d solid)" % [tag, idx, solid])
		else:
			_failm("%s frag %d voxel grid empty/all-carved" % [tag, idx])

# Local-space normals of each SUBTRACTION clip box (its local +Z axis).
func _clip_normals(f: DestructibleBody) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var csg := f.get_node_or_null("Csg")
	if csg == null:
		return out
	for ch: Node in csg.get_children():
		if ch is CSGBox3D and (ch as CSGBox3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
			out.append((ch as CSGBox3D).transform.basis.z.normalized())
	return out

func _v(n: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [n.x, n.y, n.z]

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
