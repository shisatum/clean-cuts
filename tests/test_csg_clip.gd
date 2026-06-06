extends Node

# Tests whether CSGCombiner3D's INTERSECTION and SUBTRACTION operations
# actually clip geometry, or silently return the unclipped base mesh.
# Run headlessly: Godot --headless --path <proj> res://tests/test_csg_clip.tscn

func _ready() -> void:
	var passed := 0
	var failed := 0

	for op_name: String in ["INTERSECTION", "SUBTRACTION"]:
		var op: int = CSGShape3D.OPERATION_INTERSECTION if op_name == "INTERSECTION" \
				else CSGShape3D.OPERATION_SUBTRACTION
		var ok: bool = _test_clip(op_name, op)
		if ok:
			print("PASS  csg_%s_clips_geometry" % op_name.to_lower())
			passed += 1
		else:
			printerr("FAIL  csg_%s_clips_geometry" % op_name.to_lower())
			failed += 1

	print("--- %d passed, %d failed ---" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# Creates a 2×1×1 base box (X from -1 to +1), then clips/subtracts to keep
# only the LEFT half (X <= 0).  Verifies all result vertices have X <= 0.
func _test_clip(op_name: String, op: int) -> bool:
	var csg := CSGCombiner3D.new()
	add_child(csg)

	# Base: 2 units wide box, X from -1 to +1
	var base := CSGBox3D.new()
	base.size = Vector3(2.0, 1.0, 1.0)
	csg.add_child(base)

	var clip := CSGBox3D.new()
	clip.size = Vector3(1000.0, 1000.0, 1000.0)
	clip.operation = op

	if op == CSGShape3D.OPERATION_INTERSECTION:
		# Box covers X from -1000 to 0: keeps left half
		clip.position = Vector3(-500.0, 0.0, 0.0)
	else:
		# SUBTRACTION: box covers X from 0 to +1000: removes right half
		clip.position = Vector3(500.0, 0.0, 0.0)

	csg.add_child(clip)

	var meshes: Array = csg.get_meshes()
	if meshes.size() < 2:
		printerr("  [%s] get_meshes returned %d elements (need >=2)" % [op_name, meshes.size()])
		csg.queue_free()
		return false

	var mesh := meshes[1] as ArrayMesh
	if mesh == null:
		printerr("  [%s] meshes[1] is not ArrayMesh" % op_name)
		csg.queue_free()
		return false

	if mesh.get_surface_count() == 0:
		printerr("  [%s] ArrayMesh has 0 surfaces" % op_name)
		csg.queue_free()
		return false

	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		printerr("  [%s] vertex array is empty" % op_name)
		csg.queue_free()
		return false

	var max_x: float = -INF
	for v: Vector3 in verts:
		max_x = maxf(max_x, v.x)

	print("  [%s] %d vertices, max X = %.4f (want <= 0.01)" % [op_name, verts.size(), max_x])
	csg.queue_free()
	return max_x <= 0.01
