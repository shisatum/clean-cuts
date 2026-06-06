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
- M4 ✅ Voxel flood-fill severs. Fragments use greedy voxel decomposition for correct shape. Recursive.
- Pre-M5 fixes ✅ `DestructibleObject` + `FragmentObject` unified into `DestructibleBody extends RigidBody3D`. `sever_threshold` deleted. See REALISTIC_PLAN.md for the two deferred/accepted cosmetic items.

**Current branch:** `m5-enemies`

**M5 in progress — Step 1: single-part enemy:**
- `Enemy extends DestructibleBody` (`scripts/enemy.gd`). Chase AI in `_integrate_forces` (XZ toward camera). Dies when voxel mass drops below `death_threshold` (default 50%).
- `DestructibleBody` emits `mass_changed(solid_count: int)` after each connectivity check — enemy connects to it.
- Enemy scene: `scenes/enemy.tscn` — reddish 0.5×1.8×0.5m box, wood material.
- `EnemySpawner` node in `main.tscn` (`scripts/enemy_spawner.gd`): spawns one enemy at a random angle around the camera (radius 8m, floor expanded to 60×60); respawns 2s after each death. Uses `call_deferred("_do_spawn")` to avoid parent-busy error.
- **Machine gun:** right-click held fires at 80ms interval via `Timer` in `fly_camera.gd`.
- **Performance:** three fixes in `destructible_body.gd` + `voxel_connectivity.gd` — (1) debounce flags prevent frame stacking, (2) incremental `_voxels` cache + `carve_holes()` keeps voxel cost O(V) per shot, (3) `_bake_csg()` collapses CSG tree to `CSGMesh3D` after 20 holes (`CSG_BAKE_THRESHOLD`).
- **Raycast collision:** Area3D (layer 2) with trimesh shape — `_rebuild_collision()` bakes the CSG mesh after each hole so rays accurately pass through existing damage. Scene-defined `BodyCollision` (BoxShape3D) handles physics separately.
- **Scene file lesson:** In `.tscn` files, direct children of the root node MUST use `parent="."`, NOT `parent="RootName"`. Wrong paths silently orphan the child nodes at instantiation — no error in-editor, just missing children at runtime.
- **Headless tests:** `tests/test_raycast.gd` verifies Area3D/raycast architecture; `tests/test_enemy_spawn.gd` verifies EnemySpawner places an enemy on the floor. Run with `Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/<scene>.tscn`.
- **Done when:** enemy chases player, takes persistent holes, tips over at 50% mass loss, 60 fps even with many holes per object.
- Step 2 (after Step 1 confirmed): multi-part enemies (torso + limbs).

**M6 and beyond:**
- M6: Physical projectiles — reintroduce deliberately, in isolation.
- M7: Multiplayer — host authority + GodotSteam transport.

Read `REALISTIC_PLAN.md`, check the current branch (`git branch`), then continue M5. Ask before adding anything not listed above.
