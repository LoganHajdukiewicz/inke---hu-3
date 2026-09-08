@tool
extends StaticBody3D
class_name Terrain
## Organic outdoor ground. Generates rolling noise-based terrain with
## grass/rock coloring, exact walk collision, and flat building pads.
##
## HOW TO USE:
##   1. Add a Terrain node to your level (or instance terrain.tscn)
##   2. Tweak Shape/Noise exports in the Inspector - it rebuilds live
##   3. Need a flat spot for a building? Add a FlattenPad child, move it
##      where you want, set its radius - the ground flattens under it
##      at the pad's height.
##   4. BEACHES: when the terrain touches a WaterZone, the ground within
##      sand_distance meters (default 30) of the SHORELINE (where the
##      terrain actually dips under the water surface) gets sand coloring.
##      Interior ground that never touches the water stays green, even on
##      an island completely surrounded by one big water rectangle.
##   5. PAINTING: turn on paint_mode and left-click in the 3D viewport to
##      raise the ground under the cursor (hold Shift to lower it). Brush
##      radius/strength live in the Inspector. Sculpt ridges, valleys and
##      topographical islands by hand - painted height saves with the
##      scene and stacks on top of the noise hills. Ctrl-Z undoes strokes.
##      MOUNTAIN RULE: painted peaks keep their full height (no cap) and
##      grow a WALKABLE flank around themselves by default - the ground
##      rises to meet them at max_slope_degrees. Where the flank CAN'T
##      spread (terrain border, FlattenPads, TerrainPaths), the mountain
##      silently goes steep/pointy there instead - tall enough peaks
##      naturally become unclimbable walls.
##
## The generated mesh/collision are runtime-only children (not saved
## into your scene file), so scenes stay tiny.

@export_group("Shape")
## Total ground size in meters (X by Z).
@export var size: Vector2 = Vector2(80, 80):
	set(v): size = v; _request_rebuild()
## Vertices per side. Higher = smoother hills, heavier mesh. 64-128 is plenty.
@export_range(8, 200, 1) var resolution: int = 64:
	set(v): resolution = v; _request_rebuild()
## How tall the hills get.
@export var hill_height: float = 4.0:
	set(v): hill_height = v; _request_rebuild()
## Fraction of the border that fades down to edge_height (0 = no fade).
## Use it to sink the rim into surrounding geometry or make an island.
@export_range(0.0, 0.5, 0.01) var edge_falloff: float = 0.15:
	set(v): edge_falloff = v; _request_rebuild()
## Height the faded border settles at.
@export var edge_height: float = 0.0:
	set(v): edge_height = v; _request_rebuild()
## TRAVERSABILITY GUARANTEE: no slope anywhere exceeds this angle, so the
## whole terrain is walkable (Godot's default walk limit is 45deg). Peaks
## that would be steeper get shaved down. 0 = off (raw noise).
@export_range(0.0, 60.0, 1.0) var max_slope_degrees: float = 38.0:
	set(v): max_slope_degrees = v; _request_rebuild()

@export_group("Noise")
## Reroll for different hills.
@export var noise_seed: int = 7:
	set(v): noise_seed = v; _request_rebuild()
## Size of the hills: small = few big rolling mounds, large = busy bumps.
@export_range(0.005, 0.2, 0.001) var hill_frequency: float = 0.03:
	set(v): hill_frequency = v; _request_rebuild()
## Extra layers of finer detail on top of the base hills.
@export_range(1, 6, 1) var detail_octaves: int = 3:
	set(v): detail_octaves = v; _request_rebuild()

@export_group("Colors")
@export var grass_color: Color = Color(0.36, 0.55, 0.25):
	set(v): grass_color = v; _request_rebuild()
@export var rock_color: Color = Color(0.45, 0.42, 0.4):
	set(v): rock_color = v; _request_rebuild()
@export var dirt_color: Color = Color(0.5, 0.4, 0.28):
	set(v): dirt_color = v; _request_rebuild()
## How steep a slope has to be before it turns to rock (0-1, ~0.5 = 45deg).
@export_range(0.1, 1.0, 0.05) var rock_steepness: float = 0.55:
	set(v): rock_steepness = v; _request_rebuild()
