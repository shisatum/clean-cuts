## Headless raycast smoke-test.
## Verifies that DestructibleBody nodes expose an Area3D on collision layer 2
## so that raycasts use the trimesh shape (accurate hole detection) rather than
## the body's physics box shape.
##
## Run via:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> 2>&1
## Pass = exit code 0.  Fail = exit code 1.
extends Node

var _fail := false

func _ready() -> void:
    # Wait three physics frames so Jolt registers all bodies and Area3Ds.
    await get_tree().physics_frame
    await get_tree().physics_frame
    await get_tree().physics_frame
    _run()

func _run() -> void:
    var root: Node    = get_tree().get_root()
    var main: Node3D  = root.get_node_or_null("Main") as Node3D
    if main == null:
        _fail_msg("Could not find /root/Main")
        _quit()
        return

    var enemy: Node3D = main.get_node_or_null("Enemy") as Node3D
    if enemy == null:
        _fail_msg("Could not find /root/Main/Enemy")
        _quit()
        return

    var space := enemy.get_world_3d().direct_space_state
    var ep    := enemy.global_position

    # ── 1. Enemy should have Csg and BodyCollision as real children ───────
    var csg  := enemy.get_node_or_null("Csg")
    var bcol := enemy.get_node_or_null("BodyCollision")
    if csg != null:
        _pass_msg("enemy has Csg child (scene file parent paths correct)")
    else:
        _fail_msg("enemy missing Csg child — scene parent paths likely wrong (parent=\"Enemy\" vs parent=\".\")")
    if bcol != null:
        _pass_msg("enemy has BodyCollision child")
    else:
        _fail_msg("enemy missing BodyCollision child")

    # ── 2. Enemy body should be on layer 1 only (Area3D owns layer 2) ─────
    var rb    := enemy as RigidBody3D
    var layer := rb.collision_layer
    print("[TEST] enemy.collision_layer = %d (binary %s)" % [layer, _bin(layer)])
    if not (layer & 2):
        _pass_msg("enemy body is NOT on layer 2 — Area3D is the raycast target (trimesh accuracy preserved)")
    else:
        _fail_msg("enemy body is on layer 2 — box shape used instead of trimesh, holes will be inaccurate")

    # ── 3. Enemy should have an Area3D child on layer 2 ──────────────────
    var ray_area: Area3D = null
    for child in enemy.get_children():
        if child is Area3D:
            ray_area = child as Area3D
            break
    if ray_area != null:
        print("[TEST] Area3D found: collision_layer=%d" % ray_area.collision_layer)
        if ray_area.collision_layer == 2:
            _pass_msg("Area3D is on collision layer 2")
        else:
            _fail_msg("Area3D exists but wrong layer (%d)" % ray_area.collision_layer)
    else:
        _fail_msg("no Area3D child found on enemy — trimesh raycast not possible")

    # ── 4. Raycast(mask=2) should hit the Area3D, not the body itself ─────
    var q := PhysicsRayQueryParameters3D.create(
        ep + Vector3(0.0,  5.0, 0.0),
        ep + Vector3(0.0, -5.0, 0.0))
    q.collision_mask    = 2
    q.collide_with_areas = true
    var hit := space.intersect_ray(q)
    if hit.is_empty():
        _fail_msg("raycast(mask=2) missed entirely — no layer-2 shape at enemy position")
    else:
        var cname: String = hit.collider.name
        var clayer_val    = hit.collider.get("collision_layer")
        var clayer: int   = clayer_val if clayer_val != null else -1
        print("[TEST] ray hit: collider=%s  layer=%d" % [cname, clayer])
        if hit.collider is Area3D and hit.collider.get_parent() == enemy:
            _pass_msg("ray hit enemy's Area3D (trimesh collision path active)")
        elif hit.collider == enemy:
            _fail_msg("ray hit enemy body directly — Area3D missing, box shape used (holes inaccurate)")
        else:
            _fail_msg("ray hit unexpected object: %s" % cname)

    # ── 5. PlankWood sanity check ─────────────────────────────────────────
    var plank: Node3D = main.get_node_or_null("PlankWood") as Node3D
    if plank != null:
        var pb   := plank as RigidBody3D
        var pp   := plank.global_position
        print("[TEST] PlankWood.collision_layer = %d" % pb.collision_layer)
        var plank_area: Area3D = null
        for child in plank.get_children():
            if child is Area3D:
                plank_area = child as Area3D
                break
        if plank_area != null:
            _pass_msg("PlankWood has Area3D child")
        else:
            _fail_msg("PlankWood missing Area3D — holes inaccurate")

        var pq := PhysicsRayQueryParameters3D.create(
            pp + Vector3(0, 0, -2.0),
            pp + Vector3(0, 0,  2.0))
        pq.collision_mask    = 2
        pq.collide_with_areas = true
        var ph := space.intersect_ray(pq)
        if ph.is_empty():
            _fail_msg("PlankWood NOT hittable by raycast(mask=2)")
        elif ph.collider is Area3D and ph.collider.get_parent() == plank:
            _pass_msg("PlankWood hit via Area3D (correct)")
        elif ph.collider == plank:
            _fail_msg("PlankWood hit via body directly (Area3D missing)")
        else:
            _fail_msg("plank ray hit unexpected: %s" % ph.collider.name)

    _quit()

func _pass_msg(msg: String) -> void:
    print("[TEST] PASS: %s" % msg)

func _fail_msg(msg: String) -> void:
    print("[TEST] FAIL: %s" % msg)
    _fail = true

func _quit() -> void:
    print("[TEST] done — %s" % ("FAIL" if _fail else "PASS"))
    get_tree().quit(1 if _fail else 0)

static func _bin(n: int) -> String:
    if n == 0:
        return "0"
    var s := ""
    var v := n
    while v > 0:
        s = str(v & 1) + s
        v >>= 1
    return s
