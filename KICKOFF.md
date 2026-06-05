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

**Current state — M0, M1, M2, M3 are complete:**
- M0 ✅ Free-fly camera (WASD/QE/Shift/mouselook), crosshair, floor, plank, hitscan raycast logs hits.
- M1 ✅ Plank is a `CSGCombiner3D`. Clicks bore persistent cylindrical holes aligned to shot direction.
- M2 ✅ Smooth energy gradient: sub-yield = shallow dent, above-yield = through-hole with radius scaling via sqrt curve up to ultimate. Scroll wheel adjusts shot energy live.
- M3 ✅ `MaterialData.compute_hole(energy)` owns the gradient. `cavity_shape` (0=needle, 1=crater) controls hole profile. Wood: wide holes. Steel: narrow tunnels. Two planks in scene.

**Current state — M0 through M4 complete:**
- M4 ✅ Voxel flood-fill severs. Fragments use greedy voxel decomposition for correct shape. Recursive. See REALISTIC_PLAN.md for pre-M5 fix list (4 items, including unused `sever_threshold`).

**Next up — Pre-M5 fixes, then M5:**
- Fix/remove `sever_threshold` on MaterialData (currently unused).
- Decide on unifying DestructibleObject + FragmentObject (see plan doc).
- M5: Enemies — destructible, material-based, AI disabled when mass drops below threshold.
- M6: Physical projectiles — reintroduce deliberately, in isolation.
- M7: Multiplayer — host authority + GodotSteam transport, after destruction system is unified.

Read `REALISTIC_PLAN.md`, check the current branch (`git branch`), then build M3. Ask before adding anything not listed above.
