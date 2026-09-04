@tool
extends StaticBody3D
class_name Room
## Instant building interior. One node = floor + four walls + optional
## ceiling, with door and window openings cut wherever you drop Doorway
## children. Rebuild is live in the editor.
##
## HOW TO USE:
##   1. Add a Room node, set interior_size
##   2. Add a Doorway child, drag it to a wall - an opening is cut there
##      (set sill_height > 0 to make it a window instead of a door)
##   3. Snap several Rooms side by side and connect them with doorways
##      to build whole buildings. Pair with a Terrain FlattenPad outside.
##
## Generated geometry is runtime-only (not saved into the scene file).

@export_group("Shape")
## Interior space: width (X), wall height (Y), depth (Z).
@export var interior_size: Vector3 = Vector3(10, 4, 8):
	set(v): interior_size = v; _request_rebuild()
@export var wall_thickness: float = 0.3:
	set(v): wall_thickness = v; _request_rebuild()
@export var floor_thickness: float = 0.3:
	set(v): floor_thickness = v; _request_rebuild()
@export var has_ceiling: bool = true:
	set(v): has_ceiling = v; _request_rebuild()
## Skip generating the floor slab (e.g. room sits on Terrain or a Floor).
@export var has_floor: bool = true:
	set(v): has_floor = v; _request_rebuild()

@export_group("Colors")
@export var wall_color: Color = Color(0.75, 0.7, 0.62):
	set(v): wall_color = v; _request_rebuild()
@export var floor_color: Color = Color(0.45, 0.36, 0.28):
	set(v): floor_color = v; _request_rebuild()
@export var ceiling_color: Color = Color(0.85, 0.83, 0.78):
	set(v): ceiling_color = v; _request_rebuild()

var _parts_root: Node3D
var _shapes: Array[CollisionShape3D] = []
var _rebuild_queued := false


func _ready():
	_rebuild()


func _request_rebuild():
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild():
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if _parts_root and is_instance_valid(_parts_root):
		_parts_root.free()   # Immediate: old visuals must not linger a frame
	# CollisionShape3D only works as a DIRECT child of the body, so shapes
	# live on self and are tracked for cleanup separately from the meshes.
	for s in _shapes:
		if is_instance_valid(s):
			s.free()
	_shapes.clear()
	_parts_root = Node3D.new()
	add_child(_parts_root)
	
	var w := interior_size.x
	var h := interior_size.y
	var d := interior_size.z
	var t := wall_thickness
	
	var wall_mat := _mat(wall_color)
	var floor_mat := _mat(floor_color)
	var ceil_mat := _mat(ceiling_color)
	
	# Floor and ceiling slabs
	if has_floor:
		_slab(Vector3(w + 2 * t, floor_thickness, d + 2 * t), Vector3(0, -floor_thickness * 0.5, 0), floor_mat)
	if has_ceiling:
		_slab(Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, h + t * 0.5, 0), ceil_mat)
	
	# Gather doorways per wall. Walls: 0=N(-z) 1=S(+z) 2=W(-x) 3=E(+x)
	var openings := [[], [], [], []]
	for c in get_children():
		if c is Doorway:
			var wall := _nearest_wall(c.position, w, d)
			c.position = _snap_to_wall(c.position, wall, w, d)
			var along = c.position.x if wall < 2 else c.position.z
			openings[wall].append({
				"center": along,
				"width": c.width,
				"bottom": c.sill_height,
				"top": minf(c.sill_height + c.height, h),
			})
	
	# Build each wall as segments around its openings
	_build_wall(0, w, h, d, t, openings[0], wall_mat)
	_build_wall(1, w, h, d, t, openings[1], wall_mat)
	_build_wall(2, d, h, w, t, openings[2], wall_mat)
	_build_wall(3, d, h, w, t, openings[3], wall_mat)


func _build_wall(wall: int, length: float, h: float, other: float, t: float, holes: Array, mat: StandardMaterial3D) -> void:
	# Wall local axis: 'along' spans [-length/2 - t, length/2 + t] so corners meet
	var full := length + 2.0 * t
	holes.sort_custom(func(a, b): return a.center < b.center)
	
	# Vertical strips between holes (full height), clamped to the wall
	var cursor := -full * 0.5
	var strips := []   # {from, to} along the wall
	for hole in holes:
		var left = clampf(hole.center - hole.width * 0.5, -full * 0.5, full * 0.5)
		if left > cursor + 0.01:
			strips.append({"from": cursor, "to": left})
		cursor = maxf(cursor, clampf(hole.center + hole.width * 0.5, -full * 0.5, full * 0.5))
	if cursor < full * 0.5 - 0.01:
		strips.append({"from": cursor, "to": full * 0.5})
	for s in strips:
		_wall_box(wall, s.from, s.to, 0.0, h, other, t, mat)
	# Lintels above + sills below each hole
	for hole in holes:
		var left = hole.center - hole.width * 0.5
		var right = hole.center + hole.width * 0.5
		if hole.top < h - 0.01:
			_wall_box(wall, left, right, hole.top, h, other, t, mat)
		if hole.bottom > 0.01:
			_wall_box(wall, left, right, 0.0, hole.bottom, other, t, mat)


func _wall_box(wall: int, from: float, to: float, y0: float, y1: float, other: float, t: float, mat: StandardMaterial3D) -> void:
	var size_along := to - from
	var mid := (from + to) * 0.5
	var y := (y0 + y1) * 0.5
	var box_size: Vector3
	var box_pos: Vector3
	var off := other * 0.5 + t * 0.5
	match wall:
		0: box_size = Vector3(size_along, y1 - y0, t); box_pos = Vector3(mid, y, -off)
		1: box_size = Vector3(size_along, y1 - y0, t); box_pos = Vector3(mid, y, off)
		2: box_size = Vector3(t, y1 - y0, size_along); box_pos = Vector3(-off, y, mid)
		3: box_size = Vector3(t, y1 - y0, size_along); box_pos = Vector3(off, y, mid)
	_slab(box_size, box_pos, mat)


func _slab(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_parts_root.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	add_child(cs)
	_shapes.append(cs)


func _nearest_wall(p: Vector3, w: float, d: float) -> int:
	var dists = [absf(p.z + d * 0.5), absf(p.z - d * 0.5), absf(p.x + w * 0.5), absf(p.x - w * 0.5)]
	var best := 0
	for i in range(1, 4):
		if dists[i] < dists[best]:
			best = i
	return best


func _snap_to_wall(p: Vector3, wall: int, w: float, d: float) -> Vector3:
	match wall:
		0: p.z = -d * 0.5
		1: p.z = d * 0.5
		2: p.x = -w * 0.5
		3: p.x = w * 0.5
	p.y = 0.0
	return p


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m
