@tool
extends EditorNode3DGizmoPlugin
## MOVING FLOOR PATHS - select a Floor that moves (type MOVING or with
## MOVING in extra types) and you see a dashed line + a GHOST outline of
## where it travels to. Drag the cyan ball at the end to set the path
## (movement_axis). Spinning floors show a curved arrow sized by
## spin_speed - drag its ball outward to spin faster.

var plugin: EditorPlugin


func _init() -> void:
	create_material("path", Color(0.3, 0.9, 1.0, 0.95), false, true)
	create_material("ghost", Color(0.3, 0.9, 1.0, 0.45), false, true)
	create_material("spin", Color(1.0, 0.75, 0.3, 0.95), false, true)
	create_handle_material("ball")


func _get_gizmo_name() -> String:
	return "LevelKit Moving Floor"


func _get_priority() -> int:
	return -3


static func _moves(f: Node) -> bool:
	return f is Floor and (int(f.floor_type) == 4 or 4 in f.extra_floor_types or bool(f.motion_moves_override))


static func _spins(f: Node) -> bool:
	return f is Floor and (int(f.floor_type) == 3 or 3 in f.extra_floor_types or bool(f.motion_spins_override))


func _has_gizmo(node: Node3D) -> bool:
	return node is Floor


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var f := gizmo.get_node_3d()
	if not (f in plugin.get_editor_interface().get_selection().get_selected_nodes()):
		return
	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	var inv := f.global_transform.affine_inverse().basis
	if _moves(f):
		var end_local: Vector3 = inv * Vector3(f.movement_axis)
		var lines := PackedVector3Array()
		var n := 12
		for i in range(n):
			if i % 2 == 0:
				lines.append(end_local * float(i) / n); lines.append(end_local * float(i + 1) / n)
		gizmo.add_lines(lines, get_material("path", gizmo), false)
		# ghost outline of the floor at the far end
		var s: Vector3 = f.floor_size
		var g := PackedVector3Array()
		var h := Vector3(s.x * 0.5, 0, s.z * 0.5)
		var c := [Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z)]
		for i in range(4):
			for dy in [0.0, -s.y]:
				g.append(end_local + c[i] + Vector3(0, dy, 0)); g.append(end_local + c[(i + 1) % 4] + Vector3(0, dy, 0))
			g.append(end_local + c[i]); g.append(end_local + c[i] + Vector3(0, -s.y, 0))
		gizmo.add_lines(g, get_material("ghost", gizmo), false)
		handles.append(end_local + Vector3(0, 0.4, 0)); ids.append(0)
	if _spins(f):
		var r := maxf(f.floor_size.x, f.floor_size.z) * 0.5 + 0.6
		var span: float = clampf(absf(f.spin_speed) / 360.0, 0.05, 1.0) * TAU
		var dir: float = 1.0 if int(f.spin_direction) == 0 else -1.0
		var arc := PackedVector3Array()
		var seg := 32
		for i in range(seg):
			var a0 := -dir * span * i / seg
			var a1 := -dir * span * (i + 1) / seg
			arc.append(Vector3(cos(a0), 0.3, sin(a0)) * Vector3(r, 1, r)); arc.append(Vector3(cos(a1), 0.3, sin(a1)) * Vector3(r, 1, r))
		gizmo.add_lines(arc, get_material("spin", gizmo), false)
		# speed ball: distance from centre = speed (r + speed/90)
		handles.append(Vector3(r + absf(f.spin_speed) / 90.0, 0.3, 0)); ids.append(1)
	if not handles.is_empty():
		gizmo.add_handles(handles, get_material("ball", gizmo), ids)


func _get_handle_name(_g: EditorNode3DGizmo, id: int, _s: bool) -> String:
	return "Move path" if id == 0 else "Spin speed"


func _get_handle_value(g: EditorNode3DGizmo, id: int, _s: bool) -> Variant:
	var f := g.get_node_3d()
	return f.movement_axis if id == 0 else f.spin_speed


func _set_handle(g: EditorNode3DGizmo, id: int, _s: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var f := g.get_node_3d()
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if id == 0:
		var cur: Vector3 = f.global_position + Vector3(f.movement_axis)
		var p = null
		if Input.is_key_pressed(KEY_SHIFT):
			# Shift: move vertically (plane facing the camera through the end)
			var n := -camera.global_transform.basis.z
			n.y = 0
			p = Plane(n.normalized(), cur).intersects_ray(from, dir)
			if p != null:
				p = Vector3(cur.x, p.y, cur.z)
		else:
			p = Plane(Vector3.UP, cur.y).intersects_ray(from, dir)
		if p == null:
			return
		var axis: Vector3 = p - f.global_position
		var snap: float = plugin.grid_snap
		if snap > 0.0:
			axis = axis.snapped(Vector3.ONE * snap)
		f.movement_axis = axis
		plugin._status("Move path  %.1f, %.1f, %.1f  (%.1fm)   Shift = up/down" % [axis.x, axis.y, axis.z, axis.length()])
	else:
		var r := maxf(f.floor_size.x, f.floor_size.z) * 0.5 + 0.6
		var p = Plane(f.global_transform.basis.y, f.global_position + f.global_transform.basis.y * 0.3).intersects_ray(from, dir)
		if p == null:
			return
		var d: float = Vector2(p.x - f.global_position.x, p.z - f.global_position.z).length()
		f.spin_speed = snappedf(clampf((d - r) * 90.0, 5.0, 720.0), 5.0)
		plugin._status("Spin speed %d°/s" % int(f.spin_speed))
	f.update_gizmos()


func _commit_handle(g: EditorNode3DGizmo, id: int, _s: bool, restore: Variant, cancel: bool) -> void:
	var f := g.get_node_3d()
	var prop := "movement_axis" if id == 0 else "spin_speed"
	if cancel:
		f.set(prop, restore); return
	var ur := plugin.get_undo_redo()
	ur.create_action("Edit " + prop)
	ur.add_do_property(f, prop, f.get(prop))
	ur.add_undo_property(f, prop, restore)
	ur.add_do_method(f, "update_gizmos")
	ur.add_undo_method(f, "update_gizmos")
	ur.commit_action(false)
