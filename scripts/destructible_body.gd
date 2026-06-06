class_name DestructibleBody
extends RigidBody3D

@export var material_data: MaterialData
@export var body_material: Material
@export var body_size: Vector3 = Vector3(0.15, 0.8, 2.5)

const TARGET_VOXELS     := 900
const MIN_FRAG_FRACTION := 0.08

## Emitted after each hole is applied with the number of solid voxels remaining.
## Connect to this signal to track mass loss (e.g. for enemy health thresholds).
signal mass_changed(solid_count: int)

var _csg: CSGCombiner3D
var _last_hit_dir: Vector3
var _severing := false

# Called automatically for scene-placed nodes (planks).
func _ready() -> void:
	_csg = get_node_or_null("Csg") as CSGCombiner3D
	if _csg == null:
		return
	_csg.use_collision = false
	var body_nd: Node = _csg.get_node_or_null("Body")
	if body_nd is CSGBox3D:
		body_size = (body_nd as CSGBox3D).size
		if body_material == null:
			body_material = (body_nd as CSGBox3D).material
	_init_colliders()

# Called immediately after add_child() for dynamically spawned fragments.
func setup(size: Vector3, mat: MaterialData, body_mat: Material,
		create_body_box: bool = true) -> void:
	body_size     = size
	material_data = mat
	body_material = body_mat
	_csg = CSGCombiner3D.new()
	_csg.name = "Csg"
	_csg.use_collision = false
	add_child(_csg)
	if create_body_box:
		var box := CSGBox3D.new()
		box.size     = size
		box.material = body_mat
		_csg.add_child(box)
	_init_colliders()

func _init_colliders() -> void:
	# Join layer 2 so raycasts (collision_mask = 2) detect this body directly
	# via its own physics shape. A child Area3D was tried first, but Jolt does
	# not reliably register Area3D shapes for dynamic-body children — it works
	# for frozen/static parents but misses for moving bodies like enemies and
	# fragments. Using the RigidBody3D itself on layer 2 is simpler and stable.
	collision_layer = collision_layer | 2
	# Scene-placed bodies should define CollisionShape3D in the scene file so
	# Jolt registers it at body-creation time (not deferred). Dynamically
	# spawned fragments have no scene shape, so we create one here.
	var has_phys_shape: bool = get_children().any(
		func(c: Node) -> bool: return c is CollisionShape3D)
	if not has_phys_shape:
		var col       := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = body_size
		col.shape = box_shape
		add_child(col)

# Adds one solid box to build up a fragment's base shape voxel-by-voxel.
func add_body_box(local_pos: Vector3, sz: Vector3) -> void:
	var b := CSGBox3D.new()
	b.size     = sz
	b.material = body_material
	b.position = local_pos
	_csg.add_child(b)

# Copies an existing hole cylinder (by world transform) into this body's CSG tree.
func add_hole_from_transform(t: Transform3D, radius: float, height: float) -> void:
	var cyl := CSGCylinder3D.new()
	cyl.radius    = radius
	cyl.height    = height
	cyl.sides     = 8
	cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
	_csg.add_child(cyl)
	cyl.global_transform = t

func apply_hole(global_hit_pos: Vector3, direction: Vector3, energy: float) -> void:
	var hole: Vector2 = material_data.compute_hole(energy) if material_data \
		else (Vector2(0.06, 0.4) if energy >= 40.0 else Vector2.ZERO)
	if hole.x < 0.005:
		return
	_last_hit_dir = direction
	var cyl := CSGCylinder3D.new()
	cyl.radius    = hole.x
	cyl.height    = hole.y
	cyl.sides     = 8
	cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
	_csg.add_child(cyl)
	_align_to_direction(cyl, global_hit_pos, direction)
	call_deferred("_check_connectivity")

func _get_holes() -> Array:
	return _csg.get_children().filter(
		func(c: Node) -> bool:
			return c is CSGCylinder3D \
				and (c as CSGCylinder3D).operation == CSGShape3D.OPERATION_SUBTRACTION
	)

func _get_body_boxes() -> Array:
	return _csg.get_children().filter(func(c: Node) -> bool: return c is CSGBox3D)

