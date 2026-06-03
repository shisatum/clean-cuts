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
- GitHub: `https://github.com/shisatum/clean-cuts` (private)
