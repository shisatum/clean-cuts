class_name EnemyTorso
extends DestructibleBody

## The persistent core of a multi-part enemy: drives the chase AI and is the body
## that topples on death. It deliberately does NOT decide death — the Enemy
## container watches the vital parts (this torso AND the head) and calls go_limp()
## when either has lost enough mass. Locomotion lives here because the torso is the
## heavy, ground-contacting root; driving movement from a light welded head would
## fight the joint solver.

@export var move_speed: float = 1.5

var _dead: bool = false
var _player: Node3D

func _ready() -> void:
	super()
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	_player = get_viewport().get_camera_3d()

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

## Release the upright lock and topple. Called by the Enemy container when a vital
## part (this torso or the head) is destroyed. Idempotent.
func go_limp() -> void:
	if _dead:
		return
	_dead = true
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	if is_inside_tree():
		var tip := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		apply_torque_impulse(tip.normalized() * 4.0)
	print("[ENEMY] died — vital part destroyed")
