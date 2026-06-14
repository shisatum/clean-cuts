# Kickoff prompt — paste into a new Claude Code session

> **Canonical location:** this file lives at `D:\LOVE\code_projects\Godot\new_physics_project\KICKOFF.md`.
> Point the session at `D:\LOVE\code_projects\Godot\new_physics_project\` when pasting.

---

I'm building a 3D destruction sandbox in **Godot 4**. The dream is **clean cuts and persistent holes**: shoot a wooden plank, it keeps the holes; later milestones add slicing it in half. The full plan is at `D:\LOVE\code_projects\Godot\new_physics_project\REALISTIC_PLAN.md` — **read it first**, it's the brief.

The project lives at `D:\LOVE\code_projects\Godot\new_physics_project\`. Godot binaries are at `D:\LOVE\code_projects\Godot\Godot_v4.6.3-stable_win64\`.

A previous attempt lives at `D:\LOVE\code_projects\Godot\material-destruction-demo\`. Treat it as a **parts bin and reference only — do NOT patch it.**

**Hard constraints:**
- GDScript only. No C++, no GDExtension, no compute shaders.
- Physics: Jolt. Cutting: built-in CSG (`CSGCombiner3D`).
- **No physical bullet.** Impacts are a hitscan raycast (`intersect_ray` → position, normal, collider).
- One feature at a time. It must run before we add the next.
- Any script over ~300 lines is a smell — split it.
- Use explicit `var x: float = ...` typing whenever GDScript can't infer the type (ternaries, ambiguous returns).

**Current state — M0 through M4 + pre-M5 fixes complete:**
- M0 ✅ Free-fly camera (WASD/QE/Shift/mouselook), crosshair, floor, plank, hitscan raycast logs hits.
- M1 ✅ Clicks bore persistent cylindrical holes aligned to shot direction.
- M2 ✅ Smooth energy gradient: sub-yield = shallow dent, above-yield = through-hole with radius scaling via sqrt curve up to ultimate. Scroll wheel adjusts shot energy live.
- M3 ✅ `MaterialData.compute_hole(energy)` owns the gradient. `cavity_shape` (0=needle, 1=crater) controls hole profile. Wood: wide holes. Steel: narrow tunnels. Two planks in scene.
- M4 ✅ Voxel flood-fill severs. Voxels decide WHERE to cut; each fragment's body is built from **greedy-decomposed boxes** (`VoxelConnectivity.decompose_island`) that exactly tile its island's voxel footprint, minus hole cylinders. No clip planes. Recursive.
- Fracture-face polish ✅ (docs option 2, greedy boxes) Replaced the earlier clip-plane approach (option 3) which broke for non-planar fractures — L-cuts only got ONE clip plane (leaving ghost geometry on the uncovered arm), and circular shots could produce near-zero centroid direction (no plane at all, full-AABB ghost). Greedy boxes fix both: each fragment renders only its actual voxel-covered region. Straight/L cuts still have flat axis-aligned faces; diagonal cuts have a voxel-resolution staircase (cosmetic trade-off). Verified visually via `tests/visual_capture.tscn` (straight + L + circle scenarios).
- Pre-M5 fixes ✅ `DestructibleObject` + `FragmentObject` unified into `DestructibleBody extends RigidBody3D`. `sever_threshold` deleted.

**Current branch:** `m5-enemies`

**M5 in progress — Step 1: single-part enemy:**
- `Enemy extends DestructibleBody` (`scripts/enemy.gd`). Chase AI in `_integrate_forces` (XZ toward camera). Dies when voxel mass drops below `death_threshold` (default 50%).
- `DestructibleBody` emits `mass_changed(solid_count: int)` after each connectivity check — enemy connects to it.
- Enemy scene: `scenes/enemy.tscn` — reddish 0.5×1.8×0.5m box, wood material.
- `EnemySpawner` node in `main.tscn` (`scripts/enemy_spawner.gd`): spawns one enemy at a random angle around the camera (radius 8m, floor expanded to 60×60); respawns 2s after each death. Uses `call_deferred("_do_spawn")` to avoid parent-busy error.
- **Machine gun:** right-click held fires at 80ms interval via `Timer` in `fly_camera.gd`.
- **Camera:** WASD/Shift locked to XZ plane; Q/E for vertical.
- **HUD controls** (Escape to uncapture mouse): *Enemy Speed* slider (0–10, default 1.5) — live enemies + new spawns; *Wireframe* toggle; *Show Collision* toggle (green=physics box, blue=trimesh, auto-updates on fracture via `collision_rebuilt` signal).
- **Ghost collision fix:** dying body's `collision_layer/mask` zeroed before `queue_free()` so Jolt drops it before fragments are added — prevents hover-at-split-point.
- **Performance:** three fixes in `destructible_body.gd` + `voxel_connectivity.gd` — (1) debounce flags prevent frame stacking, (2) incremental `_voxels` cache + `carve_holes()` keeps voxel cost O(V) per shot, (3) `_bake_csg()` collapses CSG tree to `CSGMesh3D` after 20 holes (`CSG_BAKE_THRESHOLD`).
- **Raycast collision:** Area3D (layer 2) with trimesh shape — `_rebuild_collision()` bakes the CSG mesh after each hole so rays accurately pass through existing damage. Scene-defined `BodyCollision` (BoxShape3D) handles physics separately.
- **Compound physics boxes (permanent):** fragments use compound `BoxShape3D` collision (one per greedy box from `decompose_island`), set at spawn, never swapped. No freeze/trimesh — that pattern removed bodies from Jolt's island system and required reimplementing sleep/wake manually. Compound boxes stay dynamic; Jolt handles sleep/wake natively. Raycast trimesh (layer 2 Area3D) still built from CSG mesh for accurate shot-through-holes. Boxes resync to current `_voxels` after every shot (`_rebuild_compound_from_island` in `_check_connectivity`). If all voxels are carved to zero, body self-destructs (wakes neighbors, zeros collision layers, queue_free).
- **Wake on fracture + wake-chaining:** `_check_connectivity` calls `_wake_nearby_sleeping()` before `queue_free()` (GDScript equivalent of Jolt's `ActivateBodiesInAABox` — Jolt intentionally does not wake neighbors on removal). `sleeping_state_changed(false)` also calls `_wake_nearby_sleeping()` so wakeups propagate through resting stacks.
- **Scene file lesson:** In `.tscn` files, direct children of the root node MUST use `parent="."`, NOT `parent="RootName"`. Wrong paths silently orphan the child nodes at instantiation — no error in-editor, just missing children at runtime.
- **Headless tests:** `tests/test_raycast.gd` verifies Area3D/raycast architecture; `tests/test_enemy_spawn.gd` verifies EnemySpawner places an enemy on the floor; `tests/test_split_fragments.gd` covers fracture structure (scenarios A=straight, B=two cuts, C=diagonal, D=L-cut — all assert ≥1 body box, 0 clip planes, non-empty voxels). `tests/test_clip_plane.gd` is now obsolete (clip planes removed) but not deleted. Run with `Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/<scene>.tscn`. **CSG does not render headless** — use `tests/visual_capture.tscn` WITHOUT `--headless` to eyeball fragment geometry (writes `tests/capture_multi.png`, three scenarios: straight/L/circle).
- **Done when:** enemy chases player, takes persistent holes, tips over at 50% mass loss, 60 fps even with many holes per object. **Step 1 is code-complete — only the in-play "is it fun" gate remains.**

**M5 Step 2 — multi-part enemies (torso + limbs). ✅ DONE + verified.**
The enemy is a scene-authored **container assembly**: `enemy.tscn` root = `Enemy extends Node3D` (`scripts/enemy.gd`, thin coordinator, in the `"enemies"` group, forwards `move_speed`) holding a `Torso` (`EnemyTorso extends DestructibleBody`, `scripts/enemy_torso.gd` — chase AI + upright lock + torso-mass death) + `ArmL`/`ArmR` (plain `DestructibleBody`) + `WeldL`/`WeldR` (`Generic6DOFJoint3D` rigid welds). Key facts learned:
- A single multi-box body CAN'T do this — `_check_connectivity` destroys-and-replaces the whole body on any split, so the chasing torso identity is lost. Persistent torso ⇒ limbs must be separate welded bodies.
- Weld = `Generic6DOFJoint3D` with linear+angular limits enabled, lower==upper==0 on x/y/z (`Enemy._lock_weld`). **node_a/node_b are relative to the JOINT** — resolve via `joint.get_node_or_null(joint.node_b)`.
- A limb detaches (weld freed, falls as a free body keeping its holes) when its remaining mass drops below `limb_detach_fraction` (0.45) or it self-fractures. **Corpses persist by default** (`despawn_on_death = false`); respawn is driven by the container's `died` signal, NOT by the corpse being freed, so disabling cleanup doesn't stall spawns. Flip `despawn_on_death` on (with `cleanup_delay`) to re-enable timed removal.
- New `class_name`s need one `--import` to register before headless runs. Tests: `test_enemy_limbs` (structure/weld/detach), `test_enemy_spawn`, `test_split_fragments` all green; `capture_enemy.tscn` (windowed) shows the figure.

**M5 Step 3a — head + vital-part death model. ✅ DONE.**
Added a `Head` `DestructibleBody` welded above the torso (`head` NodePath on the container). The container distinguishes **VITAL** parts (torso + head — destroying *either* kills via mass loss) from **LIMBS** (arms/legs — detach but NEVER kill; an enemy missing every limb is still alive). Death moved out of `EnemyTorso` (now locomotion + `go_limp()` only) into the container's single `_kill()`, driven by `_on_vital_mass_changed`/`_on_vital_gone` watching torso AND head. **Locomotion stays on the torso** (heavy root; driving from the light head fights the joint solver). Death is checked **per vital part, not summed** (per-body voxel normalisation would over-weight thin parts); headshots are naturally lethal in fewer shots. **"Blood loss" from wounds/lost limbs is deferred — not now.** Verified by `test_enemy_head.gd` + the headshot-topple capture.

**Also done this session:** corpses persist (`despawn_on_death`=false; respawn via `died` signal). **Re-anchor welds on fracture** — `DestructibleBody.fractured(fragments)` → `Enemy._on_torso_fractured` moves head/arm welds onto the nearest surviving fragment when the torso is cut apart, so parts stay attached (sever a vital core = death; corpse is rigid). **Deferred follow-up: floppy ragdoll** (loosen welds on death). Verified by `test_enemy_reanchor.gd` + playtest.

**Next up — M5 Step 3b: steel armor. 🎯**
A steel **helmet** welded over the head + a steel **chest plate** welded over the torso — each one more welded `DestructibleBody` part on the existing container with steel `material_data`/`body_material` (reuse `resources/steel.tres`). Shots must defeat the plate/helmet before the soft vital core. Pure composition on the assembly; no new material math.

**Backlog — M4.5 (fracture definition, profile-gated):** large objects fracture coarsely because every body is voxelised to ~900 voxels regardless of size. Fix tiered: (1) target a voxel cell SIZE with a cap instead of a fixed count [start here]; (2) edge-adaptive refinement only near breaks; (3) smooth the cut face instead of adding voxels. Profile before escalating. See REALISTIC_PLAN.md.

**M5 roadmap after Step 3 (in REALISTIC_PLAN.md):**
- Step 4: player as a destructible body + armor + a HUD damage readout showing which region/armor took the hit.
- M5.5 (stretch): rigged character models with real limbs — hard part is CSG on skinned meshes; its own research milestone, only after Steps 1–4 are fun. Procedural physics movement is exploratory and decided after rigged models land (may be cut).

**M6 and beyond:**
- M6: Physical projectiles — reintroduce deliberately, in isolation.
- M7: Multiplayer — host authority + GodotSteam transport.

Read `REALISTIC_PLAN.md`, check the current branch (`git branch`), then continue M5. Ask before adding anything not listed above.
