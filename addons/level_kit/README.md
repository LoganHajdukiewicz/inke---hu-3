# Level Kit — fast level building

Enabled automatically (Project ▸ Project Settings ▸ Plugins ▸ **Level Kit**).
Open any 3D scene and find the **Level Kit** tab in the right-hand dock.

The goal: block out a playable level in minutes, not hours. Click to place,
drag handles to size, generate whole jump courses, sculpt terrain, then hit
**Play From Here** to test that exact spot.

---

## 1. Place anything with one click

Pick an item in **PLACE**, then click in the 3D viewport.

- The object lands **on the surface you clicked**: terrain, a platform, or
  the y=0 plane if the scene is empty. No more dragging things out of the
  ground or guessing Y.
- It **keeps placing** with every click. **Right-click** or **Esc** stops.
- **Shift + click** stacks the new object on the top of whatever you clicked.
- **Grid** snaps the X/Z position (0 = off). **Align** tilts objects to
  the slope. **Rand yaw** randomly rotates each placement, which is useful
  for scattering crates and rocks.
- Everything is filed into tidy folders (`LK_Platforms`, `LK_Enemies`,
  `LK_Pickups`…) so the Scene tree stays readable.
- Every placement is one **Ctrl+Z**.

Catalogue: 8 platform shapes, every gameplay floor type, all traversal pieces
(grapple, swing bar, rope, ladder, fence, beam, rail, ground-pound mound),
pickups, breakables, all 10 enemies plus the spawner, checkpoints/reset
plane/heal patch/sign/button/door/scene exit/dialogue trigger/water, and
Room/Hallway/Terrain.

## 2. The Platform node (drag to size)

A **Platform** is one node that can be a **slab, round pillar top, ramp,
stairs or arch bridge**. You can also add it from Add Node ▸ "Platform".

- Select it and **drag the orange handles**: width, depth, thickness and
  rise (ramps, stairs and arches). Drags snap to the Level Kit grid.
- The node origin is the **centre of the top surface**, so its Y is exactly
  the height Inke stands at.
- `pillar_depth` extends the body down to the ground to make a pillar.
- **Look**: Stone / Wood / Metal / Grass / Sand / Snow / Crystal / Custom,
  with an optional darker edge trim so ledges read clearly.
- Always ledge-grabbable, with collision generated at load time. Scene files
  stay tiny.

## 3. Courses — jump-tested layouts in one click

**COURSES** builds a whole section at the point the viewport is looking at:

| Button | What you get |
|---|---|
| Stepping Stones | A path of platforms, each one jump apart, optionally climbing (**Rise**) |
| Spiral Tower | Platforms spiralling up around a central column |
| Block Climb | Big chunky steps, each a hop up |
| Floating Islands | Scattered grass islands, auto-pulled so none are unreachable |
| Gauntlet | Mixed course: stones, ramps, arch bridges, long-jump gaps, raised goal |

**Move** sets which ability the gaps are sized for (Walk / Run / Double / Long
dash jump). **Difficulty** controls where a full-commitment jump lands on the
next platform: 0 = deep into it (forgiving), 1 = just past its near edge
(tight). The whole course is one node, so you can move or rotate it as a
unit, then hand-edit individual platforms.

### Jump distances are measured, not guessed
`jump_arcs.gd` holds Inke's **real recorded jump trajectories** (walk, run,
double, long). Generated gaps were then verified by headless runs in which
the real controller jumped every gap. **If you retune movement**, re-record:

```
godot --headless --path . -s res://addons/level_kit/tools/record_arcs.gd
```

The dock also shows the current numbers (flat reach, reach going up 2m, apex).

## 4. Terrain tools

Select a **Terrain** node, then:

**Brushes** (drag in the viewport; click the button again or Esc to stop):
- **Raise / Lower** – sculpt up or down
- **Flatten** – levels the ground to the height where you **first clicked**;
  drag to extend the flat area (roads, building sites)
- **Smooth** – softens spikes and noise
- **Plateau** – builds a flat-topped mesa at click height + strength
  (it only raises, so dragging widens the mesa)

**Size** and **Strength** sliders control the brush. One drag = one Ctrl+Z.

**Stamps** (applied at the viewport point, or the terrain centre):
**Island** · **Mountain** · **Valley** · **Crater** · **Ridge** · **Clear
Sculpt**. Each is undoable. Stamps and brushes write to the Terrain's painted
layer, so the existing Terrain features (walkable mountain flanks, snow caps,
beaches, FlattenPads, TerrainPaths) all still apply on top.

