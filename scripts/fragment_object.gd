class_name FragmentObject
extends RigidBody3D

# Dynamic fragment spawned when a DestructibleObject or another FragmentObject severs.
# Carries its own hole history and voxel connectivity check — fully recursive.

var material_data: MaterialData
var body_size: Vector3

const TARGET_VOXELS    := 900
const MIN_FRAG_FRACTION := 0.08

var _csg: CSGCombiner3D
var _col_shape: CollisionShape3D
var _last_hit_dir: Vector3
var _severing := false

# Called by the spawning script immediately after add_child().
func setup(size: Vector3, mat: MaterialData, body_mat: Material) -> void:
	body_size    = size
	material_data = mat

	_csg = CSGCombiner3D.new()
	_csg.use_collision = false
	add_child(_csg)

	var box := CSGBox3D.new()
	box.size     = size
	box.material = body_mat
	_csg.add_child(box)

	_col_shape = CollisionShape3D.new()
	var box_shape     := BoxShape3D.new()
	box_shape.size     = size
	_col_shape.shape   = box_shape
	add_child(_col_shape)

	# Upgrade from box to accurate convex hull once CSG finishes baking.
	call_deferred("_rebuild_collision")

# Copies an existing hole into this fragment's CSG tree.
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

func _check_connectivity() -> void:
	if _severing or not is_inside_tree():
		return
	var holes: Array = _csg.get_children().filter(
		func(c: Node) -> bool:
			return c is CSGCylinder3D \
				and (c as CSGCylinder3D).operation == CSGShape3D.OPERATION_SUBTRACTION
	)
	var dims: Vector3i      = VoxelConnectivity.compute_dims(body_size, TARGET_VOXELS)
	var voxels: PackedByteArray = VoxelConnectivity.build_grid(body_size, dims, holes)
	var islands: Array[PackedInt32Array] = VoxelConnectivity.find_islands(voxels, dims)
	if islands.size() < 2:
		var threshold: float = material_data.sever_threshold if material_data else 1.0
		var thin_axis: int = _thinnest_axis(body_size)
		var section: Dictionary = VoxelConnectivity.weakest_section(voxels, dims, thin_axis)
		if section.coverage < threshold:
			return
		islands = VoxelConnectivity.split_at_plane(dims, thin_axis, section.pos)
	_severing = true
	var min_vox: int = int(dims.x * dims.y * dims.z * MIN_FRAG_FRACTION)
	var body_mat: Material = null
	for c: Node in _csg.get_children():
		if c is CSGBox3D:
			body_mat = (c as CSGBox3D).material
			break
	for island: PackedInt32Array in islands:
		if island.size() < min_vox:
			continue
		var b: Dictionary    = VoxelConnectivity.island_bounds(island, dims)
		var aabb: Dictionary = VoxelConnectivity.aabb_to_local(b.mn, b.mx, dims, body_size)
		_spawn_fragment(aabb.center, aabb.size, holes, body_mat)
	queue_free()

func _spawn_fragment(lc: Vector3, sz: Vector3, holes: Array, body_mat: Material) -> void:
	var frag := FragmentObject.new()
	get_parent().add_child(frag)
	frag.setup(sz, material_data, body_mat)
	frag.global_transform = Transform3D(global_transform.basis, global_transform * lc)
	for hole: Node in holes:
		var cyl := hole as CSGCylinder3D
		if _hole_overlaps(_csg.to_local(cyl.global_position), cyl, lc, sz):
			frag.add_hole_from_transform(cyl.global_transform, cyl.radius, cyl.height)
	var ang: Vector3 = global_transform.basis * Vector3(lc.z, 0.0, -lc.x).normalized() * 1.5
	frag.angular_velocity = ang
	frag.linear_velocity  = _last_hit_dir * 0.5

func _hole_overlaps(cyl_local: Vector3, cyl: CSGCylinder3D, fc: Vector3, fs: Vector3) -> bool:
	var m: float  = cyl.height * 0.5
	var h: Vector3 = fs * 0.5
	return absf(cyl_local.x - fc.x) <= h.x + m \
		and absf(cyl_local.y - fc.y) <= h.y + m \
		and absf(cyl_local.z - fc.z) <= h.z + m

func _rebuild_collision() -> void:
	if not is_inside_tree() or not _csg:
		return
	var meshes: Array = _csg.get_meshes()
	if meshes.size() >= 2 and meshes[1] is ArrayMesh:
		var convex: Shape3D = (meshes[1] as ArrayMesh).create_convex_shape(true, true)
		if convex and _col_shape:
			_col_shape.shape = convex

func _thinnest_axis(sz: Vector3) -> int:
	if sz.x <= sz.y and sz.x <= sz.z:
		return 0
	elif sz.y <= sz.z:
		return 1
	return 2

func _align_to_direction(node: Node3D, gp: Vector3, direction: Vector3) -> void:
	var y: Vector3  = direction.normalized()
	var ref: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x: Vector3  = ref.cross(y).normalized()
	var z: Vector3  = x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), gp)