@export var sand_color: Color = Color(0.82, 0.72, 0.5):
	set(v): sand_color = v; _request_rebuild()
## TERRAIN RULE: ground within this many meters of a touching WaterZone
## is sand colored (beach band). 0 disables.
@export var sand_distance: float = 30.0:
	set(v): sand_distance = maxf(v, 0.0); _request_rebuild()
@export var snow_color: Color = Color(0.93, 0.95, 0.97):
	set(v): snow_color = v; _request_rebuild()
## TERRAIN RULE: ground above this height (meters above the terrain node)
## turns white like snow, blending in over snow_blend meters. Painted
## mountains poke into it automatically. 0 disables.
@export var snow_height: float = 25.0:
	set(v): snow_height = v; _request_rebuild()
## Meters over which grass/rock fades into full snow above snow_height.
@export var snow_blend: float = 8.0:
	set(v): snow_blend = maxf(v, 0.1); _request_rebuild()

@export_group("Painting (editor)")
## PAINT MODE: with this ON and the Terrain selected, left-click in the 3D
## viewport to raise the ground under the cursor. Hold Shift to lower it.
## Drag to keep sculpting. Painted height is saved into the scene.
@export var paint_mode: bool = false
## Brush radius in meters.
@export_range(1.0, 100.0, 0.5, "or_greater") var brush_radius: float = 8.0
## Sculpt speed: meters of height added per second while the mouse is held.
@export var brush_strength: float = 8.0
## Tick to erase ALL painted height (back to pure noise terrain).
@export var clear_painted: bool = false:
	set(_v):
		clear_painted = false
		paint_data.fill(0.0)
		_request_rebuild()
## Painted height layer (meters per vertex). Managed by the brush - hands off.
@export_storage var paint_data: PackedFloat32Array = PackedFloat32Array()
@export_storage var paint_res: int = 0

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _rebuild_queued := false
var _heights: PackedFloat32Array = []   # (resolution+1)^2 grid, row-major
var _path_mask: PackedFloat32Array = []  # 0-1 per vertex: path color strength
var _path_col: PackedColorArray = []     # per-vertex path surface color


func _ready():
	# Terrain lips/cliffs are ledge-grabbable
	add_to_group("LedgeGrabbable")
	# Deferred so WaterZones are in the tree before the first sand-band pass
	call_deferred("_rebuild")


