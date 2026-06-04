class_name VoxelConnectivity
extends RefCounted

# Computes a voxel grid dimension that gives ~target_count total voxels,
# scaled to the object's proportions.
static func compute_dims(body_size: Vector3, target_count: int) -> Vector3i:
	var vol: float = body_size.x * body_size.y * body_size.z
	var side: float = pow(vol / float(target_count), 1.0 / 3.0)
	# Minimum 3 per axis so a standard hole (r=0.06) reliably carves all the
	# way through the plank's 0.15m width, preventing thin phantom connections.
	return Vector3i(
		max(3, roundi(body_size.x / side)),
		max(3, roundi(body_size.y / side)),
		max(3, roundi(body_size.z / side))
	)

# Returns a PackedByteArray: 1 = solid, 0 = carved by a hole.
# holes must be CSGCylinder3D nodes in the same local space as body_size.
static func build_grid(body_size: Vector3, dims: Vector3i, holes: Array) -> PackedByteArray:
	var voxels := PackedByteArray()
	voxels.resize(dims.x * dims.y * dims.z)
	voxels.fill(1)
	var cell := Vector3(body_size.x / dims.x, body_size.y / dims.y, body_size.z / dims.z)
	for hole: Node in holes:
		if not (hole is CSGCylinder3D):
			continue
		var cyl := hole as CSGCylinder3D
		var inv: Transform3D = cyl.transform.inverse()
		var r: float = cyl.radius
		var hh: float = cyl.height * 0.5
		for zi: int in range(dims.z):
			for yi: int in range(dims.y):
				for xi: int in range(dims.x):
					var i: int = xi + yi * dims.x + zi * dims.x * dims.y
					if voxels[i] == 0:
						continue
					var lp := Vector3(
						-body_size.x * 0.5 + (xi + 0.5) * cell.x,
						-body_size.y * 0.5 + (yi + 0.5) * cell.y,
						-body_size.z * 0.5 + (zi + 0.5) * cell.z
					)
					var p: Vector3 = inv * lp
					if Vector2(p.x, p.z).length() <= r and absf(p.y) <= hh:
						voxels[i] = 0
	return voxels

# BFS flood fill. Returns one PackedInt32Array of voxel indices per connected island.
# Uses 6-face connectivity (strict — diagonal-only contacts do not count as connected).
static func find_islands(voxels: PackedByteArray, dims: Vector3i) -> Array[PackedInt32Array]:
	var labels := PackedInt32Array()
	labels.resize(voxels.size())
	labels.fill(-1)
	var islands: Array[PackedInt32Array] = []
	var label: int = 0
	for zi: int in range(dims.z):
		for yi: int in range(dims.y):
			for xi: int in range(dims.x):
				var idx: int = xi + yi * dims.x + zi * dims.x * dims.y
				if voxels[idx] != 1 or labels[idx] != -1:
					continue
				var island := PackedInt32Array()
				var stack: Array[Vector3i] = [Vector3i(xi, yi, zi)]
				labels[idx] = label
				while not stack.is_empty():
					var v: Vector3i = stack.pop_back()
					island.append(v.x + v.y * dims.x + v.z * dims.x * dims.y)
					for nb: Vector3i in _neighbors(v, dims):
						var ni: int = nb.x + nb.y * dims.x + nb.z * dims.x * dims.y
						if voxels[ni] == 1 and labels[ni] == -1:
							labels[ni] = label
							stack.append(nb)
				islands.append(island)
				label += 1
	return islands

# Returns voxel-space bounding box of an island as {mn, mx} Vector3i.
static func island_bounds(island: PackedInt32Array, dims: Vector3i) -> Dictionary:
	var mn := Vector3i(dims.x, dims.y, dims.z)
	var mx := Vector3i(0, 0, 0)
	for raw: int in island:
		var v := Vector3i(raw % dims.x, (raw / dims.x) % dims.y, raw / (dims.x * dims.y))
		mn = Vector3i(min(mn.x, v.x), min(mn.y, v.y), min(mn.z, v.z))
		mx = Vector3i(max(mx.x, v.x), max(mx.y, v.y), max(mx.z, v.z))
	return {mn = mn, mx = mx}

# Converts a voxel-space AABB to a local-space {center, size} Dictionary.
static func aabb_to_local(mn: Vector3i, mx: Vector3i, dims: Vector3i, body_size: Vector3) -> Dictionary:
	var cell := Vector3(body_size.x / dims.x, body_size.y / dims.y, body_size.z / dims.z)
	var origin := Vector3(-body_size.x * 0.5, -body_size.y * 0.5, -body_size.z * 0.5)
	var lo: Vector3 = origin + Vector3(mn.x * cell.x, mn.y * cell.y, mn.z * cell.z)
	var hi: Vector3 = origin + Vector3((mx.x + 1) * cell.x, (mx.y + 1) * cell.y, (mx.z + 1) * cell.z)
	return {center = (lo + hi) * 0.5, size = hi - lo}

