@tool
extends StaticBody3D
class_name Platform
## LEVEL KIT PLATFORM - one node, any common platform shape, sized by
## dragging. Select it and pull the orange handles in the 3D viewport
## (width / depth / thickness), or type numbers in the Inspector.
##
## The node origin is the CENTRE OF THE TOP SURFACE, so "position.y" is
## literally the height Inke stands at. Snapping, stacking and the jump
## tools all rely on that.
##
## Shapes: BOX slab, ROUND pillar top, RAMP (walkable slope), STAIRS,
## ARCH bridge. Everything is ledge-grabbable and generated at load time
## (scene files stay tiny).

enum Shape { BOX, ROUND, RAMP, STAIRS, ARCH }
enum Look { STONE, WOOD, METAL, GRASS, SAND, SNOW, CRYSTAL, CUSTOM }

@export var shape: Shape = Shape.BOX:
	set(v): shape = v; _queue()
## Top surface size: X = width, Y = thickness (how far it extends DOWN
## from the top), Z = depth. For RAMP/STAIRS, Z is the run length.
@export var size: Vector3 = Vector3(6, 1, 6):
	set(v): size = Vector3(maxf(v.x, 0.1), maxf(v.y, 0.05), maxf(v.z, 0.1)); _queue()
## RAMP/STAIRS: how much higher the far (-Z) end is than the near end.
@export var rise: float = 3.0:
	set(v): rise = v; _queue()
## STAIRS: step count. ARCH: curve segments.
@export_range(2, 64, 1) var segments: int = 8:
	set(v): segments = v; _queue()
## ROUND: sides of the pillar (more = smoother).
@export_range(6, 64, 1) var round_sides: int = 24:
	set(v): round_sides = v; _queue()
## Extend the body downward to this depth below the top (a pillar to the
## ground). 0 = just the slab thickness.
@export var pillar_depth: float = 0.0:
	set(v): pillar_depth = maxf(v, 0.0); _queue()

@export_group("Look")
@export var look: Look = Look.STONE:
	set(v): look = v; _queue()
## Used when look = CUSTOM, and as a tint for the others.
@export var color: Color = Color(1, 1, 1):
	set(v): color = v; _queue()
## Draw a thin contrasting trim along the top edge so ledges read clearly.
@export var edge_trim: bool = true:
	set(v): edge_trim = v; _queue()

@export_group("Gameplay")
## Inke can ledge-grab this platform's edges.
@export var ledge_grabbable: bool = true:
	set(v): ledge_grabbable = v; _update_groups()

const LOOK_COLORS := {
	Look.STONE: Color(0.58, 0.56, 0.54),
	Look.WOOD: Color(0.55, 0.38, 0.22),
	Look.METAL: Color(0.52, 0.58, 0.64),
	Look.GRASS: Color(0.38, 0.6, 0.28),
	Look.SAND: Color(0.86, 0.76, 0.52),
	Look.SNOW: Color(0.93, 0.95, 0.98),
	Look.CRYSTAL: Color(0.45, 0.75, 1.0),
}

var _mesh: MeshInstance3D
var _col: CollisionShape3D
var _queued := false


func _ready() -> void:
	_update_groups()
	_rebuild()


func _update_groups() -> void:
	if ledge_grabbable:
		add_to_group("LedgeGrabbable")
	elif is_in_group("LedgeGrabbable"):
		remove_from_group("LedgeGrabbable")
	add_to_group("LevelKitPlatform")


func _queue() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


## World-space top surface height (what Inke stands on).
func top_y() -> float:
	return global_position.y


## Local-space axis-aligned box of the whole body (for snapping/stacking).
func local_bounds() -> AABB:
	var depth := size.y + pillar_depth
	match shape:
		Shape.RAMP, Shape.STAIRS:
			var lo := minf(0.0, rise)
			var hi := maxf(0.0, rise)
			return AABB(Vector3(-size.x * 0.5, lo - depth, -size.z * 0.5), Vector3(size.x, hi - lo + depth, size.z))
		_:
			return AABB(Vector3(-size.x * 0.5, -depth, -size.z * 0.5), Vector3(size.x, depth, size.z))


