class_name Enemy
extends DestructibleBody

## Fraction of initial mass that must be destroyed to kill this enemy (0.5 = 50%).
@export var death_threshold: float = 0.5
@export var move_speed: float = 1.5
## Half-width of the patrol path along the X axis.
@export var patrol_range: float = 3.0

var _initial_voxel_count: int = 0
var _dead: bool = false
var _move_dir: float = 1.0
var _patrol_origin: Vector3

func _ready() -> void:
	super()
	# Stay upright while alive; unlocked on death so the body can tip over.
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	_patrol_origin = global_position
	mass_changed.connect(_on_mass_changed)
	# Full box with no holes — total voxel count is simply the grid volume.
	var dims: Vector3i = VoxelConnectivity.compute_dims(body_size, TARGET_VOXELS)
	_initial_voxel_count = dims.x * dims.y * dims.z

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _dead:
		return
	# Reverse direction at patrol limits.
	var offset: float = state.transform.origin.x - _patrol_origin.x
	if offset >= patrol_range:
		_move_dir = -1.0
	elif offset <= -patrol_range:
		_move_dir = 1.0
	var vel: Vector3 = state.linear_velocity
	vel.x = _move_dir * move_speed
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
