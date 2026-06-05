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
- **M4 — Procedural fracture. ✅** Voxel flood-fill (BFS, 6-face, ~900 voxels/object). After each hole, disconnected islands become `FragmentObject` (RigidBody3D, carries own hole history, fully recursive). Fragment shape built from greedy voxel decomposition (`decompose_island`) — no AABB overflow. `build_grid_with_shapes` prevents ghost-solid corner voxels on diagonal/irregular fragments. Dust (< 8% volume) deleted silently. Spin set proportional to COM offset.

- **Pre-M5 fixes (known limitations — resolve before M5):**
  1. Occasional small gray CSG artifacts at complex cut boundaries. Investigate capping hole count per object or baking to ArrayMesh after N holes.
  2. Stepped/staircase appearance on diagonal cut edges — 5cm voxel cells visible. Consider increasing TARGET_VOXELS if it affects feel.
  3. `sever_threshold` on `MaterialData` is **unused** — `split_at_plane` was removed because it caused false rectangular splits from diagonal shots. Either reimplement against the flood-fill BFS result, or **delete the field** before M5.
  4. Pre-M5 refactor: unify `DestructibleObject` + `FragmentObject` into `DestructibleBody extends Node3D`. Attempted once — regression because `cyl.position` means something different when CSGCombiner3D is the root vs a child. Resolve that coordinate-space inconsistency before retrying.

- **M5 — Enemies.** Destructible, material-based bodies that move. An enemy is a `DestructibleBody` with simple AI. Mass-death threshold: compare live voxels to initial voxel count — when a configurable percentage is lost (e.g. 50%), disable AI and let the body collapse. Enemy parts are the same wood/steel destructible objects already built; no new material system needed.
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
