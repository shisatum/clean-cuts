# Clean-Cuts Destruction — A Realistic Plan

*A scoped-down path from "stuck for months" to "playable prototype this week." June 2026.*

> **Canonical location:** this file lives at `D:\LOVE\code_projects\Godot\new_physics_project\REALISTIC_PLAN.md`.
> The copy that used to sit at `D:\LOVE\code_projects\Godot\REALISTIC_PLAN.md` has been deleted.

---

## The one-paragraph diagnosis

Your childhood dream is **clean cuts and persistent holes** — bore a bullet hole through a plank, slice it in half, and have both halves keep the holes you already made. That is a *constructive solid geometry* (CSG) game, and your old `material-destruction-demo` was aimed at exactly the right target. It didn't fail because the idea was wrong. It failed because two things grew without limit: (1) the **impact model** — thousands of lines of ballistic heuristics to stop fast physics-projectiles from tunnelling and double-hitting, and (2) the **runtime mesh pipeline** — CSG re-bake + voxel island-splitting + compound-convex collision rebuild on every hit. The new XPBD/C++/GPU GDD is the *opposite* engine (soft continuous deformation, not clean cuts) and an order of magnitude harder to build. It is the wrong tool for your dream. Don't build it.

The plan below keeps the CSG idea, deletes the two things that exploded, and proves the fun with the smallest possible slice before adding anything back.

---

## The single most important change: kill the physical bullet

`Destructible.gd` is **2,566 lines**, and the large majority of it — `ballistic_damp_cooldown`, `_pass_through_restore_token`, `_peak_approach_speed`, four-ray fallback probing, closing-speed estimation, thin-sheet pass-through, pair-ID double-hit suppression — exists for **one reason**: handling a fast `RigidBody3D` projectile that tunnels through thin geometry and reports collisions unreliably at high speed. That whole category of pain is optional.

For "clean cuts and holes" you do **not** need a physical bullet. A **hitscan raycast** from the crosshair gives you, in one call, exactly what CSG needs:

- the **hit position** (where to place the cutter),
- the **surface normal** (how to orient the cutter),
- the **object hit** (what to cut).

No tunnelling. No double-hits. No closing-speed math. No cooldown tokens. Deleting the physical projectile removes ~70% of the complexity that buried the old project, *for free*, while producing an identical visual result for the core feel. Physical thrown/launched objects become a *later, optional* milestone — not a foundation.

---

## Tech recommendation

| Decision | Choice | Why |
|---|---|---|
| Engine | **Godot 4.x** (you already know it) | Free, fast iteration, GDScript is plenty for a prototype. Don't switch. |
| Physics | **Jolt** (Godot 4.4+ default) | You're already on it; it's the right choice for rigid bodies. |
| Cutting primitive | **CSG boolean subtraction** (built-in `CSGCombiner3D`) | Native, gives clean holes/cuts, retains a damage history. The thing you already had working. |
| Impact source | **Hitscan `RaycastQuery`** from camera | Eliminates the entire ballistics-heuristics layer. |
| Language | **GDScript only** | No C++, no GDExtension, no Vulkan. Revisit only if profiling proves you must. |

**Do not** start the C++/XPBD/GPU engine. That is a multi-year, multi-person, research-grade middleware project (the category of NVIDIA FleX or Pixelux DMM). It also produces *soft squashy deformation*, which is not the feel you chose.

### One honest caveat about CSG

Godot's runtime CSG is not designed to regenerate a complex mesh every frame. The fix is the one your old project already discovered: **cut rarely, debounce the re-bake, and cap the CSG history** by baking to a plain `ArrayMesh` after N cuts. Keep that lesson; drop everything else. If CSG ever becomes the real bottleneck (it won't at prototype scale), the fallback is plane-slicing of convex meshes — but cross that bridge only when profiling forces you to.

---

## The simplified architecture (three pieces, not thirty)

```
Crosshair raycast  ──►  Hit { object, position, normal }
                              │
                              ▼
                    Damage decision  (is energy ≥ this material's threshold?)
                              │
                              ▼
                    Apply cutter  (subtract a CSG cylinder at hit point/normal)
                              │
                              ▼
                    Debounced re-bake + collision rebuild
```

