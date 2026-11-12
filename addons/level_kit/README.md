# Level Kit — fast level building

Enabled automatically (Project ▸ Project Settings ▸ Plugins ▸ **Level Kit**).
Open any 3D scene and find the **Level Kit** tab in the right-hand dock.

The goal: block out a playable level in minutes, not hours. Click to place,
drag handles to size, generate whole jump courses, sculpt terrain, then hit
**Play From Here** to test that exact spot.

---

---

## ⭐ Drag to build (fastest way to block out a level)

### Draw to size
In **DRAW TO SIZE**, pick Platform, Pillar/Block, Wall, Ramp, Stairs, Room,
Water, any floor type, Climb Fence, Heal Patch, Dialogue Box or Goal Flag.
Then in the 3D view:
1. **Press** on any surface: terrain, a roof, another platform.
2. **Drag** out the footprint (snapped to the grid). An orange ghost box shows
   the size live, and the status line shows the metres.
3. Hold **Shift** and move the mouse **up/down** to set the height.
4. **Release** to place it. Keep dragging to place more. Right-click or Esc
   stops.

Walls and fences collapse to their thickness along the short side, and ramps
and stairs climb in the direction you dragged. Blocks and walls reach down to
the surface you started on, so they're never floating.

### Orange handles on everything
Select any of these and drag the orange dots to resize that side:
Room (width/depth/height), Hallway, Floor (box or cylinder radius), Terrain
(size, hill height, brush radius), Water (size, depth), Climb Fence, Ladder,
Balance Beam (length), Rope (length), Swing Bar (bar, posts), Heal Patch,
Dialogue Trigger, Location Flag, Flatten Pad (radius, blend), Terrain Path
(road width), Ground Pound Mound, Cred Gate, Dialogue Camera Bounds, and Curved
Floor. Platforms have their own handles. Every drag snaps to the grid and is
one Ctrl+Z.

### Rotation arc
Select any object and a **cyan semi-circle** appears around its feet, with a
yellow arrow showing which way it faces and a **knob** at the front. Drag the
knob around the circle to turn the object. It snaps to **15°** steps; hold
**Shift** for free rotation. The angle shows in the status line. One drag is
one Ctrl+Z, and it works inside rotated parents. Toggle it with **Rotation
arc** under CHECK.

### Edge snap
Drag a Platform, Floor, Room or Climb Fence near another one and it **clicks
flush**: side by side, edges lined up, tops level, or stacked on top. The gap
ruler shows "SNAPPED". Hold **Ctrl** while dragging to place freely. Toggle it
with **Edge snap** under ASSIST.

### Alt-drag copy
Hold **Alt** when you start dragging something with the move tool. A copy
stays at the starting spot and you drag the original away.

### Gap ruler
With a Platform selected, a line and label point to the nearest platform:
`12.0m gap · level / to P03: Run jump ✓ / back: …`. It turns **green** when
the jump is makeable and **red** when it's too far, using Inke's measured
jumps. It updates live as you drag.

### Scatter brush
Select a terrain, choose a set (**Forest, Beach, Meadow, Rocky, Pines**),
press **Paint** and drag. **Shift**+drag erases. Props get random size and
rotation and sit on the ground. "Keep off paths…" skips cliffs, roads,
flatten pads and anything near your platforms, so gameplay stays clear. The
props are `LKProp` nodes: rock, boulder, tree, pine, palm, bush, grass,
flowers, stump and log, built in code with no assets. Change `seed` to reroll
one; they're also in PLACE ▸ Scenery.

### Level stats
**Refresh stats** shows the estimated run time versus the 10-minute target,
whether quests plus medallions are enough for your CRED gate, counts of
everything, and a warning when checkpoints are too far apart.

### Surface snap
On by default. Move anything with Godot's normal move tool, sideways, and it
**slides along the ground under it**: over hills, onto roofs and platforms.
Drag it vertically if you really want it in the air.

### Quick menu
Press **Q** in the 3D view: a ring of the 12 most-used items opens at the
cursor (slab, pillar, ramp, CRED, gear, crate, inkling, checkpoint, grapple
point, spring floor, sign, health). Click one to drop it there. Q or Esc
closes the ring.

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

---

# Level Tools (third dock tab)

### Play test
- **▶ Play from here**: Inke spawns where the viewport is looking.
- **▶ Play from selected**: Inke spawns standing on top of whatever is
  selected (a platform, a checkpoint, a peak).
- **■ Stop.** "Play inside the editor" runs the game in Godot's embedded Game
  tab instead of a separate window. Edit something, press Play again, and the
  scene saves and restarts with all upgrades.

### Moving floors: drag the path
Select a Moving floor. A dashed line and a ghost outline show where it
travels. **Drag the cyan ball** to set the end point (Shift+drag moves it up
or down). Spinning floors show an orange arc sized by speed; drag its ball
outward to spin faster (5–720°/s).

### Align & spread (select 2 or more)
- **Align X / Align Z / Same height**: line them up with the first selected
  one. Same height matches the tops of platforms.
- **Spread X / Z / along a line**: space them evenly between the first and
  last, or with **Fixed gap** exactly that many metres between edges.
- **Ground all** drops them onto the ground. **Face same way** turns them to
  match the last-clicked object. **Random turn** gives each a random rotation.

### Looks
Click a swatch (Stone, Wood, Metal, Grass, Sand, Snow, Crystal, Punk Pink,
Toxic, Brick, Night, Gold) to restyle the selected platforms, props and room
walls. **Copy look from active** copies the last-clicked object's look onto
the rest of the selection. **Toggle edge trim** turns platform trim on or off.

### Hide & lock
Each category (Enemies, Pickups, Breakables, Scenery, Dialogue, NPCs,
Terrain, Water, Platforms) has a 👁 hide toggle and a 🔒 lock toggle (locked
things can't be clicked or moved). Hiding is editor-only: hidden things are
automatically shown again before every save and play, so the real level
never ends up invisible.

### Camera bookmarks
Type a name and **Save view**. Click a bookmark to fly there; right-click
deletes it. Bookmarks are saved inside the scene file.

### Auto checkpoints
Set the max spacing (default 90m). **Suggest** lists every place (platforms,
quest givers, rails, flags, the boss) that's further than that from a
checkpoint. **Add them** places checkpoints there, on the ground.

## Files
- `level_kit.gd` – editor plugin and dock
- `nodes/platform.gd` – the Platform node
- `platform_gizmo.gd` – handles, reach rings, reach lines
- `generators.gd` – course layouts
- `jump_arcs.gd` – measured jump data (generated)
- `tools/record_arcs.gd` – re-measures jump arcs from the live controller
- `kit_tools.gd` – Level Tools tab (play test, align, looks, hide/lock, bookmarks, auto checkpoints)
- `motion_gizmo.gd` – moving/spinning floor path handles
- `rotate_gizmo.gd`, `world_gizmo.gd`, `drag_build.gd`, `build_assist.gd` – handles, draw-to-size, snapping, scatter, stats
- `nodes/prop.gd` – code-built scenery props
- `kit_plus.gd` – Level Kit+ tab (script writer, quest wizard, draw, stamps)
- `stamps/` – saved stamps
- `runtime/play_here.gd` – tiny autoload behind Play From Here (inert unless
  launched from the dock)
