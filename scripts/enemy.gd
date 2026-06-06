class_name Enemy
extends DestructibleBody

## Fraction of initial mass that must be destroyed to kill this enemy (0.5 = 50%).
@export var death_threshold: float = 0.5
@export var move_speed: float = 1.5

var _initial_voxel_count: int = 0
var _dead: bool = false
var _player: Node3D

func _ready() -> void:
	super()
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	_player = get_viewport().get_camera_3d()
	mass_changed.connect(_on_mass_changed)
	var dims: Vector3i = VoxelConnectivity.compute_dims(body_size, TARGET_VOXELS)
	_initial_voxel_count = dims.x * dims.y * dims.z

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _dead or not is_instance_valid(_player):
		return
	var to_player: Vector3 = _player.global_position - state.transform.origin
	to_player.y = 0.0
	var vel: Vector3 = state.linear_velocity
	if to_player.length_squared() > 1.0:
		var dir: Vector3 = to_player.normalized()
		vel.x = dir.x * move_speed
		vel.z = dir.z * move_speed
	else:
		vel.x = 0.0
		vel.z = 0.0
	state.linear_velocity = vel

func _on_mass_changed(solid_count: int) -> void:
	if _dead or _initial_voxel_count == 0:
		return
	var fraction: float = float(solid_count) / float(_initial_voxel_count)
	if fraction <= 1.0 - death_threshold:
		_die(fraction)

func _die(mass_fraction: float) -> void:
	_dead = true
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	var tip := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	apply_torque_impulse(tip.normalized() * 4.0)
	print("[ENEMY] died — %.0f%% mass remaining" % [mass_fraction * 100.0])
	get_tree().create_timer(3.0).timeout.connect(_cleanup)

func _cleanup() -> void:
	if is_inside_tree():
		queue_free()