func _request_rebuild():
	# Coalesce a burst of Inspector changes into one rebuild
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild():
	_rebuild_queued = false
	if not is_inside_tree():
		return
	var n := resolution
	var step := Vector2(size.x / n, size.y / n)
	var half := size * 0.5
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = hill_frequency
	noise.fractal_octaves = detail_octaves
	
	# Collect flatten pads (any FlattenPad children)
	var pads: Array = []
	for c in get_children():
		if c is FlattenPad:
			pads.append(c)
	
	# --- Height grid ------------------------------------------------------
	var count := (n + 1) * (n + 1)
	_heights.resize(count)
	_ensure_paint_grid()
	for iz in range(n + 1):
		for ix in range(n + 1):
			var x := -half.x + ix * step.x
			var z := -half.y + iz * step.y
			var h := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * hill_height
			# Border falloff
			if edge_falloff > 0.0:
				var fx = minf(ix, n - ix) / float(n)
				var fz = minf(iz, n - iz) / float(n)
				var f = clampf(minf(fx, fz) / edge_falloff, 0.0, 1.0)
				h = lerpf(edge_height, h, smoothstep(0.0, 1.0, f))
			_heights[iz * (n + 1) + ix] = h
	
	# Walkability clamp: shave any slope steeper than max_slope_degrees.
	# NOISE ONLY - the clamp runs before painted height is added, so
	# hand-sculpted mountains can be arbitrarily tall/steep (great for
	# walling off areas). The slope guarantee is a suggestion, not a law.
	if max_slope_degrees > 0.0:
		_apply_slope_limit(step)
	
	# Painted (sculpted) height stacks on top, uncapped
	for i in range(count):
		_heights[i] += paint_data[i]
	
	# MOUNTAIN RULE: grow walkable flanks around painted peaks where
	# possible (raises surrounding ground to max_slope_degrees cones);
	# where blocked, the peak stays steep/pointy.
	if max_slope_degrees > 0.0:
		_grow_walkable_flanks(step)
	
	# Flatten pads pull the ground to their own height (after the clamp so
	# pads stay perfectly flat)
	for iz in range(n + 1):
		for ix in range(n + 1):
			var x := -half.x + ix * step.x
			var z := -half.y + iz * step.y
			var h := _heights[iz * (n + 1) + ix]
			for pad in pads:
				var d = Vector2(x - pad.position.x, z - pad.position.z).length()
				if d < pad.radius + pad.blend:
					var t = 1.0 - smoothstep(pad.radius, pad.radius + pad.blend, d)
					h = lerpf(h, pad.position.y, t)
			_heights[iz * (n + 1) + ix] = h
	
	# TerrainPath children carve flat walkable roads along their curves
	_path_mask.resize(count); _path_mask.fill(0.0)
	_path_col.resize(count)
	for c in get_children():
		if c is TerrainPath and c.curve and c.curve.point_count >= 2:
			_apply_path(c, n, step, half)
	
	# Beach sand band: distance (meters) from each vertex to the SHORELINE -
	# the nearest point where this terrain actually dips under a WaterZone's
	# surface. Interior ground that never touches water stays green even if
	# a huge water rectangle surrounds the whole island.
	var sand_dist := PackedFloat32Array()
	if sand_distance > 0.0:
		sand_dist = _shoreline_distance_field(n, step, half)
	
	# --- Mesh with slope-based vertex colors ------------------------------
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(n + 1):
		for ix in range(n + 1):
			var x := -half.x + ix * step.x
			var z := -half.y + iz * step.y
			var h := _heights[iz * (n + 1) + ix]
			# Steepness from neighbors (central difference)
			var hl := _grid_h(ix - 1, iz); var hr := _grid_h(ix + 1, iz)
			var hd := _grid_h(ix, iz - 1); var hu := _grid_h(ix, iz + 1)
			var slope = Vector2((hr - hl) / (2.0 * step.x), (hu - hd) / (2.0 * step.y)).length()
			var steep = clampf(slope / rock_steepness, 0.0, 1.0)
			var col: Color = grass_color.lerp(rock_color, smoothstep(0.4, 1.0, steep))
			# Low ground gets a dirt tint, plus subtle noise variation
			col = col.lerp(dirt_color, clampf(1.0 - h / maxf(hill_height * 0.35, 0.01), 0.0, 0.6) * 0.35)
			col = col.darkened((noise.get_noise_2d(x * 7.0, z * 7.0)) * 0.06)
			# TERRAIN RULE: sand band near touching water (beach). Vertices
			# within sand_distance meters of the shoreline go sand colored,
			# blending back into grass over the last few meters.
			if not sand_dist.is_empty():
				var wd := sand_dist[iz * (n + 1) + ix]
				if wd < sand_distance:
					var sand_t := 1.0 - smoothstep(sand_distance * 0.85, sand_distance, wd)
					var sc := sand_color.darkened((noise.get_noise_2d(x * 9.0, z * 9.0)) * 0.05)
					col = col.lerp(sc, sand_t)
			# TERRAIN RULE: snow caps. High ground fades to white - painted
			# mountains reach into the snow line automatically. Subtle noise
			# breakup keeps the transition organic instead of a hard ring.
			if snow_height > 0.0 and h > snow_height - snow_blend:
				var snow_t := smoothstep(snow_height - snow_blend, snow_height, h + noise.get_noise_2d(x * 3.0, z * 3.0) * snow_blend * 0.5)
				var snow_c := snow_color.darkened((noise.get_noise_2d(x * 11.0, z * 11.0)) * 0.04)
				col = col.lerp(snow_c, snow_t)
			# Paths paint their own surface color
			var pi := iz * (n + 1) + ix
			if _path_mask[pi] > 0.0:
				col = col.lerp(_path_col[pi], _path_mask[pi])
			st.set_color(col)
			st.set_uv(Vector2(ix / float(n), iz / float(n)))
			st.add_vertex(Vector3(x, h, z))
	for iz in range(n):
		for ix in range(n):
			var a := iz * (n + 1) + ix
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			# Godot front faces wind CLOCKWISE - CCW here made the whole
			# ground render as backfaces (invisible from above)
			st.add_index(a); st.add_index(b); st.add_index(d)
			st.add_index(a); st.add_index(d); st.add_index(c)
	st.generate_normals()
	var mesh := st.commit()
	
	# Skirt so you never see under the world at the borders
	mesh = _add_skirt(mesh, n, step, half)
	
	if _mesh_instance == null or not is_instance_valid(_mesh_instance):
		_mesh_instance = MeshInstance3D.new()
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # Visible from every angle, always
	_mesh_instance.material_override = mat
	
	# --- Collision: HeightMapShape3D, NOT a trimesh -----------------------
	# Heightmaps always depenetrate UPWARD, so a player placed touching or
	# slightly inside the ground pops onto the surface and walks freely.
	# (Trimesh collision wedges anything that starts intersecting it.)
	if _collision == null or not is_instance_valid(_collision):
		_collision = CollisionShape3D.new()
		add_child(_collision)
	# HeightMapShape3D cells are fixed at 1 unit, so resample the surface
	# at 1m spacing (bilinear) instead of scaling the shape (non-uniform
	# collision scaling is unreliable).
	# HeightMapShape3D cells are fixed at 1 unit and scaling collision
	# shapes is unreliable, so resample the surface at exact 1m spacing
	# (bilinear). The shape may overhang the visual edge by <1m; heights
	# clamp to the border value there.
	var cw := int(ceilf(size.x)) + 1
	var cd := int(ceilf(size.y)) + 1
	var cdata := PackedFloat32Array()
	cdata.resize(cw * cd)
	for cz in range(cd):
		for cx in range(cw):
			var lx = cx - (cw - 1) * 0.5
			var lz = cz - (cd - 1) * 0.5
			cdata[cz * cw + cx] = _sample_local_height(lx, lz)
	var hshape := HeightMapShape3D.new()
	hshape.map_width = cw
	hshape.map_depth = cd
	hshape.map_data = cdata
	_collision.shape = hshape
	_collision.position = Vector3.ZERO


