extends Camera3D

const MOVE_SPEED := 4.0
const SPRINT_MULT := 3.0
const MOUSE_SENSITIVITY := 0.0015
const ENERGY_STEP := 50.0
const ENERGY_MIN := 0.0
const ENERGY_MAX := 2500.0
const MACHINEGUN_INTERVAL := 0.08

@export var shot_energy: float = 60.0
var enemy_speed: float = 1.5

var _yaw := 0.0
var _pitch := 0.0
var _energy_label: Label
var _energy_slider: HSlider
var _speed_label: Label
var _speed_slider: HSlider
var _wireframe_btn: CheckButton
var _collision_btn: CheckButton
var _cdbg_mat_box:  StandardMaterial3D = null
var _cdbg_mat_mesh: StandardMaterial3D = null
var _mg_timer: Timer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_energy_label = get_node_or_null("../HUD/EnergyPanel/EnergyLabel")
	_energy_slider = get_node_or_null("../HUD/EnergyPanel/EnergySlider")
	if _energy_slider:
		_energy_slider.value_changed.connect(_on_slider_changed)
	_set_energy(shot_energy)
	_speed_label = get_node_or_null("../HUD/SpeedPanel/SpeedLabel")
	_speed_slider = get_node_or_null("../HUD/SpeedPanel/SpeedSlider")
	if _speed_slider:
		_speed_slider.value_changed.connect(_on_speed_slider_changed)
	_wireframe_btn = get_node_or_null("../HUD/DebugPanel/WireframeButton")
	if _wireframe_btn:
		_wireframe_btn.toggled.connect(_on_wireframe_toggled)
	_collision_btn = get_node_or_null("../HUD/DebugPanel/CollisionButton")
	if _collision_btn:
		_collision_btn.toggled.connect(_on_collision_toggled)
	_mg_timer = Timer.new()
	_mg_timer.wait_time = MACHINEGUN_INTERVAL
	_mg_timer.timeout.connect(_fire)
	add_child(_mg_timer)

func _set_energy(value: float) -> void:
	shot_energy = clamp(value, ENERGY_MIN, ENERGY_MAX)
	if _energy_slider:
		_energy_slider.set_value_no_signal(shot_energy)
	if _energy_label:
		_energy_label.text = "Shot Energy: %d" % int(shot_energy)

func _on_slider_changed(value: float) -> void:
	shot_energy = value
	if _energy_label:
		_energy_label.text = "Shot Energy: %d" % int(value)

func _on_wireframe_toggled(pressed: bool) -> void:
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if pressed else Viewport.DEBUG_DRAW_DISABLED

func _on_collision_toggled(pressed: bool) -> void:
	for n in get_tree().get_nodes_in_group("_cdbg"):
		n.queue_free()
	if get_tree().node_added.is_connected(_on_node_added_for_collision):
		get_tree().node_added.disconnect(_on_node_added_for_collision)
	if not pressed:
		_cdbg_mat_box = null; _cdbg_mat_mesh = null
		return
	_cdbg_mat_box  = _dbg_mat(Color(0.0, 1.0, 0.2, 0.25))
	_cdbg_mat_mesh = _dbg_mat(Color(0.2, 0.6, 1.0, 0.20))
	for col: Node in get_tree().root.find_children("*", "CollisionShape3D", true, false):
		_add_collision_overlay(col as CollisionShape3D)
	for body: Node in get_tree().root.find_children("*", "DestructibleBody", true, false):
		_connect_body_signal(body as DestructibleBody)
	get_tree().node_added.connect(_on_node_added_for_collision)

func _on_node_added_for_collision(node: Node) -> void:
	if node is CollisionShape3D:
		_add_collision_overlay(node as CollisionShape3D)
	elif node is DestructibleBody:
		_connect_body_signal(node as DestructibleBody)

func _connect_body_signal(body: DestructibleBody) -> void:
	if not body.collision_rebuilt.is_connected(_on_collision_rebuilt):
		body.collision_rebuilt.connect(_on_collision_rebuilt)

