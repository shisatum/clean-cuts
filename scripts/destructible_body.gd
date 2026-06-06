class_name DestructibleBody
extends RigidBody3D

@export var material_data: MaterialData
@export var body_material: Material
@export var body_size: Vector3 = Vector3(0.15, 0.8, 2.5)
## Minimum fragment size as a fraction of total voxel grid volume.
## Islands smaller than this are silently deleted ("dust").
## 0.02 = 2 % — keeps pieces down to ~6 cm on a plank, ~4 cm on the enemy.
## Raise toward 0.05 if too many tiny physics shards appear; lower toward 0.005
## if meaningful pieces are still vanishing.
@export_range(0.001, 0.15, 0.001) var min_frag_fraction: float = 0.02

const TARGET_VOXELS := 900
## Bake the CSG tree to a plain mesh after this many holes to keep re-bake cost constant.
const CSG_BAKE_THRESHOLD := 20

## Emitted after each hole is applied with the number of solid voxels remaining.
## Connect to this signal to track mass loss (e.g. for enemy health thresholds).
signal mass_changed(solid_count: int)

var _csg: CSGCombiner3D
var _ray_col: CollisionShape3D
var _last_hit_dir: Vector3
var _severing := false
var _connectivity_pending: bool = false
var _collision_pending: bool    = false
var _voxels: PackedByteArray    = PackedByteArray()
var _dims: Vector3i             = Vector3i.ZERO
var _carved_count: int          = 0

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
	_init_voxels()
	call_deferred("_rebuild_collision")

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
	call_deferred("_rebuild_collision")

func _init_colliders() -> void:
	# Scene-placed bodies (enemies, future scene objects) should define a
	# CollisionShape3D directly in the scene file so Jolt registers it at
	# body-creation time rather than deferred. Dynamically spawned fragments
	# have no scene shape, so we create one here.
	var has_phys_shape: bool = get_children().any(
		func(c: Node) -> bool: return c is CollisionShape3D)
	if not has_phys_shape:
		var col       := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = body_size
		col.shape = box_shape
		add_child(col)
	# Build the Area3D complete — shape added as child BEFORE the area enters
	# the tree. Jolt registers an area's shapes at tree-entry time; adding a
	# shape after the area is already in the tree is deferred by one physics
	# step, causing the first frame's raycasts to miss.
	_ray_col = CollisionShape3D.new()
	var initial_box := BoxShape3D.new()
	initial_box.size = body_size
	_ray_col.shape = initial_box
	var ray_area := Area3D.new()
	ray_area.collision_layer = 2
	ray_area.collision_mask  = 0
	ray_area.add_child(_ray_col)  # shape in first
	add_child(ray_area)           # then enter tree complete

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
	if not _connectivity_pending:
		_connectivity_pending = true
		call_deferred("_check_connectivity")
	if not _collision_pending:
		_collision_pending = true
		call_deferred("_rebuild_collision")

func _get_holes() -> Array:
	return _csg.get_children().filter(
		func(c: Node) -> bool:
			return c is CSGCylinder3D \
				and (c as CSGCylinder3D).operation == CSGShape3D.OPERATION_SUBTRACTION
	)

func _get_body_boxes() -> Array:
	return _csg.get_children().filter(func(c: Node) -> bool: return c is CSGBox3D)

