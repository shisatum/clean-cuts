extends Camera3D

const MOVE_SPEED := 4.0
const SPRINT_MULT := 3.0
const MOUSE_SENSITIVITY := 0.0015
const ENERGY_STEP := 25.0
const ENERGY_MIN := 0.0
const ENERGY_MAX := 1000.0

@export var shot_energy: float = 60.0

var _yaw := 0.0
var _pitch := 0.0
var _energy_label: Label
var _energy_slider: HSlider

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_energy_label = get_node_or_null("../HUD/EnergyPanel/EnergyLabel")
	_energy_slider = get_node_or_null("../HUD/EnergyPanel/EnergySlider")
	if _energy_slider:
		_energy_slider.value_changed.connect(_on_slider_changed)
	_set_energy(shot_energy)

func _set_energy(value: float) -> void:
	shot_energy = clamp(value, ENERGY_MIN, ENERGY_MAX)
	if _energy_slider:
		_energy_slider.set_value_no_signal(shot_energy)
	if _energy_label:
		_energy_label.text = "Shot Energy: %d" % int(shot_energy)

func _on_slider_changed(value: float) -> void:
	# Fired when user drags the slider (mouse must be uncaptured via Escape)
	shot_energy = value
	if _energy_label:
		_energy_label.text = "Shot Energy: %d" % int(value)

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

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_fire()
			MOUSE_BUTTON_WHEEL_UP:
				_set_energy(shot_energy + ENERGY_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_energy(shot_energy - ENERGY_STEP)

func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir += Vector3.DOWN

	if dir.length_squared() > 0.0:
		var speed := MOVE_SPEED * (SPRINT_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		global_position += dir.normalized() * speed * delta

func _fire() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from + (-global_transform.basis.z * 1000.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		print("[HIT] miss — nothing in range")
		return

	print("[HIT] object=%s  pos=%s  normal=%s" % [
		hit.collider.name,
		hit.position.snapped(Vector3.ONE * 0.001),
		hit.normal.snapped(Vector3.ONE * 0.001),
	])

	var target: Node = hit.collider
	if not target.has_method("apply_hole"):
		target = target.get_parent()
	if target.has_method("apply_hole"):
		target.apply_hole(hit.position, -global_transform.basis.z, shot_energy)
	else:
		print("[FIRE] no destructible found — collider=%s parent=%s" % [
			hit.collider.name, hit.collider.get_parent().name])
