@tool
extends EditorNode3DGizmoPlugin
## Drag handles + jump-reach overlay for Platform nodes.
##   - Orange handles: width (+X), depth (+Z), thickness (bottom), rise
##     (ramps/stairs/arches). Dragging snaps to the Level Kit grid.
##   - Coloured rings around the top: how far Inke can jump from this edge
##     (walk / run / double / long) when the target is at the SAME height.
##   - Lines to nearby platforms: green = reachable, red = too far, with the
##     easiest move needed. Toggle with the Level Kit dock.

const JumpArcs = preload("res://addons/level_kit/jump_arcs.gd")

var plugin: EditorPlugin

# handle ids
const H_WIDTH := 0
const H_DEPTH := 1
const H_THICK := 2
const H_RISE := 3

var _drag_start_size := Vector3.ZERO
var _drag_start_rise := 0.0


func _init() -> void:
	create_material("outline", Color(1, 0.6, 0.15, 0.9), false, true)
	create_material("reach_walk", JumpArcs.COLORS["walk"] * Color(1, 1, 1, 0.55), false, true)
	create_material("reach_run", JumpArcs.COLORS["run"] * Color(1, 1, 1, 0.55), false, true)
	create_material("reach_double", JumpArcs.COLORS["double"] * Color(1, 1, 1, 0.55), false, true)
	create_material("reach_long", JumpArcs.COLORS["long"] * Color(1, 1, 1, 0.45), false, true)
	create_material("link_ok", Color(0.3, 1.0, 0.4, 0.95), false, true)
	create_material("link_bad", Color(1.0, 0.25, 0.25, 0.95), false, true)
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "LevelKit Platform"


func _has_gizmo(node: Node3D) -> bool:
	return node is Platform


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var p: Platform = gizmo.get_node_3d()
	var s := p.size
	var depth := s.y + p.pillar_depth
	# Outline of the walkable top
	var lines := PackedVector3Array()
	var hw := s.x * 0.5
	var hd := s.z * 0.5
	var top_far := p.rise if p.shape in [Platform.Shape.RAMP, Platform.Shape.STAIRS] else 0.0
	var c := [Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3(hw, top_far, -hd), Vector3(-hw, top_far, -hd)]
	for i in range(4):
		lines.append(c[i]); lines.append(c[(i + 1) % 4])
	gizmo.add_lines(lines, get_material("outline", gizmo), false)
	# Handles
	var handles := PackedVector3Array([
		Vector3(hw, 0, 0),
		Vector3(0, 0, hd),
		Vector3(0, -depth, 0),
	])
	var ids := PackedInt32Array([H_WIDTH, H_DEPTH, H_THICK])
	if p.shape in [Platform.Shape.RAMP, Platform.Shape.STAIRS, Platform.Shape.ARCH]:
		handles.append(Vector3(0, p.rise if p.shape != Platform.Shape.ARCH else p.rise, -hd if p.shape != Platform.Shape.ARCH else 0.0))
		ids.append(H_RISE)
	gizmo.add_handles(handles, get_material("handles", gizmo), ids)
	# Collision so clicking the platform selects it
	var tri := PackedVector3Array()
	var b := p.local_bounds()
	tri.append_array(_box_tris(b))
	gizmo.add_collision_triangles(_tri_mesh(tri))
	if plugin and plugin.show_reach and p.shape != Platform.Shape.RAMP:
		_draw_reach(gizmo, p)
	if plugin and plugin.show_links:
		_draw_links(gizmo, p)


func _draw_reach(gizmo: EditorNode3DGizmo, p: Platform) -> void:
	# Rounded-rectangle rings offset outward from the top edge by the
	# same-height reach of each move.
	for k in ["walk", "run", "double", "long"]:
		var r := JumpArcs.reach_at(k, 0.0)
		if r <= 0.0:
			continue
		var pts := PackedVector3Array()
		var hw := p.size.x * 0.5
		var hd := p.size.z * 0.5
		var seg := 48
		var prev := Vector3.ZERO
		for i in range(seg + 1):
			var a := TAU * i / seg
			var dir := Vector3(cos(a), 0, sin(a))
			var corner := Vector3(signf(dir.x) * hw, 0.05, signf(dir.z) * hd)
			var pt := corner + dir * r
			if p.shape == Platform.Shape.ROUND:
				pt = Vector3(cos(a) * (hw + r), 0.05, sin(a) * (hd + r))
			if i > 0:
				pts.append(prev); pts.append(pt)
			prev = pt
		gizmo.add_lines(pts, get_material("reach_" + k, gizmo), false)


