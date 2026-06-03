# Kickoff prompt — paste into the new session

> Copy everything in the box below into the fresh Sonnet / Code-tab session, pointed at `D:\LOVE\code_projects\Godot\`.

---

I'm building a 3D destruction sandbox in **Godot 4**. The dream is **clean cuts and persistent holes**: shoot a wooden plank, it keeps the holes; later milestones add slicing it in half. There's a full plan at `D:\LOVE\code_projects\Godot\REALISTIC_PLAN.md` — **read it first**, it's the brief.

Keep in mind the Godot binaries are located in D:\LOVE\code_projects\Godot\Godot_v4.6.3-stable_win64\

A previous attempt lives at `D:\LOVE\code_projects\Godot\material-destruction-demo\`. Treat it as a **parts bin and reference only — do NOT patch it.** It collapsed into a 2,566-line god-file. We're starting fresh in a **new project folder** under `D:\LOVE\code_projects\Godot\`.

**Hard constraints (these are why the last attempt failed — respect them):**
- GDScript only. No C++, no GDExtension, no compute shaders.
- Physics: Jolt (Godot 4.4+ default). Cutting: built-in CSG (`CSGCombiner3D`).
- **No physical bullet.** Impacts are a **hitscan raycast** from the crosshair (`intersect_ray` → position, normal, collider). This is non-negotiable; it deletes the entire ballistics-heuristics mess.
- One feature at a time. It must run before we add the next.
- Any script over ~300 lines is a smell — split it.

**Build M0 first, then STOP so I can run it in Godot and report back. Do not jump ahead to M1.**

**M0 — Sandbox (build this now):**
- New Godot 4 project.
- Free-fly camera with mouse-look + WASD, a crosshair in the center of the screen.
- A floor (StaticBody3D) and one wooden plank (a box mesh — this will become the destructible).
- Left-click fires a hitscan raycast from the camera through the crosshair and **prints the hit object, position, and normal** to the console.
- *Done test:* I can fly around, aim, click, and see correct hit info logged. No destruction yet.

**M1 — comes after M0 runs (don't build yet, just keep it in mind):**
- The plank becomes a `DestructibleObject`. A click subtracts a CSG cylinder (a bored hole) at the hit point, oriented along the hit normal.
- Holes persist and accumulate; collision updates so a later shot passes through an existing hole.
- Holds 60 fps, no NaN/explosion.

Start by reading `REALISTIC_PLAN.md`, then scaffold M0. Ask me before adding anything not listed in M0.