func _check_connectivity() -> void:
	_connectivity_pending = false
	if _severing or not is_inside_tree():
		return
	if _voxels.is_empty():
		_init_voxels()
	var holes: Array     = _get_holes()
	var new_holes: Array = holes.slice(_carved_count)
	if new_holes.size() > 0:
		VoxelConnectivity.carve_holes(_voxels, body_size, _dims, new_holes)
		_carved_count = holes.size()
	mass_changed.emit(_voxels.count(1))
	var islands: Array[PackedInt32Array] = VoxelConnectivity.find_islands(_voxels, _dims)
	if islands.size() < 2:
		return
	_severing = true

	var labels := PackedInt32Array()
	labels.resize(_voxels.size())
	labels.fill(-1)
	for i: int in range(islands.size()):
		for idx: int in islands[i]:
			labels[idx] = i

	# Bake the current CSG mesh once — shared across all fragments so they use
	# the original clean geometry (cylinder holes intact) rather than voxel boxes.
	var baked: ArrayMesh = null
	var cm: Array = _csg.get_meshes()
	if cm.size() >= 2 and cm[1] is ArrayMesh:
		baked = cm[1] as ArrayMesh

	# Compute each island's centroid (body-local) for clip-plane calculation.
	var cell: Vector3   = Vector3(body_size.x / _dims.x, body_size.y / _dims.y, body_size.z / _dims.z)
	var go: Vector3     = -body_size * 0.5
	var centroids: Array[Vector3] = []
	for isl: PackedInt32Array in islands:
		var s := Vector3.ZERO
		for raw: int in isl:
			var vx: int = raw % _dims.x
			var vy: int = floori(float(raw) / _dims.x) % _dims.y
			var vz: int = floori(float(raw) / (_dims.x * _dims.y))
			s += go + Vector3((vx + 0.5) * cell.x, (vy + 0.5) * cell.y, (vz + 0.5) * cell.z)
		centroids.append(s / float(isl.size()))

	var min_vox: int = int(_dims.x * _dims.y * _dims.z * min_frag_fraction)
	for i: int in range(islands.size()):
		if islands[i].size() < min_vox:
			continue
		var osum := Vector3.ZERO
		var ocnt: int = 0
		for j: int in range(islands.size()):
			if j == i:
				continue
			osum += centroids[j] * float(islands[j].size())
			ocnt += islands[j].size()
		var other_c: Vector3 = osum / float(ocnt) if ocnt > 0 else centroids[i] + Vector3.UP
		var clip_n: Vector3  = (other_c - centroids[i]).normalized()
		# Shared clip plane at midpoint of the inter-island voxel gap. Both fragments
		# clip to exactly complementary half-spaces, so the overlap zone (the source
		# of ghost geometry) is eliminated even with only 1 voxel of separation.
		var half_cell_ext: float = (absf(cell.x * clip_n.x) + absf(cell.y * clip_n.y) + absf(cell.z * clip_n.z)) * 0.5
		var max_proj_i: float  = -INF
		var min_proj_oth: float = INF
		for vox_idx: int in range(labels.size()):
			var lab: int = labels[vox_idx]
			if lab < 0 or islands[lab].size() < min_vox: continue
			var vx2: int = vox_idx % _dims.x
			var vy2: int = floori(float(vox_idx) / _dims.x) % _dims.y
			var vz2: int = floori(float(vox_idx) / (_dims.x * _dims.y))
			var proj: float = (go + Vector3((vx2 + 0.5) * cell.x, (vy2 + 0.5) * cell.y, (vz2 + 0.5) * cell.z)).dot(clip_n)
			if lab == i: max_proj_i = maxf(max_proj_i, proj)
			else: min_proj_oth = minf(min_proj_oth, proj)
		var clip_d: float = (max_proj_i + min_proj_oth) * 0.5 if min_proj_oth > max_proj_i else max_proj_i + half_cell_ext
		var b: Dictionary    = VoxelConnectivity.island_bounds(islands[i], _dims)
		var aabb: Dictionary = VoxelConnectivity.aabb_to_local(b.mn, b.mx, _dims, body_size)
		# Use centroid (not AABB center) so both fragments' cut faces map to the
		# same world position: centroids lie on the clip_n axis by construction,
		# making their perpendicular displacement zero and the cut faces coincident.
		_spawn_fragment(centroids[i], aabb.size, holes, body_material, i, labels, _dims, baked, clip_n, clip_d)
	queue_free()

