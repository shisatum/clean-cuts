## Headless raycast smoke-test.
## Verifies that DestructibleBody nodes are visible on collision layer 2
## (so the camera raycast can detect them) and that the enemy in main.tscn
## is hit by a straight-down ray aimed at its position.
##
## Run via:
##   Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> 2>&1
## Pass = exit code 0, all [TEST] lines show PASS.
## Fail = exit code 1, any [TEST] line shows FAIL.
extends Node

var _fail := false

func _ready() -> void:
    # Wait three physics frames so Jolt registers all bodies.
    await get_tree().physics_frame
    await get_tree().physics_frame
    await get_tree().physics_frame
    _run()

func _run() -> void:
    var root: Node = get_tree().get_root()
    var main: Node3D = root.get_node_or_null("Main") as Node3D
    if main == null:
        _fail_msg("Could not find /root/Main")
        _quit()
        return

    var enemy: Node3D = main.get_node_or_null("Enemy") as Node3D
    if enemy == null:
        _fail_msg("Could not find /root/Main/Enemy")
        _quit()
        return

    # ── 1. Verify collision_layer includes layer 2 ────────────────────────
    var rb := enemy as RigidBody3D
    var layer: int = rb.collision_layer
    print("[TEST] enemy.collision_layer = %d (binary %s)" % [layer, _bin(layer)])
    if layer & 2:
        _pass_msg("enemy is on collision layer 2")
    else:
        _fail_msg("enemy NOT on collision layer 2 — _init_colliders may not have run")

    # ── 2. Raycast straight down through enemy's world position ───────────
    var space := enemy.get_world_3d().direct_space_state
    var ep    := enemy.global_position
    var from  := ep + Vector3(0.0,  5.0, 0.0)   # 5 m above
    var to    := ep + Vector3(0.0, -5.0, 0.0)   # 5 m below

    var q := PhysicsRayQueryParameters3D.create(from, to)
    q.collision_mask    = 2
    q.collide_with_areas = true

    var hit := space.intersect_ray(q)
    if hit.is_empty():
        _fail_msg("raycast(mask=2) missed — enemy not detected")
    else:
        var cname: String = hit.collider.name
        var clayer: int   = hit.collider.get("collision_layer") if \
            hit.collider.get("collision_layer") != null else -1
        print("[TEST] ray hit: collider=%s  layer=%s" % [cname, str(clayer)])
        if hit.collider == enemy or hit.collider.get_parent() == enemy:
            _pass_msg("enemy is hittable by raycast(mask=2)")
        else:
            _fail_msg("ray hit something else (%s), not enemy" % cname)

    # ── 3. Plank sanity-check (PlankWood should also be hittable) ─────────
    var plank: Node3D = main.get_node_or_null("PlankWood") as Node3D
    if plank != null:
        var pb := plank as RigidBody3D
        print("[TEST] PlankWood.collision_layer = %d" % pb.collision_layer)
        var pp  := plank.global_position
        var pq  := PhysicsRayQueryParameters3D.create(
            pp + Vector3(0, 0, -2.0),   # in front of plank (plank faces Z)
            pp + Vector3(0, 0,  2.0))   # out the back
        pq.collision_mask    = 2
        pq.collide_with_areas = true
        var ph := space.intersect_ray(pq)
        if ph.is_empty():
            _fail_msg("PlankWood NOT hittable by raycast(mask=2)")
        else:
            if ph.collider == plank or ph.collider.get_parent() == plank:
                _pass_msg("PlankWood is hittable by raycast(mask=2)")
            else:
                _fail_msg("plank ray hit something else (%s)" % ph.collider.name)

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