That's the whole loop. Three concepts: **hit → decide → cut**. No projectile bodies, no island splitting, no fasteners, no multi-material interaction matrix — *yet*. Each of those is a later milestone, added one at a time, only after the previous one is fun and stable.

---

## The vertical slice (MVP)

Build the smallest thing that proves the dream. **One** of everything:

- **One target:** a single wooden plank (a `DestructibleObject` with a box mesh).
- **One weapon:** a hitscan "drill" that bores a cylindrical hole (the Point/Pierce archetype from your GDD).
- **One material:** wood (forgiving, visually readable holes).
- **One camera:** free-fly, crosshair, left-click to fire.

**Definition of done — the slice is finished when ALL of these are true:**

1. You can shoot the plank repeatedly and each shot leaves a **persistent hole**.
2. Holes **accumulate** — ten shots leave ten holes, and they're still there a minute later.
3. The collision shape updates so a second shot through an existing hole passes cleanly.
4. It holds **60 fps** while you do this, with **no NaN/explosion** and no runaway slowdown.

No slicing in half. No steel. No house. No island-splitting. No physics projectiles. If you're tempted to add one, write it on the milestone list below instead.

---

## Milestone ladder (add ONE thing per step)

Each milestone must be *fun or stable* before you start the next. If a milestone takes more than a few days, it's too big — cut it in half.

- **M0 — Sandbox. ✅** Free-fly camera, crosshair, a plank, a floor. Click logs a raycast hit. *(No destruction yet.)*
- **M1 — The MVP above. ✅** Hitscan drill bores persistent, accumulating holes in the plank at 60 fps. **This is the whole game in miniature.**
- **M2 — Energy threshold. ✅** Damage is a smooth gradient: below `yield_strength` leaves a shallow surface dent; above it bores a through-hole whose radius scales continuously with energy (sqrt curve) up to `ultimate_strength`. One `yield` and one `ultimate` number on the material. *(Salvage `MaterialData`.)*
- **M3 — Second material + damage shape. ✅** Add steel: same code, different thresholds. Move the radius/depth gradient formula out of `DestructibleObject` and into `MaterialData` as a `compute_hole(energy) -> Vector2` method. Add a `cavity_shape: float` property (0.0 = narrow deep needle, 1.0 = wide shallow crater) so each material owns its damage profile. Wood: wide holes. Steel: narrow deep tunnels. When M5 adds projectile materials, multiply the projectile's `penetration_factor` against the target's curve here. Proves data-driven materials.
- **M4 — Procedural fracture. ✅** Voxel flood-fill (BFS, 6-face, ~900 voxels/object). After each hole, disconnected islands become `DestructibleBody` (RigidBody3D, carries own hole history, fully recursive). Voxels decide WHERE to sever; each fragment RENDERS as a smooth CSG solid (see fracture-face section below), not voxel boxes. Holes are replayed from a persistent `_hole_records` list (body-local transforms) so they survive `_bake_csg` and the body moving. Dust (< `min_frag_fraction`, default 2% volume) deleted silently. Spin proportional to AABB offset; gentle outward separation impulse.

- **Pre-M5 fixes. ✅**
  1. *(deferred)* Occasional small gray CSG artifacts at complex cut boundaries. Cap hole count per object if it becomes a problem during M5 work. **Note:** distinct from the fracture-face issue — this is a Godot CSG rendering glitch (Z-fighting / degenerate polys where CSGBox3D nodes intersect at complex angles), not a voxel quantization problem.
  2. ✅ Fixed — fragment edges no longer show a voxel staircase. Resolved by the clip-plane fragment rendering (see "Fracture Face Aesthetics" below), not by adding voxels.
  3. ✅ Deleted `sever_threshold` from `MaterialData` and both `.tres` resources — unused dead field removed.
  4. ✅ Unified `DestructibleObject` + `FragmentObject` into `DestructibleBody extends RigidBody3D`. Frozen planks use `freeze = true`; spawned fragments unfrozen. CSG always lives in a `Csg` child at origin so `cyl.position` is consistently body-local in both modes. Old scripts deleted; `main.tscn` updated.