func paint_at(world_pos: Vector3, delta_height: float) -> void:
	"""Raise (negative = lower) the ground in a smooth bump of brush_radius
	meters centered on world_pos. Used by the Terrain Painter editor plugin,
	but safe to call from gameplay scripts too (explosions, dig spots...)."""
	_ensure_paint_grid()
	var n := resolution
	var step := Vector2(size.x / n, size.y / n)
	var local := to_local(world_pos)
	var cx := (local.x + size.x * 0.5) / step.x
	var cz := (local.z + size.y * 0.5) / step.y
	var rx := int(ceilf(brush_radius / step.x)) + 1
	var rz := int(ceilf(brush_radius / step.y)) + 1
	var touched := false
	for iz in range(maxi(int(cz) - rz, 0), mini(int(cz) + rz, n) + 1):
		for ix in range(maxi(int(cx) - rx, 0), mini(int(cx) + rx, n) + 1):
			var d := Vector2((ix - cx) * step.x, (iz - cz) * step.y).length()
			if d < brush_radius:
				# Cosine falloff: soft dome, no hard brush edge
				var t := 0.5 + 0.5 * cos(PI * d / brush_radius)
				paint_data[iz * (n + 1) + ix] += delta_height * t
				touched = true
	if touched:
		_request_rebuild()


func _ensure_paint_grid() -> void:
	"""Keep the paint layer sized to the current resolution, resampling the
	old sculpt bilinearly when resolution changes so nothing is lost."""
	var n := resolution
	var want := (n + 1) * (n + 1)
	if paint_res == n and paint_data.size() == want:
		return
	var old := paint_data
	var old_n := paint_res
	paint_data = PackedFloat32Array()
	paint_data.resize(want)
	if old_n > 0 and old.size() == (old_n + 1) * (old_n + 1):
		for iz in range(n + 1):
			for ix in range(n + 1):
				var fx := float(ix) / n * old_n
				var fz := float(iz) / n * old_n
				var ox := mini(int(fx), old_n - 1)
				var oz := mini(int(fz), old_n - 1)
				var tx := fx - ox
				var tz := fz - oz
				var w1 := old_n + 1
				paint_data[iz * (n + 1) + ix] = lerpf(
					lerpf(old[oz * w1 + ox], old[oz * w1 + ox + 1], tx),
					lerpf(old[(oz + 1) * w1 + ox], old[(oz + 1) * w1 + ox + 1], tx), tz)
	paint_res = n


