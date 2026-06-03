extends CSGCombiner3D

@export var material_data: MaterialData

func apply_hole(global_hit_pos: Vector3, direction: Vector3, energy: float) -> void:
	var hole: Vector2 = material_data.compute_hole(energy) if material_data \
		else (Vector2(0.06, 0.4) if energy >= 40.0 else Vector2.ZERO)

	if hole.x < 0.005:
		return

	var cyl := CSGCylinder3D.new()
	cyl.radius = hole.x
	cyl.height = hole.y
	cyl.sides = 8
	cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
	add_child(cyl)
	_align_to_direction(cyl, global_hit_pos, direction)

func _align_to_direction(node: Node3D, global_pos: Vector3, direction: Vector3) -> void:
	var y: Vector3 = direction.normalized()
	var ref: Vector3 = Vector3.UP if abs(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), global_pos)