- **Fracture Face Aesthetics — ✅ DONE (Option 2, "greedy box decomposition")**
  Implemented in `destructible_body.gd` + `voxel_connectivity.gd`. Each fragment's body is built from greedy-decomposed rectangular boxes that exactly tile its island's voxel footprint (`VoxelConnectivity.decompose_island`). No clip planes. Key notes:
  - **Why greedy boxes over clip planes:** A single clip plane cannot represent non-planar fracture boundaries (L-cuts, circular shots). For an L-cut the old code chose ONE arm's direction, leaving the other arm of the AABB unclipped → ghost geometry. For a circular cut, symmetric centroids → zero `toward` vector → NO plane computed at all → outer ring rendered as a full-AABB box overlapping the inner disc.
  - **Self-healing root cause fixed:** With clip planes, the voxel grid was carved by `carve_halfspace` but only in one direction. Solid voxels in the uncovered arm survived, so a follow-up shot could spawn sub-fragments at unexpected positions ("geometry reappearing"). Greedy boxes sidestep this entirely — the voxel grid is built from the actual box shapes, so all solid voxels are in the correct locations.
  - **Straight cuts** still produce 1-2 large rectangular boxes (clean, no visible staircase for axis-aligned fractures). **L-cuts** produce 2-4 boxes with flat axis-aligned faces. **Diagonal cuts** produce a stairstepped boundary (voxel-resolution staircase on the cut face) — this is a cosmetic trade-off, acceptable for M5.
  - **Removed:** `_fracture_plane`, `add_clip_plane`, `VoxelConnectivity.interface_points/primary_axis/_has_both_within/island_proj_range/carve_halfspace`.
  - Verified visually (`tests/visual_capture.tscn`, windowed, 3 scenarios: straight/L/circle); structurally guarded by `tests/test_split_fragments.gd` (scenarios A-D, all asserting ≥1 body box and 0 clip planes).
  Cosmetic note: hole walls inherit the body material (not default white). Dense drill scallops are bullet damage, not a geometry bug.

