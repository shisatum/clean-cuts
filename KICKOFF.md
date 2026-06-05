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
- `Enemy extends DestructibleBody` (`scripts/enemy.gd`). Patrol AI in `_integrate_forces`. Dies when voxel mass drops below `death_threshold` (default 50%).
- `DestructibleBody` emits `mass_changed(solid_count: int)` after each connectivity check — enemy connects to it.
- Enemy scene: `scenes/enemy.tscn` — reddish 0.5×1.8×0.5m box, wood material.
- One enemy placed in `main.tscn` at (0, 0.9, 3) for testing.
- **Done when:** enemy patrols, takes persistent holes, tips over at 50% mass loss, 60 fps.
- Step 2 (after Step 1 confirmed): multi-part enemies (torso + limbs).

**M6 and beyond:**
- M6: Physical projectiles — reintroduce deliberately, in isolation.
- M7: Multiplayer — host authority + GodotSteam transport.

Read `REALISTIC_PLAN.md`, check the current branch (`git branch`), then continue M5. Ask before adding anything not listed above.
