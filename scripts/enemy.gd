class_name Enemy
extends Node3D

## A multi-part enemy: a persistent EnemyTorso core, a vital head, and limb parts,
## all welded with Generic6DOFJoint3D. This container is the "nervous system" — it
## owns the welds, forwards speed to the torso, DECIDES death, and tears the
## assembly down so the spawner can respawn.
##
## Part roles:
##   VITAL (torso, head) — destroying EITHER kills the enemy (mass-loss death).
##   LIMB  (arms, future legs) — detach and fall when shot up, but NEVER kill.
##     An enemy missing every limb is still alive until a vital part loses enough
##     mass. (A future "blood loss" pass may let major wounds bleed out; not now.)
##
## Locomotion lives on the torso (heavy, ground-contacting root); the head is a
## death target, not a driver. This same shape is reused for the player (Step 4).

@export var move_speed: float = 1.5:
	set(v):
		move_speed = v
		if is_instance_valid(_torso):
			_torso.move_speed = v
## NodePath to the vital head part (a DestructibleBody welded above the torso).
@export var head: NodePath
## A vital part (torso or head) at/below this fraction of its start mass = death.
@export_range(0.0, 1.0, 0.05) var vital_death_threshold: float = 0.5
## A limb at/below this fraction of its start mass detaches and drops.
@export_range(0.0, 1.0, 0.05) var limb_detach_fraction: float = 0.45
## When true, the toppled corpse despawns after cleanup_delay; when false it
## persists indefinitely. Off for now (keep bodies on the field); flip on later.
@export var despawn_on_death: bool = false
## Seconds the toppled corpse lingers before despawning (only if despawn_on_death).
@export var cleanup_delay: float = 3.0

## Emitted once when this enemy dies. Drives respawn independently of whether the
## corpse is ever removed (despawn_on_death), so disabling cleanup doesn't stall spawns.
signal died

var _dead: bool = false
var _torso: EnemyTorso = null
var _head: DestructibleBody = null
var _limbs: Array[DestructibleBody] = []
var _joints: Dictionary = {}         # welded part (DestructibleBody) -> Generic6DOFJoint3D
var _limb_initial: Dictionary = {}   # limb -> initial solid voxel count
var _vital_initial: Dictionary = {}  # vital part -> initial solid voxel count

func _ready() -> void:
	add_to_group("enemies")
	_head = get_node_or_null(head) as DestructibleBody
	for c: Node in get_children():
		if c is EnemyTorso:
			_torso = c as EnemyTorso
		elif c is DestructibleBody and c != _head:
			_limbs.append(c as DestructibleBody)
	# Map every weld to the part it holds. node_a/node_b are relative to the JOINT.
	for c: Node in get_children():
		if c is Generic6DOFJoint3D:
			var j := c as Generic6DOFJoint3D
			_lock_weld(j)
			var part := j.get_node_or_null(j.node_b) as DestructibleBody
			if part != null:
				_joints[part] = j
	# Vital parts: torso + head. Either destroyed = death.
	for vital: DestructibleBody in [_torso, _head]:
		if vital == null:
			continue
		_vital_initial[vital] = vital._initial_solid_count
		vital.mass_changed.connect(_on_vital_mass_changed.bind(vital))
		vital.tree_exited.connect(_on_vital_gone.bind(vital))
	if _torso != null:
		_torso.move_speed = move_speed
		_torso.fractured.connect(_on_torso_fractured)
	# Limbs: detach when shot up, but never kill.
	for limb: DestructibleBody in _limbs:
		_limb_initial[limb] = limb._initial_solid_count
		limb.tree_exited.connect(_on_limb_gone.bind(limb))
		limb.mass_changed.connect(_on_limb_mass_changed.bind(limb))

## Rigid weld: lock all six DOF (lower == upper == 0 on every linear and angular
## axis) so the part holds its spawn pose relative to the torso until detached.
func _lock_weld(j: Generic6DOFJoint3D) -> void:
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	for p: int in [
			Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
			Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
			Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
			Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]:
		j.set_param_x(p, 0.0)
		j.set_param_y(p, 0.0)
		j.set_param_z(p, 0.0)

