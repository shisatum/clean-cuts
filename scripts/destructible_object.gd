extends CSGCombiner3D

const HOLE_RADIUS := 0.06
const HOLE_HEIGHT := 0.4

func apply_hole(global_hit_pos: Vector3, hit_normal: Vector3) -> void:
	var cyl := CSGCylinder3D.new()
	cyl.radius = HOLE_RADIUS
	cyl.height = HOLE_HEIGHT
	cyl.sides = 8
	cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
	add_child(cyl)
	_align_to_normal(cyl, global_hit_pos, hit_normal)

func _align_to_normal(node: Node3D, global_pos: Vector3, normal: Vector3) -> void:
	var y := normal.normalized()
	# Pick a reference vector not parallel to y
	var ref := Vector3.UP if abs(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), global_pos)
