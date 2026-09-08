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
##      sand_distance meters (default 30) of the water automatically gets
##      sand coloring. No setup - it finds the water on its own.
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
	
	# Walkability clamp: shave any slope steeper than max_slope_degrees
	if max_slope_degrees > 0.0:
		_apply_slope_limit(step)
	
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
	
	# WaterZones bordering this terrain (for the beach sand band)
	var waters: Array = []
	if sand_distance > 0.0:
		for w in get_tree().get_nodes_in_group("WaterZone"):
			if w is Area3D and "water_size" in w:
				waters.append(w)
	
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
			# within sand_distance meters of a WaterZone go sand colored,
			# blending back into grass over the last few meters.
			if not waters.is_empty():
				var wd := _water_distance(to_global(Vector3(x, h, z)), waters)
				if wd < sand_distance:
					var sand_t := 1.0 - smoothstep(sand_distance * 0.85, sand_distance, wd)
					var sc := sand_color.darkened((noise.get_noise_2d(x * 9.0, z * 9.0)) * 0.05)
					col = col.lerp(sc, sand_t)
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


func _apply_slope_limit(step: Vector2) -> void:
	"""Iteratively shave peaks until no neighbor pair exceeds the max slope.
	Only ever LOWERS vertices, so pads/valleys keep their floors."""
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


func _water_distance(world_pos: Vector3, waters: Array) -> float:
	"""Horizontal meters from world_pos to the nearest WaterZone rectangle
	(0 when over the water). Ignores water whose surface is far below this
	point of terrain - a beach only forms where water actually touches."""
	var best := 1e9
	for w in waters:
		# Water more than ~8m below this ground point doesn't make a beach
		if world_pos.y - w.global_position.y > 8.0:
			continue
		var local: Vector3 = w.to_local(world_pos)
		var dx := maxf(absf(local.x) - w.water_size.x * 0.5, 0.0)
		var dz := maxf(absf(local.z) - w.water_size.y * 0.5, 0.0)
		best = minf(best, Vector2(dx, dz).length())
	return best


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