- **M4.5 — Fracture definition near breaks (FUTURE, profile-gated).**
  *Observed in playtest:* large objects fracture coarsely. Root cause: every body is voxelised to ~`TARGET_VOXELS` (~900) **regardless of physical size** (`VoxelConnectivity.compute_dims`), so a big object has physically large voxels → blocky/stairstepped cut faces (fragments render as greedy boxes at voxel resolution). Goal: more definition at edges/breaking points **without** a uniform high-res cost. Tiered — do in order, profile between, stop when it looks good:
  - **Decision (2026-06-14, approved):** implement (1) constant cell-size + cap when prioritised; escalate to (2) edge-adaptive refinement or (3) face-smoothing **only if (1) is still too blocky after profiling.**
  1. **Cheap win — target a voxel CELL SIZE with a cap, not a fixed count.** Change `compute_dims` to aim for a roughly constant cell edge (~4–6 cm) capped at a max total (~4–8 k voxels). Large objects gain definition automatically; small ones unchanged; worst case bounded. ~10 lines, low risk. Likely fixes most of the observed blockiness. **Start here.**
  2. **Edge-adaptive refinement (the literal ask).** Keep connectivity coarse (cheap island decision); refine resolution only in a band of voxels adjacent to carved/void cells (the actual break), then greedy-decompose the mixed grid. Targeted high-def only at the break. Medium-high complexity — the single-cell-size assumption baked into `decompose_island` / `aabb_to_local` / `carve_holes` / `build_grid_with_shapes` must become a two-level grid. Do only if (1) is insufficient.
  3. **Smooth the face instead of adding voxels.** The blockiness is partly a RENDER artifact (greedy boxes). Generate the cut face from the actual hole/cut geometry or a marching-cubes-style surface near the boundary. Research-y, and earlier planar-clip approaches failed for non-planar fractures (see Fracture Face Aesthetics). Last resort.
  - **Process (per project rule #5):** profile current cost first on a large body — voxel count, flood-fill + decompose ms, and box count after a *diagonal* cut (worst case for greedy boxes → collision-shape count). Then do (1), measure, escalate only if needed. Don't jump to octree/adaptive before (1) proves insufficient — that's the premature-complexity trap that buried the old project. Watch the collision-shape count: finer voxels on a diagonal cut multiply greedy boxes → physics cost, so (1)'s cap matters.

- **M5 — Enemies. 🔧 in progress**
  - Step 1 ✅ code-complete (pending in-play "is it fun" gate): single-part box enemy. `Enemy extends DestructibleBody`. Chase AI via `_integrate_forces` (XZ plane, direct line toward camera/player); angular X/Z axes locked so it stays upright, unlocked on death. `DestructibleBody` emits `mass_changed(solid_count)` after every connectivity check; enemy connects to it and calls `_die()` when `solid_count / initial_voxels <= (1 - death_threshold)`. Default threshold: 50%.
  - **EnemySpawner:** `scripts/enemy_spawner.gd` — spawns one enemy at a time at a random angle around the camera (`spawn_radius = 8m`). On enemy death (tree_exited), waits `respawn_delay = 2s` then spawns the next. Uses `call_deferred("_do_spawn")` in `_ready()` to avoid "parent busy setting up children" error. Floor expanded to 60×60 to accommodate spawn radius.
  - **Machine gun:** Right-click held fires repeated shots at 80ms interval (`MACHINEGUN_INTERVAL = 0.08s`) via a `Timer` in `fly_camera.gd`.
  - **Camera movement:** WASD/Shift locked to the XZ plane regardless of pitch. Q/E still move the camera vertically.
  - **HUD controls** (Escape to uncapture mouse, then interact):
    - *Enemy Speed* slider (0–10 m/s, step 0.5, default 1.5) — updates all live enemies immediately and is read by `EnemySpawner._do_spawn()` for new spawns (`cam.get("enemy_speed")`). Enemies are registered in the `"enemies"` group.
    - *Wireframe* toggle — `Viewport.DEBUG_DRAW_WIREFRAME`.
    - *Show Collision* toggle — renders semi-transparent overlays on every `CollisionShape3D` in the tree: **green** = physics `BoxShape3D`, **blue** = raycast `ConcavePolygonShape3D` (trimesh). New fragments get overlays automatically via `SceneTree.node_added`; trimesh overlays refresh automatically when `DestructibleBody` emits `collision_rebuilt(shape_node)` after each `_rebuild_collision()`. Toggle off/on to rescan the whole tree. Note: `SceneTree.debug_collision_hint` has no GDScript setter; `--debug-collisions` CLI flag is the engine alternative.
  - **Ghost collision fix:** on fracture, the dying body's `collision_layer` and `collision_mask` are zeroed immediately before `queue_free()`, removing it from Jolt's broadphase in the same step the fragments are added. Prevents the depenetration impulse that made pieces hover/jump at split time.
  - **Compound physics boxes (permanent — implemented):** fragments use a compound of greedy boxes from `VoxelConnectivity.decompose_island` (one `CollisionShape3D` per greedy box) as their physics shape, set at spawn via `_apply_compound_boxes()`. Compound boxes stay for the body's entire lifetime — no sleep/wake swap. Scene-placed bodies (planks, enemies) fall back to a single `body_size` box. The raycast Area3D (layer 2, `_ray_col`) still uses a trimesh built from the CSG mesh after each hole, so shots accurately pass through existing damage.
  - **Compound box sync after each shot:** `_check_connectivity()` now calls `_rebuild_compound_from_island(islands[0])` whenever a shot does NOT split the body (single-island result). Rebuilds greedy boxes from the current carved `_voxels`, so physics collision shrinks with the actual remaining solid volume instead of floating in carved-away space. Debounced by `_connectivity_pending` — runs at most once per frame.
  - **Zero-voxel self-destruct:** if `_voxels.count(1) == 0` after carving (body fully shot away), `_check_connectivity()` wakes neighbors, zeros collision layers, hides CSG, and calls `queue_free()`. Same ghost-collision cleanup as the sever path.
  - **Sleep/wake: trust Jolt's island system.** We investigated a sleep→trimesh→freeze swap (converting sleeping bodies to `FREEZE_MODE_STATIC` with `ConcavePolygonShape3D`) but abandoned it: freezing removes bodies from Jolt's island system entirely, forcing us to re-implement sleep/wake management ourselves. Compound boxes at voxel resolution are accurate enough for gameplay. Jolt handles island sleep/wake natively; we don't fight it.
  - **Fracture-time wake (ActivateBodiesInAABox equivalent):** Jolt intentionally does not wake neighbors when a body is removed (deliberate design, documented in Jolt source). Before `queue_free()` in `_check_connectivity()`, `_wake_nearby_sleeping()` runs a `PhysicsShapeQueryParameters3D` query (body_size × 1.1, layer 1) and sets `sleeping = false` on any sleeping `RigidBody3D` found. This is the GDScript equivalent of `BodyInterface::ActivateBodiesInAABox`.
  - **Wake-chaining:** `sleeping_state_changed(false)` → `_on_sleeping_state_changed` → `_wake_nearby_sleeping()`. When any body naturally wakes (e.g. hit while resting), it propagates the wake to sleeping neighbors. Complements fracture-time wake for stack propagation.
  - **Performance fixes (all implemented):**
    1. *Debounce* — `_connectivity_pending` / `_collision_pending` flags in `apply_hole()` prevent frame stacking when machine gun fires 10+ holes per frame.
    2. *Incremental voxels* — `_voxels: PackedByteArray` cached in `DestructibleBody`; `VoxelConnectivity.carve_holes()` applies only new holes in-place (O(V) per shot vs. O(N×V) rebuild). `_carved_count` tracks how many holes are already baked in.
    3. *CSG bake cap* — after `CSG_BAKE_THRESHOLD = 20` holes, `_bake_csg()` collapses the entire CSG subtree to a single `CSGMesh3D` wrapping the baked `ArrayMesh`, clears all cylinders, resets `_carved_count`. Keeps each subsequent re-evaluation O(1) in history length.
  - **Collision architecture:** Two-layer separation. Physics (layer 1): `BodyCollision` BoxShape3D defined in `enemy.tscn` so Jolt registers it at body-creation time. Raycasts (layer 2): `_init_colliders()` creates an Area3D with a BoxShape3D seed; `_rebuild_collision()` replaces it with a trimesh after each CSG bake so shots accurately pass through existing holes.
  - **Jolt timing rule:** Area3D shapes must be added as children BEFORE the Area3D enters the scene tree (`ray_area.add_child(_ray_col)` then `add_child(ray_area)`). Adding shapes after tree-entry defers registration by one physics step.
  - **Scene file rule:** Direct children of a `.tscn` root node MUST use `parent="."`, NOT `parent="RootName"`. Wrong paths silently orphan the children at instantiation — no editor error, just missing nodes at runtime. This was the root cause of the enemy being unhittable: `_csg == null` → early return → no collision setup.
  - **Test infrastructure:** `tests/test_raycast.gd` + `tests/test_enemy_spawn.gd` are headless smoke-tests. `test_raycast`: verifies Area3D on layer 2 and raycast hit path. `test_enemy_spawn`: verifies EnemySpawner places an enemy on the floor within 15 physics frames. Run with `--headless`.
  - **Definition of done for Step 1:** Enemy chases player. Shooting it carves persistent holes. After enough damage it stops moving and tips over. Fragments still fly if it severs. 60 fps even after many holes on one object.
  - **Step 2 — Multi-part enemies (torso + limbs). ✅ DONE (scene-authored container assembly).** The enemy is an assembly of separate `DestructibleBody` parts welded together, NOT one body. This shape is reused for armour plates (Step 3) and the player body (Step 4).
    - **Why separate welded bodies and not a single multi-box body:** a single body can't keep its chasing identity through dismemberment. `DestructibleBody._check_connectivity` destroys-and-replaces the whole body the instant it splits into ≥2 islands (spawns every island as a fresh inert fragment, then `queue_free`s itself). So "torso keeps coming after losing an arm" is impossible without rewriting the tested M4 fracture core. The torso must be a *persistent* body that survives limb loss → limbs are their own welded bodies.
    - **Architecture:** `scenes/enemy.tscn` root is `Enemy extends Node3D` (`scripts/enemy.gd`) — a thin coordinator, NOT a physics body (avoids the nested-RigidBody hazard; lets limbs/welds be authored in the editor). Children: `Torso` (`EnemyTorso extends DestructibleBody`, `scripts/enemy_torso.gd`) + `ArmL`/`ArmR` (plain `DestructibleBody`) + `WeldL`/`WeldR` (`Generic6DOFJoint3D`). The container is the node in the `"enemies"` group and exposes `move_speed` (forwarded to the torso, since the spawner sets it before the torso ref resolves).
    - **Welds:** `Enemy._lock_weld()` makes each `Generic6DOFJoint3D` a rigid weld — `FLAG_ENABLE_LINEAR_LIMIT`/`FLAG_ENABLE_ANGULAR_LIMIT` true on x/y/z with lower==upper==0. `exclude_nodes_from_collision` (Joint3D default true) stops the torso and its arm from colliding at the overlapping shoulder. **node_a/node_b NodePaths are relative to the JOINT, not the container** — resolve a weld's limb via `joint.get_node_or_null(joint.node_b)` (this bit me once). Verified the weld holds: arm stays at 0.003 m drift in the torso's LOCAL frame while the assembly chases/yaws as a rigid unit.
    - **Chase AI** lives on the torso (`_integrate_forces`, XZ toward camera, angular X/Z locked for upright). Directly setting the torso's `linear_velocity` each frame coexists fine with the welds (confirmed: torso moved + weld held).
    - **Dismemberment:** a limb is its own `DestructibleBody`, so shooting it carves holes / severs it independently. The container detaches a limb (frees its weld, applies a small drop impulse → it falls as a free body keeping its holes) when (a) the limb's remaining mass drops below `limb_detach_fraction` (default 0.45) via its `mass_changed`, or (b) the limb frees itself by self-fracturing (`tree_exited` → free the dangling weld).
    - **Death = vital-part model, owned by the container** (generalised in Step 3a below — originally torso-only). The container watches each VITAL part and topples the enemy when *any one* of them drops to/below `vital_death_threshold` of its own start mass (default 0.5) or is fully removed. Checked **per-part, NOT summed** — each part's voxel grid is independently normalised to ~`TARGET_VOXELS`, so summing would wildly over-weight a thin part. `EnemyTorso.go_limp()` (called by the container's single `_kill()`) releases the upright lock + applies the tip torque; limbs stay welded and tip with the corpse. `_kill()` emits the container's `died` signal — **respawn is driven by `died`, not by the corpse being freed** — so corpses can persist without stalling spawns. **Corpses persist by default** (`despawn_on_death = false`); set it true (with `cleanup_delay`) to re-enable timed removal later. A vital part shattering out from under the assembly is caught via its `tree_exited`. `is_inside_tree()` guards avoid `get_tree()`-null on app shutdown.
    - **Tests:** `tests/test_enemy_limbs.gd` (headless — structure, weld-holds-in-local-frame, detach frees weld, torso survives). `tests/test_enemy_spawn.gd` still green (container satisfies the `Enemy`/`move_speed`/group contract). `tests/test_split_fragments.gd` still fully green (M4 untouched). Visual: `tests/capture_enemy.tscn` (windowed) → `capture_enemy_before/after.png` — confirms the torso+arm figure and a shot-off arm flying free with its holes. **New `class_name`s (`Enemy`, `EnemyTorso`) require `--import` once to register before headless runs resolve them.**
    - **Known cosmetic:** arms are blocky bars close to the torso — reads as a multi-part body, not yet a clean humanoid. Geometry (arm size/offset, adding a head/legs) is tunable in `enemy.tscn` later; not blocking.
    - **Done test (met):** enemy with limbs chases the player; concentrated fire on a limb drops it as a persistent-hole fragment while the torso keeps coming; torso destruction kills + tips the enemy.
  - **Step 3a — Head + vital-part death model. ✅ DONE.** Added a `Head` `DestructibleBody` welded above the torso (`WeldHead`; container `head` NodePath export). The container now distinguishes **VITAL** parts (torso + head — destroying *either* kills, mass-loss per part) from **LIMBS** (arms, future legs — detach and fall when shot up, but NEVER kill). An enemy missing every limb is still alive until a vital part loses enough mass. Death authority is centralised: death logic moved OUT of `EnemyTorso` (now locomotion + `go_limp()` only) INTO `Enemy._kill()`, driven by `_on_vital_mass_changed` / `_on_vital_gone` on torso AND head. **Locomotion stays on the torso** (heavy ground-contact root) — driving movement from the light welded head would fight the joint solver (center-of-gravity reasoning). Headshots are naturally more lethal: per-body voxel normalisation means a hole removes a bigger *fraction* of the small head than of the torso, so 50% head loss comes in fewer shots. *Future "blood loss" (major wounds / lost limbs bleed out over time) is explicitly deferred — not now.* Verified: `tests/test_enemy_head.gd` (head is vital not limb; both arms gone ≠ death; head <50% ⇒ death + torso limp), plus `capture_enemy.tscn` (head renders on top; headshot topples the body).
  - **Step 3a follow-ups (done this session):**
    - **Corpses persist.** `Enemy.despawn_on_death` defaults false; respawn is driven by the container's `died` signal (not by the corpse being freed), so disabling cleanup doesn't stall spawns. Flip the flag (+ `cleanup_delay`) to re-enable timed removal.
    - **Re-anchor welds on fracture.** New `DestructibleBody.fractured(fragments)` signal lets the `Enemy` container move each head/arm weld onto the **nearest surviving fragment** when the torso is cut apart (`_on_torso_fractured` / `_nearest_fragment` / `_weld_parts`), so parts ride the chunk they belong to instead of dropping into the void. A part with no surviving fragment falls free. **Severing a vital core = death** (agreed). The corpse is **rigid**; **floppy ragdoll (loosen the welds on death) is a deferred follow-up.** Re-anchor logic guarded by `tests/test_enemy_reanchor.gd` (deterministic — a clean headless bisect is unreliable, so real fracture behavior was confirmed by playtest, per the "user is the tester" rule).
  - **Step 3b — Steel armor. 🎯 NEXT.** A steel **helmet** welded over the head + a steel **chest plate** welded over the torso, reusing the existing M3 `MaterialData` steel (`resources/steel.tres` — narrow deep tunnels, high thresholds). Each is just one more welded `DestructibleBody` part on the Step 2/3a container with a steel `material_data`/`body_material`. Shots must chew through or knock the plate/helmet off before they damage the soft vital core underneath. Read: armored torso/head is hard to kill, bare limbs are soft. No new material math — composition on the existing assembly, not a new system.
    - **Done test:** shots that would pierce bare wood barely scratch the armored region; sustained fire eventually punches through or detaches the plate, exposing the soft core; armor and core carry independent hole history.
  - **Step 4 — Player as a destructible body + armor + damage UI.** Point the same `DestructibleBody`/armor machinery at the player: the player has a physical body that can be shot (by other enemies/players, or test fire) and takes persistent damage like an enemy. Add a HUD readout that shows damage to the player's own model — a small body-diagram or per-region health that updates as parts take holes / armor is stripped. Reuses Steps 2–3; the new work is the player-side body wiring and the damage UI, not new destruction tech.
    - **Done test:** the player body can be damaged and the HUD reflects which region/armor took the hit in real time; player "death" triggers at a defined mass/region threshold; still 60 fps.
