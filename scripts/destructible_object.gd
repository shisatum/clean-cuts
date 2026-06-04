extends CSGCombiner3D

@export var material_data: MaterialData
@export var body_material: Material       # set in scene; propagated to all fragments
@export var body_size: Vector3 = Vector3(0.15, 0.8, 2.5)

const TARGET_VOXELS     := 900
const MIN_FRAG_FRACTION := 0.08

var _last_hit_dir: Vector3
var _severing := false

func _ready() -> void:
	var body_nd := get_node_or_null("Body")
	if body_nd is CSGBox3D:
		body_size = (body_nd as CSGBox3D).size
		if body_material == null:
			body_material = (body_nd as CSGBox3D).material

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
	add_child(cyl)
	_align_to_direction(cyl, global_hit_pos, direction)
	call_deferred("_check_connectivity")

func _check_connectivity() -> void:
	if _severing or not is_inside_tree():
		return
	var holes: Array = get_children().filter(
		func(c: Node) -> bool:
			return c is CSGCylinder3D \
				and (c as CSGCylinder3D).operation == CSGShape3D.OPERATION_SUBTRACTION
	)
	var dims: Vector3i           = VoxelConnectivity.compute_dims(body_size, TARGET_VOXELS)
	var voxels: PackedByteArray  = VoxelConnectivity.build_grid(body_size, dims, holes)
	var islands: Array[PackedInt32Array] = VoxelConnectivity.find_islands(voxels, dims)
	if islands.size() < 2:
		return
	_severing = true

	# Build label array so each hole is assigned to exactly the island that owns it.
	var labels := PackedInt32Array()
	labels.resize(voxels.size())
	labels.fill(-1)
	for i: int in range(islands.size()):
		for idx: int in islands[i]:
			labels[idx] = i

	var min_vox: int       = int(dims.x * dims.y * dims.z * MIN_FRAG_FRACTION)
	var n_islands: int     = islands.size()
	var body_mat: Material = body_material
	for i: int in range(islands.size()):
		if islands[i].size() < min_vox:
			continue
		var b: Dictionary    = VoxelConnectivity.island_bounds(islands[i], dims)
		var aabb: Dictionary = VoxelConnectivity.aabb_to_local(b.mn, b.mx, dims, body_size)
		_spawn_fragment(aabb.center, aabb.size, holes, body_mat, i, labels, dims, n_islands)
	queue_free()

func _spawn_fragment(lc: Vector3, sz: Vector3, holes: Array, body_mat: Material,
		island_idx: int, labels: PackedInt32Array, dims: Vector3i,
		n_islands: int) -> void:
	var frag := FragmentObject.new()
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

# Returns true if the voxel at body_local_pos (or any neighbour) belongs to island_label.
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
