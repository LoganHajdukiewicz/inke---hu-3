# Worldbuilding tools

Tools for organic outdoor terrain and quick building interiors.
The `Floor` scene is still the tool for gameplay floors (moving,
spinning, spring, damage...) — these are for the world AROUND that.

## Terrain — organic outdoor ground

Add a **Terrain** node (or instance `scenes/environments/worldbuilding/terrain.tscn`).
Rolling noise-based hills with grass/rock/dirt coloring and exact
collision, all rebuilt live as you tweak the Inspector:

- **Shape**: size, resolution, hill_height, edge_falloff/edge_height
  (fade the rim down to make islands or blend into other geometry)
- **Noise**: noise_seed (reroll the hills), hill_frequency (few big
  mounds vs busy bumps), detail_octaves
- **Colors**: grass/rock/dirt + rock_steepness (how steep before slopes
  turn rocky)

`get_height(world_pos)` returns the ground height at any point —
useful for scattering props from scripts.

### FlattenPad — building sites
Add a **FlattenPad** as a CHILD of the Terrain, drag it where a
building should go: the ground flattens to the pad's height in
`radius`, blending back into the hills over `blend` meters. Live in
the editor. Use one per building/arena/spawn clearing.

## Room — instant interiors

Add a **Room** node (or instance `room.tscn`): floor + 4 walls +
ceiling from one node. `interior_size` is the inside space.

### Room modes (`room_mode`)
- **Snap With Doorway** (default, the main flow): drag a room near
  another and it snaps flush against it — and a doorway is cut through
  the shared wall automatically. Chain rooms into whole buildings by
  just dragging them next to each other. `auto_doorway_width/height`
  and `snap_distance` tune it.
- **Merge**: drag the room so it OVERLAPS another room — it merges into
  it, becoming one large irregular space (L-shapes, T-shapes). The
  shared walls vanish; the merged room contributes its footprint to the
  host room's geometry.
- **Snap Only**: snaps flush like the default but keeps the shared wall
  solid — for when two rooms should touch without a connecting door.

### Doorway — doors and windows
Add a **Doorway** as a CHILD of the Room and drag it INTO a wall —
the opening is carved right where the marker sits (CSG subtraction),
live in the editor. No snapping rules: wherever it overlaps a wall,
there's a hole.

- `sill_height = 0` → a door
- `sill_height = 1.2` → a window
- `width` / `height` shape the opening
- the cut auto-rotates toward the nearest wall; rotate the Doorway
  node yourself to override (e.g. diagonal walls)

### Doors, locks and keys
Every Doorway spawns an interactable **Door** by default (`has_door`
untick = open archway; windows never get doors). Walk up and press
**E** to open/close. Doors are **unlocked by default** — tick
`door_locked` on the Doorway (or `locked` on a hand-placed Door) to
require a **Key** (scenes/items/Collectibles/key.tscn) with a
matching `key_id`. Keys are placeable anywhere, including as
GroundPoundMound loot (set the mound's `collectable_scene` to
key.tscn). Open styles: swing (default), slide up/down, vanish;
`consume_key` controls reusability. HU-3 never picks up keys.

### Ceiling lights
Rooms spawn ceiling lights automatically (`has_lights`, default on;
`light_count` for how many). New lights are laid out in a grid, but
drag any **RoomLight** wherever you want — they never get
repositioned. Color/energy/range/shadows per light or room-wide.

### Buildings
Drag Rooms next to each other (they snap + auto-doorway by default).
Outside, drop a FlattenPad on the Terrain under the building. Set `has_floor = false` when a room sits
directly on a Floor/Terrain. Stack rooms for multiple storeys
(`has_ceiling` off + a Room above with `has_floor` on).

All generated geometry is runtime-only — your scene files stay tiny,
and everything re-generates when the scene loads.
