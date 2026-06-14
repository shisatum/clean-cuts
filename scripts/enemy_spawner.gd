class_name EnemySpawner
extends Node

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

@export var spawn_radius: float = 8.0
@export var respawn_delay: float = 2.0

var _timer: Timer
var _spawn_pending: bool = false

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_do_spawn)
	add_child(_timer)
	# Defer so the parent node finishes its own _ready() cascade before we add_child on it.
	call_deferred("_do_spawn")

func _do_spawn() -> void:
	_spawn_pending = false
	var inst: Node = ENEMY_SCENE.instantiate()
	var enemy: Enemy = inst as Enemy
	if enemy == null:
		push_error("[EnemySpawner] instantiate() did not produce an Enemy — check enemy.gd for parse errors")
		inst.queue_free()
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var angle: float = randf() * TAU
	var px: float = cam.global_position.x if is_instance_valid(cam) else 0.0
	var pz: float = cam.global_position.z if is_instance_valid(cam) else 0.0
	enemy.position = Vector3(px + cos(angle) * spawn_radius, 0.9, pz + sin(angle) * spawn_radius)
	if cam and cam.get("enemy_speed") != null:
		enemy.move_speed = cam.enemy_speed
	get_parent().add_child(enemy)
	# Respawn on death, not on the corpse being freed — corpses can persist
	# (despawn_on_death) without stalling the next spawn.
	enemy.died.connect(_on_enemy_died)
	print("[EnemySpawner] spawned enemy at ", enemy.position)

func _on_enemy_died() -> void:
	if _spawn_pending or not is_inside_tree():
		return
	_spawn_pending = true
	_timer.start(respawn_delay)
