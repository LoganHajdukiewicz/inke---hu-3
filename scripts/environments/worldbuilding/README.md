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

### Doorway — doors and windows
Add a **Doorway** as a CHILD of the Room and drag it toward a wall —
it snaps to the nearest wall and cuts an opening (walls rebuild into
segments + lintel/sill automatically):

- `sill_height = 0` → a door
- `sill_height = 1.2` → a window
- `width` / `height` shape the opening

### Buildings
Snap Rooms side by side (corners overlap cleanly thanks to wall
thickness padding) and put matching Doorways on the shared wall of
each room. Outside, drop a FlattenPad on the Terrain under the
building. Set `has_floor = false` when a room sits directly on a
Floor/Terrain. Stack rooms for multiple storeys (`has_ceiling` off +
a Room above with `has_floor` on).

All generated geometry is runtime-only — your scene files stay tiny,
and everything re-generates when the scene loads.