func _check_connectivity() -> void:
	if _severing or not is_inside_tree():
		return
	var holes: Array      = _get_holes()
	var dims: Vector3i    = VoxelConnectivity.compute_dims(body_size, TARGET_VOXELS)
	var body_boxes: Array = _get_body_boxes()
	var voxels: PackedByteArray = VoxelConnectivity.build_grid_with_shapes(
		body_size, dims, body_boxes, holes) if body_boxes.size() > 1 \
		else VoxelConnectivity.build_grid(body_size, dims, holes)
	mass_changed.emit(voxels.count(1))
	var islands: Array[PackedInt32Array] = VoxelConnectivity.find_islands(voxels, dims)
	if islands.size() < 2:
		return
	_severing = true

	var labels := PackedInt32Array()
	labels.resize(voxels.size())
	labels.fill(-1)
	for i: int in range(islands.size()):
		for idx: int in islands[i]:
			labels[idx] = i

	var min_vox: int   = int(dims.x * dims.y * dims.z * MIN_FRAG_FRACTION)
	var n_islands: int = islands.size()
	for i: int in range(islands.size()):
		if islands[i].size() < min_vox:
			continue
		var b: Dictionary    = VoxelConnectivity.island_bounds(islands[i], dims)
		var aabb: Dictionary = VoxelConnectivity.aabb_to_local(b.mn, b.mx, dims, body_size)
		_spawn_fragment(aabb.center, aabb.size, holes, body_material, i, labels, dims, n_islands)
	queue_free()

func _spawn_fragment(lc: Vector3, sz: Vector3, holes: Array, body_mat: Material,
		island_idx: int, labels: PackedInt32Array, dims: Vector3i,
		n_islands: int) -> void:
	var frag := DestructibleBody.new()
	get_parent().add_child(frag)
	frag.setup(sz, material_data, body_mat, false)
	frag.global_transform = Transform3D(global_transform.basis, global_transform * lc)
	for box: Dictionary in VoxelConnectivity.decompose_island(labels, island_idx, dims):
		var a: Dictionary = VoxelConnectivity.aabb_to_local(box.mn, box.mx, dims, body_size)
		frag.add_body_box(a.center - lc, a.size)
	for hole: Node in holes:
		var cyl := hole as CSGCylinder3D
		var in_this: bool  = _hole_in_island(cyl.position, island_idx, labels, dims)
		var in_other: bool = false
		for j: int in range(n_islands):
			if j != island_idx and _hole_in_island(cyl.position, j, labels, dims):
				in_other = true
				break
		if in_this or (not in_other):
			frag.add_hole_from_transform(cyl.global_transform, cyl.radius, cyl.height)
	var ang: Vector3 = global_transform.basis * Vector3(lc.z, 0.0, -lc.x).normalized() * 1.5
	frag.angular_velocity = ang
	frag.linear_velocity  = _last_hit_dir * 0.5

func _hole_in_island(body_local_pos: Vector3, island_label: int,
		labels: PackedInt32Array, dims: Vector3i) -> bool:
	var cell := Vector3(body_size.x / dims.x, body_size.y / dims.y, body_size.z / dims.z)
	var xi: int = clamp(int((body_local_pos.x + body_size.x * 0.5) / cell.x), 0, dims.x - 1)
	var yi: int = clamp(int((body_local_pos.y + body_size.y * 0.5) / cell.y), 0, dims.y - 1)
	var zi: int = clamp(int((body_local_pos.z + body_size.z * 0.5) / cell.z), 0, dims.z - 1)
	for dz: int in range(-1, 2):
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var nx: int = xi + dx
				var ny: int = yi + dy
				var nz: int = zi + dz
				if nx < 0 or nx >= dims.x or ny < 0 or ny >= dims.y or nz < 0 or nz >= dims.z:
					continue
				if labels[nx + ny * dims.x + nz * dims.x * dims.y] == island_label:
					return true
	return false

func _align_to_direction(node: Node3D, gp: Vector3, direction: Vector3) -> void:
	var y: Vector3   = direction.normalized()
	var ref: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x: Vector3   = ref.cross(y).normalized()
	var z: Vector3   = x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), gp)