func _draw_links(gizmo: EditorNode3DGizmo, p: Platform) -> void:
	var tree := p.get_tree()
	if tree == null:
		return
	var lines_ok := PackedVector3Array()
	var lines_bad := PackedVector3Array()
	var max_r := JumpArcs.reach_at("long", 0.0) + 6.0
	for other in tree.get_nodes_in_group("LevelKitPlatform"):
		if other == p or not (other is Platform) or not other.is_inside_tree():
			continue
		var o: Platform = other
		var gap := _edge_gap(p, o)
		if gap > max_r:
			continue
		var dh := o.top_y() - p.top_y()
		var move := JumpArcs.best_move(gap, dh)
		var a := Vector3(0, 0.3, 0)
		var bpos := p.to_local(o.global_position) + Vector3(0, 0.3, 0)
		if move == "":
			lines_bad.append(a); lines_bad.append(bpos)
		else:
			lines_ok.append(a); lines_ok.append(bpos)
	if not lines_ok.is_empty():
		gizmo.add_lines(lines_ok, get_material("link_ok", gizmo), false)
	if not lines_bad.is_empty():
		gizmo.add_lines(lines_bad, get_material("link_bad", gizmo), false)


static func _edge_gap(a: Platform, b: Platform) -> float:
	"""Horizontal edge-to-edge gap between two platforms' top footprints."""
	var ab := a.local_bounds()
	var bb := b.local_bounds()
	var ra := Rect2(Vector2(a.global_position.x + ab.position.x, a.global_position.z + ab.position.z), Vector2(ab.size.x, ab.size.z))
	var rb := Rect2(Vector2(b.global_position.x + bb.position.x, b.global_position.z + bb.position.z), Vector2(bb.size.x, bb.size.z))
	var dx := maxf(0.0, maxf(ra.position.x - rb.end.x, rb.position.x - ra.end.x))
	var dz := maxf(0.0, maxf(ra.position.y - rb.end.y, rb.position.y - ra.end.y))
	return Vector2(dx, dz).length()


func _get_handle_name(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return ["Width", "Depth", "Thickness", "Rise"][id]


func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
	var p: Platform = gizmo.get_node_3d()
	_drag_start_size = p.size
	_drag_start_rise = p.rise
	return p.rise if id == H_RISE else p.size


func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var p: Platform = gizmo.get_node_3d()
	var gt := p.global_transform
	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var axis_local: Vector3 = [Vector3.RIGHT, Vector3.BACK, Vector3.DOWN, Vector3.UP][id]
	var axis := (gt.basis * axis_local).normalized()
	var origin := gt.origin
	if id == H_RISE and p.shape != Platform.Shape.ARCH:
		origin = gt * Vector3(0, 0, -p.size.z * 0.5)
	var t := _closest_on_axis(origin, axis, ray_from, ray_dir)
	var snap: float = plugin.grid_snap if plugin else 0.5
	var s := p.size
	match id:
		H_WIDTH:
			s.x = maxf(snappedf(t * 2.0, snap), snap)
		H_DEPTH:
			s.z = maxf(snappedf(t * 2.0, snap), snap)
		H_THICK:
			# thickness handle: slab thickness only, pillar_depth stays
			s.y = maxf(snappedf(t - p.pillar_depth, snap * 0.5), 0.1)
		H_RISE:
			p.rise = snappedf(t, snap * 0.5)
			return
	p.size = s


func _commit_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var p: Platform = gizmo.get_node_3d()
	var prop := "rise" if id == H_RISE else "size"
	if cancel:
		p.set(prop, restore)
		return
	var ur := plugin.get_undo_redo()
	ur.create_action("Resize Platform")
	ur.add_do_property(p, prop, p.get(prop))
	ur.add_undo_property(p, prop, restore)
	ur.commit_action(false)


static func _closest_on_axis(origin: Vector3, axis: Vector3, ray_from: Vector3, ray_dir: Vector3) -> float:
	"""Distance along `axis` (from origin) of the point closest to the mouse ray."""
	var w0 := origin - ray_from
	var a := axis.dot(axis)
	var b := axis.dot(ray_dir)
	var c := ray_dir.dot(ray_dir)
	var d := axis.dot(w0)
	var e := ray_dir.dot(w0)
	var denom := a * c - b * b
	if absf(denom) < 0.0001:
		return 0.0
	return (b * e - c * d) / denom


static func _box_tris(b: AABB) -> PackedVector3Array:
	var p := []
	for i in range(8):
		p.append(b.position + Vector3(b.size.x * (i & 1), b.size.y * ((i >> 1) & 1), b.size.z * ((i >> 2) & 1)))
	var f := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var out := PackedVector3Array()
	for q in f:
		out.append(p[q[0]]); out.append(p[q[1]]); out.append(p[q[2]])
		out.append(p[q[0]]); out.append(p[q[2]]); out.append(p[q[3]])
	return out


static func _tri_mesh(tris: PackedVector3Array) -> TriangleMesh:
	var tm := TriangleMesh.new()
	tm.create_from_faces(tris)
	return tm