## 5. Check your level

- **Jump reach rings** – around the selected Platform: coloured rings showing
  how far each move reaches at the same height (green walk, blue run, yellow
  double, magenta long).
- **Reach lines** – from the selected Platform to nearby ones: **green** = the
  jump is makeable (with some move), **red** = too far or too high.
- **Validate Level** reports: missing Inke, no reset plane, platforms that are
  probably **unreachable** from the start, pickups with **no ground under
  them**, pickups **buried in terrain**, and duplicate checkpoint IDs.
  (Grapples and ropes aren't counted for reachability, so treat
  "unreachable" as "check this".)

## 6. Play From Here

**▶ Play From Here** (or **Ctrl+Shift+P** in the viewport) saves, then runs
the scene with Inke standing **where the 3D viewport camera is looking**,
facing the same way, **with every movement upgrade granted**. Falling off
respawns you at that spot too. Normal F5/F6 play is unaffected (the spawn
file is consumed on use and expires after 2 minutes).

## Viewport hotkeys (with something selected)

| Key | Action |
|---|---|
| **D** | Duplicate the selection one comfortable run-jump forward (along its facing). Press repeatedly to lay out a line of platforms. |
| **Alt+G** | Drop the selection straight down onto whatever is below it |
| **Ctrl+Shift+P** | Play From Here |

---

# Level Kit+ (second dock tab)

The slow parts of building a level, one click each. Everything is undoable.

## Script Writer — dialogue without JSON
Type in the box, one message per line:
```
S-1GN: Oh hey! You stopped to read me! [uwu]
Press X to jump.                       <- no speaker = same as the last line
But you're so smart I bet you already knew that. [owo]
HU3: The sign is talking again.
```
`[uwu] [owo] [anxious]` set S-1GN's portrait. Any other `[name]` uses
`assets/portraits/name.png`.
- **Save dialogue** writes `dialogue/<SceneRootName>/<File>.json`, which is
  exactly where DialogueManager looks.
- **Save + place S-1GN sign**: click in the viewport to drop a sign that plays
  it, facing the camera and with camera side-walls already on.
- **Save + place walk-in trigger**: an invisible box that plays the dialogue
  once, automatically, when Inke walks in. Good for S-1GN's "OH NO I FORGOT"
  moments.
- **Load** pulls an existing file back into the box as plain text.

## Quest Wizard — a quest and its giver in one step
Fill in the NPC name, title, type, count, CRED reward, an optional CRED
requirement to talk, small talk and the ask. Then **Create**, and click to
place the giver. It saves `quests/q_<npc>_<title>.tres` and wires it to the
giver.
- `reach_location`: a second click places the matching goal flag.
- `fetch_item`: a second click places the item to fetch.

## Draw
Click points in the viewport. **Enter** or right-click finishes,
**Backspace** removes the last point, **Esc** cancels. A live line shows the
path.
- **Draw Rail**: a grindable rail through your clicks at the set height,
  smoothed or sharp.
- **Draw Terrain Road**: click on a Terrain to carve a flat walkable road
  (a TerrainPath).
- **Draw Scatter Line**: drops copies of any catalogue item every N metres
  along the line, each sitting on the ground. For trails of CRED, gears,
  crates or enemies.

## Stamps — reusable sections
Select nodes, name them, then **Save selection**. Double-click a stamp to
click-place copies (Rand yaw applies). Each copy is plain editable nodes, not
a linked instance.

Starter stamps (cut from the 11-21 demo): **Floor_Gauntlet_Shipwreck**,
**Vertical_Climb_Summit**, **Combat_Camp_Junkyard**, **Boss_Arena_Islet**.

## Files
- `level_kit.gd` – editor plugin and dock
- `nodes/platform.gd` – the Platform node
- `platform_gizmo.gd` – handles, reach rings, reach lines
- `generators.gd` – course layouts
- `jump_arcs.gd` – measured jump data (generated)
- `tools/record_arcs.gd` – re-measures jump arcs from the live controller
- `kit_plus.gd` – Level Kit+ tab (script writer, quest wizard, draw, stamps)
- `stamps/` – saved stamps
- `runtime/play_here.gd` – tiny autoload behind Play From Here (inert unless
  launched from the dock)