func base_color() -> Color:
	var c: Color = color if look == Look.CUSTOM else LOOK_COLORS.get(look, Color.WHITE) * color
	c.a = 1.0
	return c


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	if _mesh == null or not is_instance_valid(_mesh):
		_mesh = MeshInstance3D.new()
		_mesh.name = "_Mesh"
		add_child(_mesh)
	if _col == null or not is_instance_valid(_col):
		_col = CollisionShape3D.new()
		_col.name = "_Collision"
		add_child(_col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := base_color()
	var trim := c.darkened(0.35) if look != Look.SNOW else c.darkened(0.15)
	var depth := size.y + pillar_depth
	match shape:
		Shape.BOX:
			_box(st, Vector3(0, -depth * 0.5, 0), Vector3(size.x, depth, size.z), c)
			if edge_trim:
				_trim_box(st, size.x, size.z, 0.0, trim)
		Shape.ROUND:
			_cylinder(st, size.x * 0.5, size.z * 0.5, 0.0, -depth, c)
			if edge_trim:
				_ring(st, size.x * 0.5, size.z * 0.5, 0.0, trim)
		Shape.RAMP:
			_ramp(st, c)
		Shape.STAIRS:
			_stairs(st, c)
		Shape.ARCH:
			_arch(st, c)
	st.generate_normals()
	var mesh := st.commit()
	_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.35 if look in [Look.METAL, Look.CRYSTAL] else 0.9
	mat.metallic = 0.5 if look == Look.METAL else 0.0
	_mesh.material_override = mat
	# Collision: convex for simple solids, exact trimesh for stairs/arches
	if shape in [Shape.STAIRS, Shape.ARCH]:
		_col.shape = mesh.create_trimesh_shape()
	else:
		_col.shape = mesh.create_convex_shape(true, false)


# --- Geometry helpers (clockwise winding = front face in Godot) ------------

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


func _box(st: SurfaceTool, center: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	_quad(st, p[4], p[5], p[6], p[7], col)            # top
	var side := col.darkened(0.12)
	_quad(st, p[3], p[2], p[1], p[0], side.darkened(0.2))  # bottom
	_quad(st, p[7], p[6], p[2], p[3], side)           # +Z
	_quad(st, p[5], p[4], p[0], p[1], side)           # -Z
	_quad(st, p[6], p[5], p[1], p[2], side)           # +X
	_quad(st, p[4], p[7], p[3], p[0], side)           # -X


func _trim_box(st: SurfaceTool, w: float, d: float, y: float, col: Color) -> void:
	var t := 0.12
	_box(st, Vector3(0, y - t * 0.5, d * 0.5 - t * 0.5), Vector3(w + 0.02, t + 0.02, t), col)
	_box(st, Vector3(0, y - t * 0.5, -d * 0.5 + t * 0.5), Vector3(w + 0.02, t + 0.02, t), col)
	_box(st, Vector3(w * 0.5 - t * 0.5, y - t * 0.5, 0), Vector3(t, t + 0.02, d + 0.02), col)
	_box(st, Vector3(-w * 0.5 + t * 0.5, y - t * 0.5, 0), Vector3(t, t + 0.02, d + 0.02), col)


func _cylinder(st: SurfaceTool, rx: float, rz: float, top: float, bottom: float, col: Color) -> void:
	var n := round_sides
	var side := col.darkened(0.12)
	for i in range(n):
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * rx, 0, sin(a0) * rz)
		var p1 := Vector3(cos(a1) * rx, 0, sin(a1) * rz)
		# top fan
		st.set_color(col)
		st.add_vertex(Vector3(0, top, 0)); st.add_vertex(p1 + Vector3(0, top, 0)); st.add_vertex(p0 + Vector3(0, top, 0))
		# bottom fan
		st.set_color(side.darkened(0.2))
		st.add_vertex(Vector3(0, bottom, 0)); st.add_vertex(p0 + Vector3(0, bottom, 0)); st.add_vertex(p1 + Vector3(0, bottom, 0))
		# side
		_quad(st, p0 + Vector3(0, top, 0), p1 + Vector3(0, top, 0), p1 + Vector3(0, bottom, 0), p0 + Vector3(0, bottom, 0), side)


func _ring(st: SurfaceTool, rx: float, rz: float, y: float, col: Color) -> void:
	var n := round_sides
	var t := 0.12
	for i in range(n):
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var o0 := Vector3(cos(a0) * (rx + 0.01), y + 0.01, sin(a0) * (rz + 0.01))
		var o1 := Vector3(cos(a1) * (rx + 0.01), y + 0.01, sin(a1) * (rz + 0.01))
		var i0 := Vector3(cos(a0) * (rx - t), y + 0.01, sin(a0) * (rz - t))
		var i1 := Vector3(cos(a1) * (rx - t), y + 0.01, sin(a1) * (rz - t))
		_quad(st, i0, i1, o1, o0, col)
		_quad(st, o0, o1, o1 - Vector3(0, t, 0), o0 - Vector3(0, t, 0), col)


func _ramp(st: SurfaceTool, col: Color) -> void:
	# Near edge (+Z) at y=0, far edge (-Z) at y=rise. Solid wedge with a
	# flat bottom `size.y + pillar_depth` under the LOWER end.
	var w := size.x * 0.5
	var d := size.z * 0.5
	var bottom := minf(0.0, rise) - size.y - pillar_depth
	var nl := Vector3(-w, 0, d); var nr := Vector3(w, 0, d)
	var fl := Vector3(-w, rise, -d); var fr := Vector3(w, rise, -d)
	var bnl := Vector3(-w, bottom, d); var bnr := Vector3(w, bottom, d)
	var bfl := Vector3(-w, bottom, -d); var bfr := Vector3(w, bottom, -d)
	var side := col.darkened(0.12)
	_quad(st, fl, fr, nr, nl, col)                      # slope surface
	_quad(st, bnl, bnr, bfr, bfl, side.darkened(0.2))   # bottom
	_quad(st, nl, nr, bnr, bnl, side)                   # near face
	_quad(st, fr, fl, bfl, bfr, side)                   # far face
	_quad(st, nr, fr, bfr, bnr, side)                   # +X side
	_quad(st, fl, nl, bnl, bfl, side)                   # -X side


func _stairs(st: SurfaceTool, col: Color) -> void:
	# `segments` steps climbing from the near (+Z) edge to the far (-Z) edge.
	var n := segments
	var run := size.z / n
	var step_h := rise / n
	var bottom := minf(0.0, rise) - size.y - pillar_depth
	for i in range(n):
		var z0 := size.z * 0.5 - run * i
		var top := step_h * (i + 1) if rise >= 0.0 else step_h * i
		var h := top - bottom
		var c := col if i % 2 == 0 else col.darkened(0.06)
		_box(st, Vector3(0, bottom + h * 0.5, z0 - run * 0.5), Vector3(size.x, h, run), c)


func _arch(st: SurfaceTool, col: Color) -> void:
	# Bridge whose deck bows UP by `rise` at the middle; thickness size.y.
	var n := maxi(segments, 4)
	var w := size.x * 0.5
	var side := col.darkened(0.12)
	for i in range(n):
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var z0 := lerpf(size.z * 0.5, -size.z * 0.5, t0)
		var z1 := lerpf(size.z * 0.5, -size.z * 0.5, t1)
		var y0 := sin(t0 * PI) * rise
		var y1 := sin(t1 * PI) * rise
		var a := Vector3(-w, y0, z0); var b := Vector3(w, y0, z0)
		var c := Vector3(w, y1, z1); var d := Vector3(-w, y1, z1)
		var dn := Vector3(0, -size.y, 0)
		_quad(st, d, c, b, a, col)                         # deck
		_quad(st, a + dn, b + dn, c + dn, d + dn, side.darkened(0.2))  # underside
		_quad(st, b, c, c + dn, b + dn, side)              # +X
		_quad(st, d, a, a + dn, d + dn, side)              # -X
		if i == 0:
			_quad(st, a, b, b + dn, a + dn, side)
		if i == n - 1:
			_quad(st, c, d, d + dn, c + dn, side)
