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

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _rebuild_queued := false
var _heights: PackedFloat32Array = []   # (resolution+1)^2 grid, row-major


func _ready():
	_rebuild()


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
	_heights.resize((n + 1) * (n + 1))
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
			# Flatten pads pull the ground to their own height
			for pad in pads:
				var d = Vector2(x - pad.position.x, z - pad.position.z).length()
				if d < pad.radius + pad.blend:
					var t = 1.0 - smoothstep(pad.radius, pad.radius + pad.blend, d)
					h = lerpf(h, pad.position.y, t)
			_heights[iz * (n + 1) + ix] = h
	
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
			st.set_color(col)
			st.set_uv(Vector2(ix / float(n), iz / float(n)))
			st.add_vertex(Vector3(x, h, z))
	for iz in range(n):
		for ix in range(n):
			var a := iz * (n + 1) + ix
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			st.add_index(a); st.add_index(d); st.add_index(b)
			st.add_index(a); st.add_index(c); st.add_index(d)
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
	_mesh_instance.material_override = mat
	
	# --- Exact collision --------------------------------------------------
	if _collision == null or not is_instance_valid(_collision):
		_collision = CollisionShape3D.new()
		add_child(_collision)
	_collision.shape = mesh.create_trimesh_shape()


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
			if e[2] == 0:
				st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(b0)
				st.add_vertex(p1); st.add_vertex(b1); st.add_vertex(b0)
			else:
				st.add_vertex(p0); st.add_vertex(b0); st.add_vertex(p1)
				st.add_vertex(p1); st.add_vertex(b0); st.add_vertex(b1)
	st.generate_normals()
	return st.commit(mesh)   # Append as second surface


func get_height(world_pos: Vector3) -> float:
	"""Terrain height (world Y) at any world XZ - handy for placing props."""
	var local = to_local(world_pos)
	var n := resolution
	var fx = clampf((local.x + size.x * 0.5) / size.x, 0.0, 1.0) * n
	var fz = clampf((local.z + size.y * 0.5) / size.y, 0.0, 1.0) * n
	var ix := int(fx); var iz := int(fz)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var h = lerpf(
		lerpf(_grid_h(ix, iz), _grid_h(ix + 1, iz), tx),
		lerpf(_grid_h(ix, iz + 1), _grid_h(ix + 1, iz + 1), tx), tz)
	return to_global(Vector3(0, h, 0)).y
