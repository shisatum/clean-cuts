extends Node

# Standalone test for the clip_d computation in _check_connectivity.
# Run headlessly: Godot --headless --path <proj> res://tests/test_clip_plane.tscn
# Exit 0 = all pass, Exit 1 = at least one failure.

func _ready() -> void:
	var passed: int = 0
	var failed: int = 0

	if _test_two_valid_islands():
		print("PASS  two_valid_islands")
		passed += 1
	else:
		printerr("FAIL  two_valid_islands")
		failed += 1

	if _test_one_valid_one_dust():
		print("PASS  one_valid_one_dust")
		passed += 1
	else:
		printerr("FAIL  one_valid_one_dust")
		failed += 1

	if _test_cut_faces_coincident():
		print("PASS  cut_faces_coincident")
		passed += 1
	else:
		printerr("FAIL  cut_faces_coincident")
		failed += 1

	print("--- %d passed, %d failed ---" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# Mirrors the clip_d calculation from _check_connectivity exactly,
# including the FIXED condition (min_proj_oth < INF).
static func _clip_d(islands: Array, island_idx: int, labels: PackedInt32Array,
		min_vox: int, clip_n: Vector3, dims: Vector3i, body_size: Vector3) -> float:
	var cell := Vector3(body_size.x / dims.x, body_size.y / dims.y, body_size.z / dims.z)
	var go := -body_size * 0.5
	var half_cell_ext: float = (absf(cell.x * clip_n.x) + absf(cell.y * clip_n.y) \
			+ absf(cell.z * clip_n.z)) * 0.5
	var max_proj_i: float  = -INF
	var min_proj_oth: float = INF
	for vox_idx: int in range(labels.size()):
		var lab: int = labels[vox_idx]
		if lab < 0 or islands[lab].size() < min_vox:
			continue
		var vx: int = vox_idx % dims.x
		var vy: int = floori(float(vox_idx) / dims.x) % dims.y
		var vz: int = floori(float(vox_idx) / (dims.x * dims.y))
		var proj: float = (go + Vector3(
				(vx + 0.5) * cell.x, (vy + 0.5) * cell.y, (vz + 0.5) * cell.z)).dot(clip_n)
		if lab == island_idx: max_proj_i = maxf(max_proj_i, proj)
		else: min_proj_oth = minf(min_proj_oth, proj)
	# FIX: guard against min_proj_oth staying at INF when no other valid islands exist.
	# Old code: `min_proj_oth > max_proj_i` — INF > finite = true → (finite+INF)*0.5 = INF.
	# New code: also require min_proj_oth < INF so we fall back to the safe default.
	return (max_proj_i + min_proj_oth) * 0.5 \
		if min_proj_oth < INF and min_proj_oth > max_proj_i \
		else max_proj_i + half_cell_ext


static func _make_labels(islands: Array, total_voxels: int) -> PackedInt32Array:
	var labels := PackedInt32Array()
	labels.resize(total_voxels)
	labels.fill(-1)
	for i: int in range(islands.size()):
		for idx: int in islands[i]:
			labels[idx] = i
	return labels


static func _centroids(islands: Array, dims: Vector3i, body_size: Vector3) -> Array[Vector3]:
	var cell := Vector3(body_size.x / dims.x, body_size.y / dims.y, body_size.z / dims.z)
	var go := -body_size * 0.5
	var result: Array[Vector3] = []
	for isl: PackedInt32Array in islands:
		var s := Vector3.ZERO
		for raw: int in isl:
			var vx: int = raw % dims.x
			var vy: int = floori(float(raw) / dims.x) % dims.y
			var vz: int = floori(float(raw) / (dims.x * dims.y))
			s += go + Vector3((vx + 0.5) * cell.x, (vy + 0.5) * cell.y, (vz + 0.5) * cell.z)
		result.append(s / float(isl.size()))
	return result


# ── Test 1: normal 2-island split ─────────────────────────────────────────────
# 10×5×3 grid split cleanly at x=5. Both islands large (min_vox=5).
# clip_d must be finite and fall strictly between the two islands' projections.
func _test_two_valid_islands() -> bool:
	var dims := Vector3i(10, 5, 3)
	var body_size := Vector3(2.5, 0.8, 0.15)
	var voxels := PackedByteArray()
	voxels.resize(dims.x * dims.y * dims.z)
	voxels.fill(1)
	for zi: int in range(dims.z):
		for yi: int in range(dims.y):
			voxels[5 + yi * dims.x + zi * dims.x * dims.y] = 0  # column at x=5 carved out
	var islands := VoxelConnectivity.find_islands(voxels, dims)
	if islands.size() != 2:
		printerr("  expected 2 islands, got %d" % islands.size())
		return false
	var labels := _make_labels(islands, voxels.size())
	var cens   := _centroids(islands, dims, body_size)
	var min_vox := 5
	var clip_n  := (cens[1] - cens[0]).normalized()
	var clip_d  := _clip_d(islands, 0, labels, min_vox, clip_n, dims, body_size)
	if not is_finite(clip_d):
		printerr("  clip_d not finite: %s" % str(clip_d))
		return false
	# clip_d should lie between the two islands' max/min projections
	var cell := Vector3(body_size.x / dims.x, body_size.y / dims.y, body_size.z / dims.z)
	var go := -body_size * 0.5
	var max_a: float = -INF
	var min_b: float =  INF
	for idx: int in islands[0]:
		var vx: int = idx % dims.x
		var vy: int = floori(float(idx) / dims.x) % dims.y
		var vz: int = floori(float(idx) / (dims.x * dims.y))
		max_a = maxf(max_a, (go + Vector3((vx+0.5)*cell.x, (vy+0.5)*cell.y, (vz+0.5)*cell.z)).dot(clip_n))
	for idx: int in islands[1]:
		var vx: int = idx % dims.x
		var vy: int = floori(float(idx) / dims.x) % dims.y
		var vz: int = floori(float(idx) / (dims.x * dims.y))
		min_b = minf(min_b, (go + Vector3((vx+0.5)*cell.x, (vy+0.5)*cell.y, (vz+0.5)*cell.z)).dot(clip_n))
	if clip_d <= max_a or clip_d >= min_b:
		printerr("  clip_d=%.4f not in gap (%.4f, %.4f)" % [clip_d, max_a, min_b])
		return false
	return true


# ── Test 2: one valid island + one dust island ─────────────────────────────────
# Large left block (x=0..8) + tiny chip (x=9), gap at x=8.
# With min_vox=20 the chip (15 voxels) is dust. Without the fix,
# min_proj_oth stays at INF → clip_d = INF → instance_set_transform crash.
func _test_one_valid_one_dust() -> bool:
	var dims := Vector3i(10, 5, 3)
	var body_size := Vector3(2.5, 0.8, 0.15)
	var voxels := PackedByteArray()
	voxels.resize(dims.x * dims.y * dims.z)
	voxels.fill(1)
	for zi: int in range(dims.z):
		for yi: int in range(dims.y):
			voxels[8 + yi * dims.x + zi * dims.x * dims.y] = 0  # gap at x=8
	var islands := VoxelConnectivity.find_islands(voxels, dims)
	if islands.size() != 2:
		printerr("  expected 2 islands, got %d" % islands.size())
		return false
	# Find which island is large
	var large: int = 0 if islands[0].size() > islands[1].size() else 1
	var labels := _make_labels(islands, voxels.size())
	var cens   := _centroids(islands, dims, body_size)
	var min_vox := 20  # chip has 1*5*3 = 15 voxels → dust
	# clip_n points from large toward dust centroid (doesn't matter much here)
	var other_idx: int = 1 - large
	var clip_n := (cens[other_idx] - cens[large]).normalized()
	var clip_d := _clip_d(islands, large, labels, min_vox, clip_n, dims, body_size)
	if not is_finite(clip_d):
		printerr("  clip_d not finite in 1-valid+1-dust case: %s" % str(clip_d))
		return false
	return true


# ── Test 3: cut faces coincident when using centroid as lc ────────────────────
# For fragments A and B with lc = centroid_A / centroid_B respectively,
# the world-space cut face lies at body_pos + R*(centroid_perp + clip_d*clip_n).
# Since centroid_A and centroid_B both lie on the clip_n axis, their perpendicular
# components are equal → both cut faces land at the same world position.
func _test_cut_faces_coincident() -> bool:
	var dims := Vector3i(10, 5, 3)
	var body_size := Vector3(2.5, 0.8, 0.15)
	var voxels := PackedByteArray()
	voxels.resize(dims.x * dims.y * dims.z)
	voxels.fill(1)
	for zi: int in range(dims.z):
		for yi: int in range(dims.y):
			voxels[5 + yi * dims.x + zi * dims.x * dims.y] = 0
	var islands := VoxelConnectivity.find_islands(voxels, dims)
	if islands.size() != 2:
		printerr("  expected 2 islands, got %d" % islands.size())
		return false
	var labels := _make_labels(islands, voxels.size())
	var cens   := _centroids(islands, dims, body_size)
	var min_vox := 5
	var clip_n  := (cens[1] - cens[0]).normalized()
	var clip_d  := _clip_d(islands, 0, labels, min_vox, clip_n, dims, body_size)
	if not is_finite(clip_d):
		printerr("  clip_d not finite: %s" % str(clip_d))
		return false
	# Fragment A's cut face world-offset from body_pos (ignoring rotation):
	#   centroid_A + (clip_d - centroid_A.dot(clip_n)) * clip_n
	# = centroid_A_perp + clip_d * clip_n
	var face_A: Vector3 = cens[0] - cens[0].dot(clip_n) * clip_n + clip_d * clip_n
	var face_B: Vector3 = cens[1] - cens[1].dot(clip_n) * clip_n + clip_d * clip_n
	if not face_A.is_equal_approx(face_B):
		printerr("  cut faces not coincident: A=%s  B=%s  diff=%.6f" \
				% [str(face_A), str(face_B), (face_A - face_B).length()])
		return false
	return true