- **M5.5 — Rigged character models (stretch, after M5 combat is fun).** Replace the box-part enemies/player with skinned, rigged meshes that have real limbs. The hard part is **CSG cutting on skinned meshes** — far harder than on static boxes (the mesh deforms with the skeleton, so the voxel grid + hole replay no longer map to a fixed local frame). Expect to either bake holes in a rest-pose local space and reskin, or keep CSG on a static collision proxy while the visual mesh is rigged. Treat this as its own research milestone; do NOT start it until Steps 1–4 are stable and fun, because it threatens the whole hole-persistence pipeline.
  - **Done test:** a rigged enemy walks/animates with limbs, takes a persistent hole that stays correctly placed as it moves and animates, and a limb can still be severed.
  - **Procedural physics movement (exploratory — decide after rigged models land).** Active-ragdoll / physics-driven locomotion instead of `_integrate_forces` velocity-setting. Flagged uncertain by design; revisit only once rigged models exist, since it depends on the skeleton/joint setup from M5.5. May be cut entirely if velocity-driven movement feels good enough.
- **M6 — Physical projectiles (optional).** *Now* add launched rigid bodies, if you still want them. Re-introduce ballistic handling deliberately and in isolation, not as a foundation.
- **M7 — Multiplayer.** Host-authority P2P using Godot's built-in MultiplayerAPI (ENet) + GodotSteam as the transport layer (NAT traversal, no port-forwarding). Architecture: host runs physics and CSG, broadcasts cut events (position/normal/radius structs) and spawns fragments via `MultiplayerSpawner`; clients are dumb renderers. Add only after the destruction system is unified and stable — syncing a partially-unified system compounds the pain.
- **M8 — Sword/slash tool.** Re-analyse once M6 is in — depends on whether physical objects are implemented.
- **M9+ — Everything else:** Steam lobby/matchmaking integration, compound convex decomposition (only if profiling forces it), house/structure, fasteners, blunt craters, 1000 m/s sniper rounds — one at a time.