func _grow_walkable_flanks(step: Vector2) -> void:
	"""Slope-limited dilation from painted-up vertices: ground around a
	sculpted peak is RAISED (never lowered) until the flank meets the peak
	at max_slope_degrees - a wide, walkable mountain by default. Vertices
	that must not move are pinned (terrain border band, FlattenPads,
	TerrainPaths): where the flank hits a pin or the terrain edge it simply
	stops, leaving that side steep - the silent 'pointy mode'. Carved pits
	(negative paint) are never filled in: propagation only sources from
	raised vertices."""
	var n := resolution
	var w1 := n + 1
	var count := w1 * w1
	var slope := tan(deg_to_rad(max_slope_degrees))
	var dx := slope * step.x
	var dz := slope * step.y
	var dd := slope * Vector2(step.x, step.y).length()
	
	# Pinned vertices: never raised. Border band keeps island edges/beaches;
	# pads and paths were placed deliberately flat.
	var pinned := PackedByteArray()
	pinned.resize(count)
	var border := maxi(int(edge_falloff * n), 1) if edge_falloff > 0.0 else 0
	for iz in range(w1):
		for ix in range(w1):
			if ix < border or iz < border or ix > n - border or iz > n - border:
				pinned[iz * w1 + ix] = 1
	for i in range(count):
		if _path_mask.size() == count and _path_mask[i] > 0.05:
			pinned[i] = 1
	var pads: Array = []
	for c in get_children():
		if c is FlattenPad:
			pads.append(c)
	if not pads.is_empty():
		var half := size * 0.5
		for iz in range(w1):
			for ix in range(w1):
				var x := -half.x + ix * step.x
				var z := -half.y + iz * step.y
				for pad in pads:
					if Vector2(x - pad.position.x, z - pad.position.z).length() < pad.radius + pad.blend:
						pinned[iz * w1 + ix] = 1
						break
	
	# Cone field seeded ONLY from painted-up vertices, spread by chamfer
	# sweeps (forward + backward twice = converged for this kernel).
	var f := PackedFloat32Array()
	f.resize(count)
	var neg := -1e9
	for i in range(count):
		f[i] = _heights[i] if (paint_data.size() == count and paint_data[i] > 0.01) else neg
	for _round in range(2):
		for iz in range(w1):
			for ix in range(w1):
				var i := iz * w1 + ix
				var v := f[i]
				if ix > 0: v = maxf(v, f[i - 1] - dx)
				if iz > 0: v = maxf(v, f[i - w1] - dz)
				if ix > 0 and iz > 0: v = maxf(v, f[i - w1 - 1] - dd)
				if ix < n and iz > 0: v = maxf(v, f[i - w1 + 1] - dd)
				f[i] = v
		for iz in range(n, -1, -1):
			for ix in range(n, -1, -1):
				var i := iz * w1 + ix
				var v := f[i]
				if ix < n: v = maxf(v, f[i + 1] - dx)
				if iz < n: v = maxf(v, f[i + w1] - dz)
				if ix < n and iz < n: v = maxf(v, f[i + w1 + 1] - dd)
				if ix > 0 and iz < n: v = maxf(v, f[i + w1 - 1] - dd)
				f[i] = v
	
	# Raise unpinned ground into the walkable cones (never lower anything)
	for i in range(count):
		if pinned[i] == 0 and f[i] > _heights[i]:
			_heights[i] = f[i]


