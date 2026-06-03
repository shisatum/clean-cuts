extends CSGCombiner3D

@export var material_data: MaterialData

const RADIUS_MAX  := 0.14   # radius at ultimate strength
const HEIGHT_FULL := 0.40   # depth at ultimate (punches clean through)
const HEIGHT_MIN  := 0.01   # minimum dent depth (near-zero energy)
const HEIGHT_YIELD := 0.08  # depth at exactly yield (surface scratch)

func apply_hole(global_hit_pos: Vector3, direction: Vector3, energy: float) -> void:
	if energy <= 0.0:
		return

	var yield_s: float    = material_data.yield_strength    if material_data else 40.0
	var ultimate_s: float = material_data.ultimate_strength if material_data else 800.0

	# Radius grows with sqrt(energy/ultimate) — perceptually linear
	var t: float      = sqrt(clamp(energy / ultimate_s, 0.0, 1.0))
	var radius: float = RADIUS_MAX * t
	if radius < 0.005:
		return  # imperceptibly small, skip geometry

	# Below yield: shallow dent that doesn't penetrate
	# Above yield: always punch fully through; only radius grows
	var height: float
	if energy < yield_s:
		height = lerpf(HEIGHT_MIN, HEIGHT_YIELD, energy / yield_s)
	else:
		height = HEIGHT_FULL

	var cyl := CSGCylinder3D.new()
	cyl.radius = radius
	cyl.height = height
	cyl.sides  = 8
	cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
	add_child(cyl)
	_align_to_direction(cyl, global_hit_pos, direction)

func _align_to_direction(node: Node3D, global_pos: Vector3, direction: Vector3) -> void:
	var y   := direction.normalized()
	var ref := Vector3.UP if abs(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x   := ref.cross(y).normalized()
	var z   := x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), global_pos)