You had most of M2–M4 *working* in the old project. The goal isn't to relearn it — it's to rebuild it on a foundation that doesn't collapse.

---

## What to salvage vs. delete from `material-destruction-demo`

**Salvage (the ideas were good):**

- `MaterialData.gd` and the `.tres` resources — clean data-driven design, keep it.
- The CSG cutter geometry (cylinder for pierce, plane/box for slash) — the shapes were right.
- The "bake + debounce + cap history" insight — hard-won and correct.
- The impact-archetype concept (pierce / slash / blunt) — good design, just implement it gradually.

**Delete (the complexity that buried you):**

- The entire ballistic/closing-speed/pass-through/cooldown layer in `Destructible.gd`. Replace with a hitscan raycast.
- Runtime voxel island-splitting + compound-convex rebuild as a *default* path. Re-add deliberately at M4.
- Fasteners, house framing, frozen-structure logic — all post-MVP.
- The 2,566-line god-file itself. **Start `Destructible.gd` fresh** and cap it: if it passes ~300 lines, something belongs in another script.

Treat the old repo as a **reference and a parts bin**, not a base to patch. Patching it is how it got to 2,566 lines.

---

## Rules to stop it getting out of hand again

These are process rules, not code. They're what actually went wrong.

1. **No more giant "autonomous agent" design docs.** Handing an AI a 7-phase spec is exactly what generated both the 2,566-line file and the unbuildable C++ GDD. Ask for one small, testable change at a time, and read what comes back.
2. **One feature at a time, and it must run before the next.** If the project can't launch and do its one trick, you don't add a second trick.
3. **Hard file-size ceiling.** Any script over ~300 lines is a smell. Split it.
4. **Every milestone has a "done test"** like the MVP's four checks above. "Done" is observable, not vibes.
5. **Profile before optimizing.** No GPU compute shaders, no C++, until a profiler proves GDScript is the bottleneck on real content. It won't be, at this scale.
5a. **Use strict typing in GDScript.** Declare `var x: float = ...` instead of `var x := ...` whenever the right-hand side is a ternary, a function call with an ambiguous return type, or anything else GDScript can't infer as a concrete type. Variant-typed variables cause parser errors that stop the game cold.
6. **Pick the feel, then protect it.** You chose clean cuts. Anything that doesn't serve clean-cuts fun (soft-body solvers, multiplayer, character controllers) is out of scope until there's a fun core.

---

## What I'd do tomorrow morning

Open a **brand-new** Godot project. Build M0 and M1 only. Get one wooden plank that you can drill persistent holes into at 60 fps. Don't touch steel, slicing, or projectiles until that plank is fun to shoot. When it is, you'll have something you've never had before in this project: **a working core you can build on instead of fight.**

That plank is the childhood dream in miniature. Everything else is just more of it.