func _on_collision_rebuilt(shape_node: CollisionShape3D) -> void:
	if not is_instance_valid(shape_node):
		return
	for child in shape_node.get_children():
		if child.is_in_group("_cdbg"):
			child.queue_free()
	_add_collision_overlay(shape_node)

func _add_collision_overlay(cs: CollisionShape3D) -> void:
	if not is_instance_valid(cs) or cs.shape == null or cs.disabled:
		return
	var vis_mesh: Mesh = null
	var mat: StandardMaterial3D
	if cs.shape is BoxShape3D:
		var bm := BoxMesh.new()
		bm.size = (cs.shape as BoxShape3D).size
		vis_mesh = bm; mat = _cdbg_mat_box
	elif cs.shape is ConcavePolygonShape3D:
		var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
		if faces.size() < 3:
			return
		var am := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		vis_mesh = am; mat = _cdbg_mat_mesh
	if vis_mesh == null or mat == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = vis_mesh
	mi.material_override = mat
	mi.add_to_group("_cdbg")
	cs.add_child(mi)

func _dbg_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _on_speed_slider_changed(value: float) -> void:
	enemy_speed = value
	if _speed_label:
		_speed_label.text = "Enemy Speed: %.1f" % value
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy:
			(e as Enemy).move_speed = value

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PI * 0.49, PI * 0.49)
		rotation = Vector3(_pitch, _yaw, 0.0)

	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_fire()
				MOUSE_BUTTON_RIGHT:
					_fire()
					_mg_timer.start()
				MOUSE_BUTTON_WHEEL_UP:
					_set_energy(shot_energy + ENERGY_STEP)
				MOUSE_BUTTON_WHEEL_DOWN:
					_set_energy(shot_energy - ENERGY_STEP)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_mg_timer.stop()

func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var fwd   := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	var right := Vector3( global_transform.basis.x.x, 0.0,  global_transform.basis.x.z)
	if fwd.length_squared()   > 1e-6: fwd   = fwd.normalized()
	if right.length_squared() > 1e-6: right = right.normalized()
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir += fwd
	if Input.is_key_pressed(KEY_S): dir -= fwd
	if Input.is_key_pressed(KEY_A): dir -= right
	if Input.is_key_pressed(KEY_D): dir += right
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir += Vector3.DOWN

	if dir.length_squared() > 0.0:
		var speed := MOVE_SPEED * (SPRINT_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		global_position += dir.normalized() * speed * delta

func _fire() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from + (-global_transform.basis.z * 1000.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask    = 2     # layer 2: accurate concave shapes only
	query.collide_with_areas = true  # needed to hit the fragment Area3Ds
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		print("[HIT] miss — nothing in range")
		return

	print("[HIT] object=%s  pos=%s  normal=%s" % [
		hit.collider.name,
		hit.position.snapped(Vector3.ONE * 0.001),
		hit.normal.snapped(Vector3.ONE * 0.001),
	])

	# DestructibleBody nodes are on collision layer 2; the collider is the body itself.
	var rb: RigidBody3D = null
	if hit.collider is RigidBody3D:
		rb = hit.collider as RigidBody3D
	elif hit.collider is Area3D and hit.collider.get_parent() is RigidBody3D:
		rb = hit.collider.get_parent() as RigidBody3D
	if rb:
		var mag: float = clamp(shot_energy * 0.002, 0.5, 6.0)
		rb.apply_impulse(-global_transform.basis.z * mag, rb.to_local(hit.position))

	var target: Node = hit.collider
	if target is Area3D:
		target = target.get_parent()
	elif not target.has_method("apply_hole"):
		target = target.get_parent()
	if target.has_method("apply_hole"):
		target.apply_hole(hit.position, -global_transform.basis.z, shot_energy)
	else:
		print("[FIRE] no destructible found — collider=%s parent=%s" % [
			hit.collider.name, hit.collider.get_parent().name])