func _spawn_fragment(lc: Vector3, sz: Vector3, holes: Array, body_mat: Material,
		island_idx: int, labels: PackedInt32Array, dims: Vector3i,
		baked: ArrayMesh, clip_n: Vector3, clip_d: float) -> void:
	var frag := DestructibleBody.new()
	get_parent().add_child(frag)
	frag.setup(sz, material_data, body_mat, false)
	frag.global_transform = Transform3D(global_transform.basis, global_transform * lc)
	if baked != null:
		# Original baked mesh shifted into fragment-local space, clipped to this
		# island's half-space by an oriented CSGBox3D. Plane is positioned at the
		# max voxel projection of THIS island onto clip_n (tight boundary), not
		# the AABB face (which over-includes for diagonal/L-shaped cuts).
		var mesh_nd := CSGMesh3D.new()
		mesh_nd.mesh     = baked
		mesh_nd.material = body_mat
		mesh_nd.position = -lc
		frag._csg.add_child(mesh_nd)
		var yref: Vector3       = Vector3.UP if absf(clip_n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var xax: Vector3        = yref.cross(clip_n).normalized()
		var yax: Vector3        = clip_n.cross(xax).normalized()
		# clip_d is body-local; shift to fragment-local (fragment origin = lc in body space)
		var clip_d_local: float = clip_d - lc.dot(clip_n)
		var clip := CSGBox3D.new()
		clip.size      = Vector3(1000.0, 1000.0, 1000.0)
		clip.operation = CSGShape3D.OPERATION_INTERSECTION
		clip.material  = body_mat
		clip.transform = Transform3D(Basis(xax, yax, clip_n), clip_n * (clip_d_local - 500.0))
		frag._csg.add_child(clip)
	else:
		# Fallback (no mesh available): voxel decomposition + cylinder transfer.
		for box: Dictionary in VoxelConnectivity.decompose_island(labels, island_idx, dims):
			var a: Dictionary = VoxelConnectivity.aabb_to_local(box.mn, box.mx, dims, body_size)
			frag.add_body_box(a.center - lc, a.size)
		for hole: Node in holes:
			var cyl := hole as CSGCylinder3D
			if _hole_overlaps_fragment(cyl.position, lc, sz, cyl.radius):
				frag.add_hole_from_transform(cyl.global_transform, cyl.radius, cyl.height)
	frag._init_voxels()
	var ang: Vector3 = global_transform.basis * Vector3(lc.z, 0.0, -lc.x).normalized() * 1.5
	frag.angular_velocity = ang
	frag.linear_velocity  = _last_hit_dir * 0.5

# Returns true if the cylinder (in body-local space) overlaps this fragment's
# axis-aligned bounding box. Used to assign holes to fragments at split time.
# More reliable than voxel-label lookup, which fails when the hole center sits
# inside carved (void) voxel space.
func _hole_overlaps_fragment(cyl_pos: Vector3, frag_center: Vector3,
		frag_size: Vector3, cyl_radius: float) -> bool:
	var half: Vector3 = frag_size * 0.5
	var d: Vector3    = (cyl_pos - frag_center).abs()
	return d.x <= half.x + cyl_radius \
		and d.y <= half.y + cyl_radius \
		and d.z <= half.z + cyl_radius

func _init_voxels() -> void:
	if _csg == null:
		return
	_dims = VoxelConnectivity.compute_dims(body_size, TARGET_VOXELS)
	var body_boxes: Array = _get_body_boxes()
	if body_boxes.size() > 1:
		_voxels = VoxelConnectivity.build_grid_with_shapes(body_size, _dims, body_boxes, [])
	else:
		_voxels = VoxelConnectivity.build_grid(body_size, _dims, [])
	_carved_count = 0

func _rebuild_collision() -> void:
	_collision_pending = false
	if _severing or not is_inside_tree() or not _csg:
		return
	var meshes: Array = _csg.get_meshes()
	if meshes.size() < 2 or not (meshes[1] is ArrayMesh):
		return
	var mesh: ArrayMesh = meshes[1] as ArrayMesh
	if _ray_col:
		_ray_col.shape = mesh.create_trimesh_shape()
	if _get_holes().size() >= CSG_BAKE_THRESHOLD:
		_bake_csg(mesh)

func _bake_csg(baked: ArrayMesh) -> void:
	for child: Node in _csg.get_children():
		_csg.remove_child(child)
		child.queue_free()
	var body := CSGMesh3D.new()
	body.mesh     = baked
	body.material = body_material
	_csg.add_child(body)
	# Reset _carved_count to 0 — the cylinder list was just cleared, so the
	# index must restart from 0. _voxels is NOT reset; all prior damage stays
	# in the grid. Holes are baked into the ArrayMesh geometry, so they remain
	# visible. Without this reset, holes.slice(_carved_count) returns [] for
	# every future shot, freezing the voxel state and preventing all splits.
	_carved_count = 0

func _align_to_direction(node: Node3D, gp: Vector3, direction: Vector3) -> void:
	var y: Vector3   = direction.normalized()
	var ref: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x: Vector3   = ref.cross(y).normalized()
	var z: Vector3   = x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), gp)