func _apply_slope_limit(step: Vector2) -> void:
	"""Iteratively shave NOISE peaks until no neighbor pair exceeds the max
	slope. Only ever LOWERS vertices, so pads/valleys keep their floors.
	Runs before painted height is added - sculpted terrain is exempt."""
	var n := resolution
	var max_dh := tan(deg_to_rad(max_slope_degrees)) * minf(step.x, step.y)
	for _pass in range(24):
		var changed := false
		for iz in range(n + 1):
			for ix in range(n + 1):
				var i := iz * (n + 1) + ix
				var h := _heights[i]
				# Against the 2 forward neighbors (each pair checked once)
				if ix < n:
					var j := i + 1
					var hj := _heights[j]
					if h - hj > max_dh:
						_heights[i] = hj + max_dh; h = _heights[i]; changed = true
					elif hj - h > max_dh:
						_heights[j] = h + max_dh; changed = true
				if iz < n:
					var j2 := i + (n + 1)
					var hj2 := _heights[j2]
					if h - hj2 > max_dh:
						_heights[i] = hj2 + max_dh; changed = true
					elif hj2 - h > max_dh:
						_heights[j2] = h + max_dh; changed = true
		if not changed:
			break


func _apply_path(path: TerrainPath, n: int, step: Vector2, half: Vector2) -> void:
	"""Carve a flat walkable strip along the path's curve: terrain height is
	pulled to the curve's height within width/2, blending back into the hills
	over blend meters. Also paints the strip with the path's color."""
	var count := (n + 1) * (n + 1)
	var pdist := PackedFloat32Array(); pdist.resize(count); pdist.fill(1e9)
	var py := PackedFloat32Array(); py.resize(count)
	var r: float = path.width * 0.5 + path.blend
	var rx := int(ceilf(r / step.x)) + 1
	var rz := int(ceilf(r / step.y)) + 1
	var xform: Transform3D = path.transform
	# Nearest-sample distance per vertex (dense baked points ~= true distance)
	for bp in path.curve.get_baked_points():
		var p: Vector3 = xform * bp   # Terrain-local
		var cx := int((p.x + half.x) / step.x)
		var cz := int((p.z + half.y) / step.y)
		for iz in range(maxi(cz - rz, 0), mini(cz + rz, n) + 1):
			for ix in range(maxi(cx - rx, 0), mini(cx + rx, n) + 1):
				var i := iz * (n + 1) + ix
				var vx := -half.x + ix * step.x
				var vz := -half.y + iz * step.y
				var d := Vector2(vx - p.x, vz - p.z).length()
				if d < pdist[i]:
					pdist[i] = d
					py[i] = p.y
	# Apply flattening + color mask
	var w2: float = path.width * 0.5
	for i in range(count):
		if pdist[i] >= r:
			continue
		var t := 1.0 - smoothstep(w2, r, pdist[i])
		_heights[i] = lerpf(_heights[i], py[i], t)
		var cmask := 1.0 - smoothstep(w2 * 0.85, w2 + path.blend * 0.3, pdist[i])
		if cmask > _path_mask[i]:
			_path_mask[i] = cmask
			_path_col[i] = path.path_color


