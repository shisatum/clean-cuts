extends CSGCombiner3D

@export var material_data: MaterialData

# body_size is read from the Body CSGBox3D child at startup.
# The export lets you see/override it in the inspector if needed.
@export var body_size: Vector3 = Vector3(0.15, 0.8, 2.5)

const TARGET_VOXELS     := 900
const MIN_FRAG_FRACTION := 0.08

var _last_hit_dir: Vector3
var _severing := false

func _ready() -> void:
	var body_nd := get_node_or_null("Body")
	if body_nd is CSGBox3D:
		body_size = (body_nd as CSGBox3D).size

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
		# Flood fill sees a technical connection — check sever_threshold on the
		# thinnest body axis only. Checking other axes causes false splits when
		# shots penetrate a face and void slices on the perpendicular axes.
		var threshold: float = material_data.sever_threshold if material_data else 1.0
		var thin_axis: int = _thinnest_axis(body_size)
		var section: Dictionary = VoxelConnectivity.weakest_section(voxels, dims, thin_axis)
		if section.coverage < threshold:
			return
		islands = VoxelConnectivity.split_at_plane(dims, thin_axis, section.pos)
	_severing = true
	var min_vox: int   = int(dims.x * dims.y * dims.z * MIN_FRAG_FRACTION)
	var body_mat: Material = null
	var body_nd := get_node_or_null("Body")
	if body_nd is CSGBox3D:
		body_mat = (body_nd as CSGBox3D).material
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
		if _hole_overlaps(to_local(cyl.global_position), cyl, lc, sz):
			frag.add_hole_from_transform(cyl.global_transform, cyl.radius, cyl.height)
	var ang: Vector3 = global_transform.basis * Vector3(lc.z, 0.0, -lc.x).normalized() * 1.5
	frag.angular_velocity = ang
	frag.linear_velocity  = _last_hit_dir * 0.5

func _hole_overlaps(cyl_local: Vector3, cyl: CSGCylinder3D, fc: Vector3, fs: Vector3) -> bool:
	var m: float   = cyl.height * 0.5
	var h: Vector3 = fs * 0.5
	return absf(cyl_local.x - fc.x) <= h.x + m \
		and absf(cyl_local.y - fc.y) <= h.y + m \
		and absf(cyl_local.z - fc.z) <= h.z + m

func _thinnest_axis(sz: Vector3) -> int:
	if sz.x <= sz.y and sz.x <= sz.z:
		return 0
	elif sz.y <= sz.z:
		return 1
	return 2

func _align_to_direction(node: Node3D, gp: Vector3, direction: Vector3) -> void:
	var y: Vector3   = direction.normalized()
	var ref: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x: Vector3   = ref.cross(y).normalized()
	var z: Vector3   = x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), gp)
