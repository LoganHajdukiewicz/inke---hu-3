@tool
extends StaticBody3D
class_name LKProp
## Scenery prop built in code (no assets needed): rock, boulder, tree, pine,
## palm, bush, grass tuft, flowers, stump, log. Pick `kind`, change `seed`
## to reroll its shape. Painted by the Level Kit scatter brush, but you can
## place/edit them by hand too. Grass/flowers have no collision.

enum Kind { ROCK, BOULDER, TREE, PINE, PALM, BUSH, GRASS, FLOWERS, STUMP, LOG }

@export var kind: Kind = Kind.ROCK:
	set(v): kind = v; _queue()
@export var seed: int = 1:
	set(v): seed = v; _queue()
@export var tint: Color = Color(1, 1, 1):
	set(v): tint = v; _queue()

var _mesh: MeshInstance3D
var _col: CollisionShape3D
var _queued := false


func _ready() -> void:
	add_to_group("LKProp")
	_rebuild()


func _queue() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new(); _mesh.name = "_Mesh"; add_child(_mesh)
		_col = CollisionShape3D.new(); _col.name = "_Col"; add_child(_col)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + int(kind) * 104729
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shape: Shape3D = null
	match kind:
		Kind.ROCK:
			_blob(st, Vector3(0, 0.35, 0), Vector3(0.9, 0.6, 0.8), Color(0.5, 0.49, 0.47), rng, 0.25)
			shape = _sphere(0.6, Vector3(0, 0.35, 0))
		Kind.BOULDER:
			_blob(st, Vector3(0, 1.1, 0), Vector3(2.2, 1.6, 1.9), Color(0.46, 0.45, 0.44), rng, 0.3)
			shape = _sphere(1.6, Vector3(0, 1.1, 0))
		Kind.TREE:
			var h := rng.randf_range(3.0, 4.5)
			_cyl(st, Vector3.ZERO, h, 0.28, 0.18, Color(0.42, 0.28, 0.16))
			for i in range(3):
				var o := Vector3(rng.randf_range(-0.6, 0.6), h + rng.randf_range(-0.3, 0.6), rng.randf_range(-0.6, 0.6))
				_blob(st, o, Vector3.ONE * rng.randf_range(1.4, 2.0), Color(0.26, 0.5, 0.22).lerp(Color(0.38, 0.6, 0.25), rng.randf()), rng, 0.2)
			shape = _capsule(0.35, h, Vector3(0, h * 0.5, 0))
		Kind.PINE:
			var ph := rng.randf_range(4.0, 6.0)
			_cyl(st, Vector3.ZERO, ph * 0.4, 0.22, 0.16, Color(0.38, 0.25, 0.15))
			for i in range(3):
				var y := ph * (0.3 + i * 0.22)
				_cone(st, Vector3(0, y, 0), ph * 0.38, 1.6 - i * 0.4, Color(0.16, 0.38, 0.22).lerp(Color(0.22, 0.45, 0.26), i * 0.3))
			shape = _capsule(0.3, ph * 0.6, Vector3(0, ph * 0.3, 0))
		Kind.PALM:
			var segs := 7
			var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
			var p := Vector3.ZERO
			for i in range(segs):
				var q := p + Vector3(0, 0.7, 0) + lean * float(i)
				_cyl(st, p, 0.72, 0.2 - i * 0.012, 0.19 - i * 0.012, Color(0.55, 0.42, 0.28).darkened(0.08 * (i % 2)), q - p)
				p = q
			for i in range(6):
				var a := TAU * i / 6.0 + rng.randf() * 0.3
				_leaf(st, p, Vector3(cos(a), -0.35, sin(a)), 2.4, Color(0.3, 0.58, 0.22))
			shape = _capsule(0.25, p.y, Vector3(0, p.y * 0.5, 0))
		Kind.BUSH:
			for i in range(4):
				_blob(st, Vector3(rng.randf_range(-0.5, 0.5), 0.45, rng.randf_range(-0.5, 0.5)), Vector3.ONE * rng.randf_range(0.7, 1.0), Color(0.28, 0.52, 0.22).lerp(Color(0.34, 0.58, 0.26), rng.randf()), rng, 0.2)
			shape = _sphere(0.75, Vector3(0, 0.45, 0))
		Kind.GRASS:
			for i in range(6):
				var a := rng.randf() * TAU
				var o2 := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
				_blade(st, o2, a, rng.randf_range(0.35, 0.6), Color(0.35, 0.6, 0.25).lerp(Color(0.5, 0.7, 0.3), rng.randf()))
		Kind.FLOWERS:
			for i in range(5):
				var a := rng.randf() * TAU
				var o3 := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
				_blade(st, o3, a, 0.35, Color(0.35, 0.6, 0.25))
				var petal: Color = [Color(1, 0.35, 0.6), Color(1, 0.85, 0.25), Color(0.6, 0.5, 1), Color(1, 1, 1)][rng.randi() % 4]
				_blob(st, o3 + Vector3(0, 0.38, 0), Vector3.ONE * 0.13, petal, rng, 0.0)
		Kind.STUMP:
			_cyl(st, Vector3.ZERO, 0.6, 0.5, 0.45, Color(0.45, 0.3, 0.18))
			shape = _capsule(0.5, 0.6, Vector3(0, 0.3, 0))
		Kind.LOG:
			_cyl(st, Vector3(-1.2, 0.3, 0), 2.4, 0.3, 0.3, Color(0.45, 0.3, 0.18), Vector3(2.4, 0, 0))
			var bs := BoxShape3D.new(); bs.size = Vector3(2.4, 0.6, 0.6)
			shape = bs
			_col.position = Vector3(0, 0.3, 0)
	st.generate_normals()
	_mesh.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.roughness = 0.95
	if kind in [Kind.GRASS, Kind.FLOWERS, Kind.PALM]:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = m
	_col.shape = shape
	_col.disabled = shape == null
	if kind != Kind.LOG:
		if shape is SphereShape3D:
			_col.position = _sphere_off
		elif shape is CapsuleShape3D:
			_col.position = _caps_off