# Greedy box decomposition of one island's solid voxels.
# Returns Array of {mn: Vector3i, mx: Vector3i} — non-overlapping boxes that
# together cover exactly the island's label'd voxels. No AABB over-estimation.
# Like build_grid but initializes solid state only from explicit body boxes
# instead of the full AABB. Required for fragments whose shape is a subset of
# their AABB (diagonal cuts, irregular islands).
static func build_grid_with_shapes(body_size: Vector3, dims: Vector3i,
		body_boxes: Array, holes: Array) -> PackedByteArray:
	var voxels := PackedByteArray()
	voxels.resize(dims.x * dims.y * dims.z)
	voxels.fill(0)
	var cell   := Vector3(body_size.x / dims.x, body_size.y / dims.y, body_size.z / dims.z)
	var origin := Vector3(-body_size.x * 0.5, -body_size.y * 0.5, -body_size.z * 0.5)
	# Mark voxels covered by body boxes as solid
	for node: Node in body_boxes:
		if not (node is CSGBox3D):
			continue
		var box := node as CSGBox3D
		var bmin: Vector3 = box.position - box.size * 0.5
		var bmax: Vector3 = box.position + box.size * 0.5
		var xi0: int = maxi(0,          int((bmin.x - origin.x) / cell.x))
		var yi0: int = maxi(0,          int((bmin.y - origin.y) / cell.y))
		var zi0: int = maxi(0,          int((bmin.z - origin.z) / cell.z))
		var xi1: int = mini(dims.x - 1, int((bmax.x - origin.x) / cell.x))
		var yi1: int = mini(dims.y - 1, int((bmax.y - origin.y) / cell.y))
		var zi1: int = mini(dims.z - 1, int((bmax.z - origin.z) / cell.z))
		for zi: int in range(zi0, zi1 + 1):
			for yi: int in range(yi0, yi1 + 1):
				for xi: int in range(xi0, xi1 + 1):
					voxels[xi + yi * dims.x + zi * dims.x * dims.y] = 1
	# Carve holes (identical to build_grid)
	for hole: Node in holes:
		if not (hole is CSGCylinder3D):
			continue
		var cyl := hole as CSGCylinder3D
		var inv: Transform3D = cyl.transform.inverse()
		var r: float = cyl.radius
		var hh: float = cyl.height * 0.5
		for zi: int in range(dims.z):
			for yi: int in range(dims.y):
				for xi: int in range(dims.x):
					var i: int = xi + yi * dims.x + zi * dims.x * dims.y
					if voxels[i] == 0:
						continue
					var lp := origin + Vector3((xi + 0.5) * cell.x, (yi + 0.5) * cell.y, (zi + 0.5) * cell.z)
					var p: Vector3 = inv * lp
					if Vector2(p.x, p.z).length() <= r and absf(p.y) <= hh:
						voxels[i] = 0
	return voxels

static func decompose_island(labels: PackedInt32Array, island_label: int,
		dims: Vector3i) -> Array[Dictionary]:
	var covered := PackedByteArray()
	covered.resize(labels.size())
	covered.fill(0)
	var boxes: Array[Dictionary] = []
	for zi: int in range(dims.z):
		for yi: int in range(dims.y):
			for xi: int in range(dims.x):
				var idx: int = xi + yi * dims.x + zi * dims.x * dims.y
				if labels[idx] != island_label or covered[idx] == 1:
					continue
				# Expand in X
				var ex := xi
				while ex + 1 < dims.x \
						and labels[(ex+1) + yi*dims.x + zi*dims.x*dims.y] == island_label \
						and covered[(ex+1) + yi*dims.x + zi*dims.x*dims.y] == 0:
					ex += 1
				# Expand in Y (full x range must hold)
				var ey := yi
				while ey + 1 < dims.y:
					var ok := true
					for tx: int in range(xi, ex + 1):
						var ti: int = tx + (ey+1)*dims.x + zi*dims.x*dims.y
						if labels[ti] != island_label or covered[ti] == 1:
							ok = false; break
					if ok: ey += 1
					else: break
				# Expand in Z (full x,y range must hold)
				var ez := zi
				while ez + 1 < dims.z:
					var ok := true
					for ty: int in range(yi, ey + 1):
						for tx: int in range(xi, ex + 1):
							var ti: int = tx + ty*dims.x + (ez+1)*dims.x*dims.y
							if labels[ti] != island_label or covered[ti] == 1:
								ok = false; break
						if not ok: break
					if ok: ez += 1
					else: break
				# Mark covered
				for tz: int in range(zi, ez + 1):
					for ty: int in range(yi, ey + 1):
						for tx: int in range(xi, ex + 1):
							covered[tx + ty*dims.x + tz*dims.x*dims.y] = 1
				boxes.append({mn = Vector3i(xi, yi, zi), mx = Vector3i(ex, ey, ez)})
	return boxes

static func _neighbors(v: Vector3i, dims: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var offsets: Array[Vector3i] = [
		Vector3i(1,0,0), Vector3i(-1,0,0),
		Vector3i(0,1,0), Vector3i(0,-1,0),
		Vector3i(0,0,1), Vector3i(0,0,-1),
	]
	for o: Vector3i in offsets:
		var nb: Vector3i = v + o
		if nb.x >= 0 and nb.x < dims.x \
		and nb.y >= 0 and nb.y < dims.y \
		and nb.z >= 0 and nb.z < dims.z:
			result.append(nb)
	return result