# ── Re-anchoring: keep the corpse connected when the torso is cut apart ───────

## The torso split into fragments (which frees the torso and would orphan the welds
## anchored to it). Re-create each head/arm weld onto the nearest surviving fragment
## so those parts ride the chunk they belong to instead of dropping into the void.
## A part with no surviving fragment (its whole region was destroyed) falls free.
func _on_torso_fractured(frags: Array) -> void:
	for part: DestructibleBody in _joints.keys():
		var old_weld: Generic6DOFJoint3D = _joints[part]
		if is_instance_valid(old_weld):
			old_weld.queue_free()
		var frag := _nearest_fragment(part, frags)
		if frag != null and is_instance_valid(part):
			_joints[part] = _weld_parts(frag, part, part.global_position)
		else:
			_joints.erase(part)

## Returns the fragment whose body centre is closest to a part, or null if none.
func _nearest_fragment(part: Node3D, frags: Array) -> DestructibleBody:
	var best: DestructibleBody = null
	var best_d: float = INF
	for f: DestructibleBody in frags:
		if not is_instance_valid(f):
			continue
		var d: float = part.global_position.distance_to(f.global_position)
		if d < best_d:
			best_d = d
			best = f
	return best

## Creates a fresh rigid weld between two bodies at a world anchor point.
func _weld_parts(body_a: Node3D, body_b: Node3D, at: Vector3) -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = j.get_path_to(body_a)
	j.node_b = j.get_path_to(body_b)
	_lock_weld(j)
	return j

# ── Vital parts (torso + head): destroying either kills the enemy ────────────

func _on_vital_mass_changed(solid_count: int, vital: DestructibleBody) -> void:
	if _dead:
		return
	var init: int = _vital_initial.get(vital, 0)
	if init <= 0:
		return
	if float(solid_count) / float(init) <= 1.0 - vital_death_threshold:
		_kill()

func _on_vital_gone(vital: DestructibleBody) -> void:
	# A vital part was fully removed (shattered to nothing). Free its dangling weld
	# (the head has one; the torso doesn't) and die.
	if _joints.has(vital):
		var j: Generic6DOFJoint3D = _joints[vital]
		_joints.erase(vital)
		if is_instance_valid(j):
			j.queue_free()
	_kill()

## Single death authority. Topples the torso (limbs stay welded and tip with it)
## and despawns the assembly after a delay so the spawner refires.
func _kill() -> void:
	if _dead or not is_inside_tree():
		return
	_dead = true
	if is_instance_valid(_torso):
		_torso.go_limp()
	died.emit()
	if despawn_on_death:
		get_tree().create_timer(cleanup_delay).timeout.connect(_cleanup)

# ── Limbs (arms/legs): detach when shot up, but never kill ───────────────────

func _on_limb_mass_changed(solid_count: int, limb: DestructibleBody) -> void:
	if _dead or not _joints.has(limb):
		return
	var init: int = _limb_initial.get(limb, 0)
	if init <= 0:
		return
	if float(solid_count) / float(init) <= limb_detach_fraction:
		_detach_limb(limb)

## Breaks a limb's weld so it falls free as a plain DestructibleBody, keeping its
## holes. Called when a limb is shot up past the detach threshold.
func _detach_limb(limb: DestructibleBody) -> void:
	if not _joints.has(limb):
		return
	var j: Generic6DOFJoint3D = _joints[limb]
	_joints.erase(limb)
	if is_instance_valid(j):
		j.queue_free()
	if is_instance_valid(limb):
		limb.apply_central_impulse(Vector3(randf_range(-0.5, 0.5), -0.2, randf_range(-0.5, 0.5)))

## A limb freed itself (its own fracture split it) — drop the now dangling weld.
func _on_limb_gone(limb: DestructibleBody) -> void:
	if _joints.has(limb):
		var j: Generic6DOFJoint3D = _joints[limb]
		_joints.erase(limb)
		if is_instance_valid(j):
			j.queue_free()
	_limbs.erase(limb)

func _cleanup() -> void:
	if is_inside_tree():
		queue_free()