func _shoreline_distance_field(n: int, step: Vector2, half: Vector2) -> PackedFloat32Array:
	"""Per-vertex meters to the nearest SHORELINE vertex: a grid point that
	sits under a WaterZone's surface (horizontally inside its rectangle AND
	at/below its surface height). Empty array when no terrain touches water."""
	var waters: Array = []
	if is_inside_tree():
		for w in get_tree().get_nodes_in_group("WaterZone"):
			if w is Area3D and "water_size" in w:
				waters.append(w)
	if waters.is_empty():
		return PackedFloat32Array()
	
	var count := (n + 1) * (n + 1)
	var field := PackedFloat32Array()
	field.resize(count)
	var big := 1e9
	var any_wet := false
	for iz in range(n + 1):
		for ix in range(n + 1):
			var x := -half.x + ix * step.x
			var z := -half.y + iz * step.y
			var wp := to_global(Vector3(x, _heights[iz * (n + 1) + ix], z))
			var wet := false
			for w in waters:
				var local: Vector3 = w.to_local(wp)
				if absf(local.x) <= w.water_size.x * 0.5 \
						and absf(local.z) <= w.water_size.y * 0.5 \
						and wp.y <= w.global_position.y + 0.15:
					wet = true
					break
			field[iz * (n + 1) + ix] = 0.0 if wet else big
			if wet:
				any_wet = true
	if not any_wet:
		return PackedFloat32Array()
	
	# Two-pass chamfer distance transform (with diagonals), in meters
	var d1x := step.x
	var d1z := step.y
	var d2 := Vector2(step.x, step.y).length()
	var w1 := n + 1
	for iz in range(n + 1):
		for ix in range(n + 1):
			var i := iz * w1 + ix
			var d := field[i]
			if ix > 0: d = minf(d, field[i - 1] + d1x)
			if iz > 0: d = minf(d, field[i - w1] + d1z)
			if ix > 0 and iz > 0: d = minf(d, field[i - w1 - 1] + d2)
			if ix < n and iz > 0: d = minf(d, field[i - w1 + 1] + d2)
			field[i] = d
	for iz in range(n, -1, -1):
		for ix in range(n, -1, -1):
			var i := iz * w1 + ix
			var d := field[i]
			if ix < n: d = minf(d, field[i + 1] + d1x)
			if iz < n: d = minf(d, field[i + w1] + d1z)
			if ix < n and iz < n: d = minf(d, field[i + w1 + 1] + d2)
			if ix > 0 and iz < n: d = minf(d, field[i + w1 - 1] + d2)
			field[i] = d
	return field


func _sample_local_height(lx: float, lz: float) -> float:
	"""Bilinear height at a local XZ from the mesh grid."""
	var n := resolution
	var fx = clampf((lx + size.x * 0.5) / size.x, 0.0, 1.0) * n
	var fz = clampf((lz + size.y * 0.5) / size.y, 0.0, 1.0) * n
	var ix := int(fx); var iz := int(fz)
	var tx: float = fx - ix
	var tz: float = fz - iz
	return lerpf(
		lerpf(_grid_h(ix, iz), _grid_h(ix + 1, iz), tx),
		lerpf(_grid_h(ix, iz + 1), _grid_h(ix + 1, iz + 1), tx), tz)


func _grid_h(ix: int, iz: int) -> float:
	var n := resolution
	return _heights[clampi(iz, 0, n) * (n + 1) + clampi(ix, 0, n)]


func _add_skirt(mesh: ArrayMesh, n: int, step: Vector2, half: Vector2) -> ArrayMesh:
	var bottom := edge_height - 4.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(dirt_color.darkened(0.35))
	var edges = [
		[Vector2i(0, 0), Vector2i(1, 0), 0],       # north row (iz=0), step +x
		[Vector2i(0, n), Vector2i(1, 0), 1],       # south row
		[Vector2i(0, 0), Vector2i(0, 1), 1],       # west column, step +z
		[Vector2i(n, 0), Vector2i(0, 1), 0],       # east column
	]
	for e in edges:
		for i in range(n):
			var g0: Vector2i = e[0] + e[1] * i
			var g1: Vector2i = e[0] + e[1] * (i + 1)
			var p0 := Vector3(-half.x + g0.x * step.x, _grid_h(g0.x, g0.y), -half.y + g0.y * step.y)
			var p1 := Vector3(-half.x + g1.x * step.x, _grid_h(g1.x, g1.y), -half.y + g1.y * step.y)
			var b0 := Vector3(p0.x, bottom, p0.z)
			var b1 := Vector3(p1.x, bottom, p1.z)
			# (clockwise = front in Godot; e[2] picks the outward side)
			if e[2] == 0:
				st.add_vertex(p0); st.add_vertex(b0); st.add_vertex(p1)
				st.add_vertex(p1); st.add_vertex(b0); st.add_vertex(b1)
			else:
				st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(b0)
				st.add_vertex(p1); st.add_vertex(b1); st.add_vertex(b0)
	st.generate_normals()
	return st.commit(mesh)   # Append as second surface


func get_height(world_pos: Vector3) -> float:
	"""Terrain height (world Y) at any world XZ - handy for placing props."""
	var local = to_local(world_pos)
	return to_global(Vector3(0, _sample_local_height(local.x, local.z), 0)).y