var _sphere_off := Vector3.ZERO
var _caps_off := Vector3.ZERO


func _sphere(r: float, off: Vector3) -> SphereShape3D:
	var s := SphereShape3D.new(); s.radius = r; _sphere_off = off; return s


func _capsule(r: float, h: float, off: Vector3) -> CapsuleShape3D:
	var c := CapsuleShape3D.new(); c.radius = r; c.height = maxf(h, r * 2.0 + 0.01); _caps_off = off; return c


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col); st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)


func _blob(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, rng: RandomNumberGenerator, jitter: float) -> void:
	# low-poly lumpy sphere (lat/long with radius noise)
	var rings := 5; var segs := 7
	var pts := []
	for i in range(rings + 1):
		var row := []
		var v := PI * i / rings
		for j in range(segs):
			var u := TAU * j / segs
			var r := 1.0 + (rng.randf_range(-jitter, jitter) if i > 0 and i < rings else 0.0)
			row.append(c + Vector3(sin(v) * cos(u) * s.x, cos(v) * s.y, sin(v) * sin(u) * s.z) * 0.5 * r)
		pts.append(row)
	for i in range(rings):
		for j in range(segs):
			var a: Vector3 = pts[i][j]; var b: Vector3 = pts[i][(j + 1) % segs]
			var c2: Vector3 = pts[i + 1][j]; var d: Vector3 = pts[i + 1][(j + 1) % segs]
			var shade := col.darkened(0.12 * float(i) / rings)
			_tri(st, a, b, d, shade); _tri(st, a, d, c2, shade)


func _cyl(st: SurfaceTool, base: Vector3, h: float, r0: float, r1: float, col: Color, axis := Vector3.ZERO) -> void:
	var up := axis if axis != Vector3.ZERO else Vector3(0, h, 0)
	var n := up.normalized()
	var t := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var b := n.cross(t)
	var segs := 7
	for j in range(segs):
		var a0 := TAU * j / segs; var a1 := TAU * (j + 1) / segs
		var d0 := t * cos(a0) + b * sin(a0); var d1 := t * cos(a1) + b * sin(a1)
		var p0 := base + d0 * r0; var p1 := base + d1 * r0
		var q0 := base + up + d0 * r1; var q1 := base + up + d1 * r1
		_tri(st, p0, q0, q1, col); _tri(st, p0, q1, p1, col)
		_tri(st, base + up, q1, q0, col.lightened(0.1))


func _cone(st: SurfaceTool, base: Vector3, h: float, r: float, col: Color) -> void:
	var segs := 8
	for j in range(segs):
		var a0 := TAU * j / segs; var a1 := TAU * (j + 1) / segs
		var p0 := base + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := base + Vector3(cos(a1), 0, sin(a1)) * r
		_tri(st, p0, base + Vector3(0, h, 0), p1, col)
		_tri(st, p0, p1, base, col.darkened(0.3))


func _leaf(st: SurfaceTool, root: Vector3, dir: Vector3, length: float, col: Color) -> void:
	var d := dir.normalized()
	var side := d.cross(Vector3.UP).normalized() * 0.35
	var mid := root + d * length * 0.5 + Vector3(0, 0.25, 0)
	var tip := root + d * length + Vector3(0, -0.4, 0)
	_tri(st, root, mid + side, mid - side, col)
	_tri(st, mid - side, mid + side, tip, col.darkened(0.15))


func _blade(st: SurfaceTool, o: Vector3, yaw: float, h: float, col: Color) -> void:
	var w := Vector3(cos(yaw), 0, sin(yaw)) * 0.06
	var lean := Vector3(sin(yaw), 0, -cos(yaw)) * 0.12
	_tri(st, o - w, o + w, o + Vector3(0, h, 0) + lean, col)
