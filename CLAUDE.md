# CLAUDE.md — persistent instructions for Claude Code

This file is read automatically at the start of every session.

## Living documents — keep these in sync

After every milestone completes (or any significant plan change), update **both**:

- `KICKOFF.md` — the "paste into a new session" prompt. Update the current-state section,
  tick off completed milestones, and refresh the "next up" brief.
- `REALISTIC_PLAN.md` — the canonical plan. Update milestone definitions, add ✅ to completed
  ones, and record any new rules or architectural decisions made during the session.

Both files are the source of truth for a future session that has no memory of this one.
If they're stale, the next session starts blind.

## Testing — and how to actually SEE the result

Two complementary layers. Use both; don't trust headless alone for anything visual.

1. **Headless logic tests** (`tests/test_*.tscn`) — fast, run in CI/terminal:
   `Godot_v4.6.3-stable_win64_console.exe --headless --path <proj> res://tests/<scene>.tscn`
   Good for voxel/connectivity/fracture-plane math and node structure. Exit 0 = pass.

2. **Windowed visual capture** — because **CSG geometry does NOT render in `--headless`**
   (`get_meshes()` returns nothing without a renderer). A structural test can pass while
   the geometry looks wrong on screen. `tests/visual_capture.tscn` runs WITHOUT `--headless`,
   builds a scene, performs the action (e.g. drills a burst, severs a plank), freezes the
   pieces, screenshots the viewport to `tests/capture*.png`, and quits:
   `Godot_v4.6.3-stable_win64_console.exe --path <proj> res://tests/visual_capture.tscn`
   Claude can then **Read the PNG and look at it** — this is how the fragment ghost-geometry /
   "wrong axis" bugs were finally diagnosed. The capture PNGs are gitignored (regenerate on demand).

**Rule going forward:** any change that affects what's on screen — CSG cutting, fragment shape,
materials, fracture faces — must be verified with an actual rendered capture, not just headless
asserts. Build a throwaway capture scene if the existing one doesn't cover the case, look at the
image, and only then call it done. Headless proves the math; the screenshot proves the game.

## Project rules (short version — full context in REALISTIC_PLAN.md)

- GDScript only. No C++, GDExtension, or compute shaders.
- Hitscan raycast only for impacts. No physical bullets.
- One milestone at a time. It must run before adding the next.
- Scripts cap at ~300 lines. Split before that ceiling.
- Explicit `var x: float = ...` typing whenever GDScript can't infer the type.
- Profile before optimizing. No premature C++ or GPU work.

## Project locations

- Project: `D:\LOVE\code_projects\Godot\new_physics_project\`
- Godot binaries: `D:\LOVE\code_projects\Godot\Godot_v4.6.3-stable_win64\`
- Reference (parts bin only, do not patch): `D:\LOVE\code_projects\Godot\material-destruction-demo\`
- GitHub: `https://github.com/shisatum/clean-cuts` (public)
