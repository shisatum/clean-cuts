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
signal collision_rebuilt(shape_node: CollisionShape3D)

var _csg: CSGCombiner3D
var _ray_col: CollisionShape3D
var _phys_col: CollisionShape3D = null
var _compound_boxes: Array[Dictionary] = []
var _compound_col_nodes: Array[CollisionShape3D] = []
var _last_hit_dir: Vector3
var _severing := false
var _connectivity_pending: bool = false
var _collision_pending: bool    = false
var _voxels: PackedByteArray    = PackedByteArray()
var _dims: Vector3i             = Vector3i.ZERO
var _carved_count: int          = 0
var _hole_records: Array[Dictionary] = []

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
	for c: Node in get_children():
		if c is CollisionShape3D:
			_phys_col = c as CollisionShape3D
			break
	sleeping_state_changed.connect(_on_sleeping_state_changed)
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
	cyl.material  = body_material  # carved hole walls render as the body, not white
	_csg.add_child(cyl)
	cyl.global_transform = t
	_hole_records.append({lt = cyl.transform, r = radius, h = height})

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
	cyl.material  = body_material  # carved hole walls render as the body, not white
	_csg.add_child(cyl)
	_align_to_direction(cyl, global_hit_pos, direction)
	# Store the hole body-local (cyl sits under _csg at the body origin), so it can
	# be replayed onto a fragment via this body's current world transform even
	# after the body has moved. Survives _bake_csg() destroying the live cylinders.
	_hole_records.append({lt = cyl.transform, r = hole.x, h = hole.y})
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
	return _csg.get_children().filter(
		func(c: Node) -> bool:
			return c is CSGBox3D \
				and (c as CSGBox3D).operation == CSGShape3D.OPERATION_UNION
	)

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

	# voxel index -> island label for decompose_island.
	var labels := PackedInt32Array()
	labels.resize(_voxels.size())
	labels.fill(-1)
	for i: int in range(islands.size()):
		for idx: int in islands[i]:
			labels[idx] = i

	var min_vox: int = int(_dims.x * _dims.y * _dims.z * min_frag_fraction)
	var valid: Array[int] = []
	for i: int in range(islands.size()):
		if islands[i].size() >= min_vox:
			valid.append(i)

	for i: int in valid:
		var b: Dictionary    = VoxelConnectivity.island_bounds(islands[i], _dims)
		var aabb: Dictionary = VoxelConnectivity.aabb_to_local(b.mn, b.mx, _dims, body_size)
		var ac: Vector3      = aabb.center
		var sz: Vector3      = aabb.size
		var boxes: Array[Dictionary] = VoxelConnectivity.decompose_island(labels, i, _dims)
		_spawn_fragment(ac, sz, body_material, boxes)
	# Wake nearby sleeping bodies before disappearing. Jolt intentionally does not
	# wake neighbors when a body is removed — this is the GDScript equivalent of
	# ActivateBodiesInAABox, called at the only moment we know support is gone.
	_wake_nearby_sleeping()
	# Remove this body from all collision layers immediately so Jolt stops
	# testing it against the freshly spawned fragments before queue_free() lands.
	collision_layer = 0
	collision_mask  = 0
	if is_instance_valid(_csg):
		_csg.visible = false
	queue_free()

# Spawns a rigid-body fragment for one disconnected island. The body shape is
# built from greedy-decomposed boxes (exact voxel coverage) so any fracture
# topology — straight, L-shaped, circular — renders without ghost geometry.
func _spawn_fragment(ac: Vector3, sz: Vector3, body_mat: Material,
		boxes: Array[Dictionary]) -> void:
	var frag := DestructibleBody.new()
	get_parent().add_child(frag)
	frag.setup(sz, material_data, body_mat, false)
	frag.global_transform = Transform3D(global_transform.basis, global_transform * ac)
	for box_d: Dictionary in boxes:
		var ba: Dictionary = VoxelConnectivity.aabb_to_local(box_d.mn, box_d.mx, _dims, body_size)
		frag.add_body_box(ba.center - ac, ba.size)
		frag._compound_boxes.append({center = ba.center - ac, size = ba.size})
	frag._apply_compound_boxes()
	for rec: Dictionary in _hole_records:
		if _hole_overlaps_fragment(rec.lt.origin, ac, sz, rec.r):
			frag.add_hole_from_transform(global_transform * rec.lt, rec.r, rec.h)
	frag._init_voxels()
	var ang_dir := Vector3(ac.z, 0.0, -ac.x)
	var ang: Vector3 = global_transform.basis * (ang_dir.normalized() if ang_dir.length_squared() > 1e-6 else Vector3.RIGHT) * 1.5
	frag.angular_velocity = ang
	var out: Vector3 = global_transform.basis * ac
	out = out.normalized() if out.length_squared() > 1e-6 else Vector3.UP
	frag.linear_velocity  = _last_hit_dir * 0.5 + out * 0.8

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
		collision_rebuilt.emit(_ray_col)
	if _get_holes().size() >= CSG_BAKE_THRESHOLD:
		_bake_csg(mesh)

func _on_sleeping_state_changed() -> void:
	if _severing:
		return
	if not sleeping:
		_wake_nearby_sleeping()

func _wake_nearby_sleeping() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = body_size * 1.1
	query.shape          = box
	query.transform      = global_transform
	query.collision_mask = 1
	query.exclude        = [get_rid()]
	for contact: Dictionary in space.intersect_shape(query, 32):
		if contact.collider is RigidBody3D and (contact.collider as RigidBody3D).sleeping:
			(contact.collider as RigidBody3D).sleeping = false

# Builds compound BoxShape3D collision from _compound_boxes (one CollisionShape3D
# per greedy box). Falls back to a single body_size box when _compound_boxes is empty
# (scene-placed bodies: planks, enemies). Safe to call at spawn time or on wake.
func _apply_compound_boxes() -> void:
	if _phys_col == null:
		return
	_clear_compound_nodes()
	if _compound_boxes.is_empty():
		var box := BoxShape3D.new()
		box.size = body_size
		_phys_col.position = Vector3.ZERO
		_phys_col.shape = box
	else:
		for i: int in range(_compound_boxes.size()):
			var bd: Dictionary = _compound_boxes[i]
			var box := BoxShape3D.new()
			box.size = bd.size
			if i == 0:
				_phys_col.position = bd.center
				_phys_col.shape = box
			else:
				var cs := CollisionShape3D.new()
				cs.position = bd.center
				cs.shape = box
				add_child(cs)
				_compound_col_nodes.append(cs)
	collision_rebuilt.emit(_phys_col)

func _clear_compound_nodes() -> void:
	for cs: CollisionShape3D in _compound_col_nodes:
		if is_instance_valid(cs):
			cs.queue_free()
	_compound_col_nodes.clear()

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
