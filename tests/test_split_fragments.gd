## Headless split-fragment test.
## Drills a vertical line of holes through a plank until it severs in two, then
## verifies each fragment is a CLEAN-PRIMITIVE solid (one UNION body box + one
## SUBTRACTION clip plane), has a finite transform, and a non-empty voxel grid.
## This guards the Option-3 "plane-split for the visual face" fragment path
## against regressing to voxel-box (Teardown) fragments or INF/NaN transforms.
##
## Split DETECTION runs purely on the voxel grid, so it works headlessly even
## though CSG mesh readback does not.
##
## Run: Godot_..._console.exe --headless --path <proj> res://tests/test_split_fragments.tscn
## Pass = exit 0, Fail = exit 1.
extends Node

var _fail := false
var _original: Node = null  # untyped: it gets freed mid-test (the split frees it)

func _ready() -> void:
	var parent := Node3D.new()
	parent.name = "Arena"
	add_child(parent)

	var body := DestructibleBody.new()
	parent.add_child(body)
	body.setup(Vector3(0.15, 0.8, 2.5), null, StandardMaterial3D.new(), true)
	_original = body

	await get_tree().physics_frame

	# Vertical line of through-thickness holes at z=0 — severs the plank into a
	# z<0 half and a z>0 half.
	for yi: int in range(-4, 5):
		body.apply_hole(Vector3(0.0, yi * 0.1, 0.0), Vector3(1.0, 0.0, 0.0), 100.0)

	# Let the deferred _check_connectivity run and fragments enter the tree.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	_check(parent)
	_quit()

func _check(parent: Node3D) -> void:
	var frags: Array[DestructibleBody] = []
	for c: Node in parent.get_children():
		if c is DestructibleBody and c != _original:
			frags.append(c as DestructibleBody)

	if frags.size() == 2:
		_pass("plank severed into exactly 2 fragments")
	else:
		_failm("expected 2 fragments, got %d" % frags.size())

	if not is_instance_valid(_original):
		_pass("original body freed after split")
	else:
		_failm("original body still alive after split")

	for idx: int in range(frags.size()):
		var f := frags[idx]
		var t := f.global_transform
		if t.origin.is_finite() and t.basis.determinant() != 0.0:
			_pass("fragment %d transform finite" % idx)
		else:
			_failm("fragment %d transform not finite: %s" % [idx, str(t.origin)])

		var csg := f.get_node_or_null("Csg")
		if csg == null:
			_failm("fragment %d has no Csg" % idx)
			continue
		var union_boxes := 0
		var sub_boxes := 0
		var voxel_boxes := 0  # multiple UNION boxes => voxel-decomposition (Teardown) regression
		for ch: Node in csg.get_children():
			if ch is CSGBox3D:
				if (ch as CSGBox3D).operation == CSGShape3D.OPERATION_UNION:
					union_boxes += 1
				elif (ch as CSGBox3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
					sub_boxes += 1
		voxel_boxes = union_boxes
		if union_boxes == 1:
			_pass("fragment %d is a single solid box (smooth, not voxelised)" % idx)
		else:
			_failm("fragment %d has %d UNION boxes — voxel-decomposition regression" % [idx, voxel_boxes])
		if sub_boxes == 1:
			_pass("fragment %d has exactly one clip plane" % idx)
		else:
			_failm("fragment %d has %d clip planes (want 1)" % [idx, sub_boxes])

		var solid := f._voxels.count(1)
		if not f._voxels.is_empty() and solid > 0:
			_pass("fragment %d voxel grid non-empty (%d solid)" % [idx, solid])
		else:
			_failm("fragment %d voxel grid empty/all-carved" % idx)

func _pass(m: String) -> void:
	print("[TEST] PASS: %s" % m)

func _failm(m: String) -> void:
	print("[TEST] FAIL: %s" % m)
	_fail = true

func _quit() -> void:
	print("[TEST] done — %s" % ("FAIL" if _fail else "PASS"))
	get_tree().quit(1 if _fail else 0)
