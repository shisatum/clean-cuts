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

**Next up — M4:**
- Add the Edge/Slash archetype: cut the plank into two independent halves that each keep their existing holes.
- This is where splitting is re-introduced — and only here.
- Each half becomes its own `CSGCombiner3D` with its own collision and hole history.

Read `REALISTIC_PLAN.md`, check the current branch (`git branch`), then build M3. Ask before adding anything not listed above.
