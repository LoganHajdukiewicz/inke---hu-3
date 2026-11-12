@tool
extends EditorNode3DGizmoPlugin
## ROTATION ARC - on ANY selected 3D node.
## A semi-circle sits around the object's feet with a small knob on it.
## Drag the knob around the arc to turn the object (yaw). Snaps to 15deg
## steps; hold Shift while dragging for free (1deg) rotation. One drag =
## one Ctrl+Z. Toggle in the Level Kit dock ("Rotation arc").
##
## The arc shows the FRONT half (the direction the object faces is the
## middle of the arc), so you always see which way it points.

var plugin: EditorPlugin
const SEGMENTS := 40


func _init() -> void:
	create_material("arc", Color(0.35, 0.85, 1.0, 0.9), false, true)
	create_material("arc_dim", Color(0.35, 0.85, 1.0, 0.25), false, true)
	create_material("facing", Color(1.0, 0.85, 0.3, 0.95), false, true)
	create_handle_material("knob")


func _get_gizmo_name() -> String:
	return "LevelKit Rotate"


func _get_priority() -> int:
	return -2


func _has_gizmo(node: Node3D) -> bool:
	if plugin == null or not plugin.show_rotate_arc:
		return false
	# skip giant/world nodes and the scene root
	if node is Terrain or node is WaterZone or node is Camera3D or node is DirectionalLight3D:
		return false
	return true


func _radius(node: Node3D) -> float:
	var r := 1.5
	if node is Platform:
		r = maxf((node as Platform).size.x, (node as Platform).size.z) * 0.5 + 1.0
	else:
		for vi in [node] + node.find_children("*", "VisualInstance3D", true, false):
			if vi is VisualInstance3D:
				var bb: AABB = (vi as VisualInstance3D).get_aabb()
				r = maxf(r, Vector2(bb.size.x, bb.size.z).length() * 0.5 + 0.8)
	return clampf(r, 1.2, 40.0)


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	# Only show for the selected node (not every node in the scene)
	if not node in plugin.get_editor_interface().get_selection().get_selected_nodes():
		return
	var r := _radius(node)
	var inv_scale := _inv_scale(node)
	var y := 0.15
	# The gizmo is drawn in the node's local space - which already includes
	# its rotation. Draw a full faint ring plus a bright FRONT half (-Z =
	# forward) and a facing tick, so the arc rotates WITH the object.
	var full := PackedVector3Array()
	var front := PackedVector3Array()
	for i in range(SEGMENTS):
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var p0 := Vector3(sin(a0), 0, -cos(a0)) * r
		var p1 := Vector3(sin(a1), 0, -cos(a1)) * r
		p0.y = y; p1.y = y
		p0 *= inv_scale; p1 *= inv_scale
		# front half = angles within +-90deg of forward
		var mid := (a0 + a1) * 0.5
		if mid <= PI * 0.5 or mid >= PI * 1.5:
			front.append(p0); front.append(p1)
		else:
			full.append(p0); full.append(p1)
	gizmo.add_lines(full, get_material("arc_dim", gizmo), false)
	gizmo.add_lines(front, get_material("arc", gizmo), false)
	# facing arrow from centre to the front of the arc
	var tip := Vector3(0, y, -r) * inv_scale
	var arrow := PackedVector3Array([Vector3(0, y, 0) * inv_scale, tip,
		tip, (Vector3(0.35, y, -r + 0.45)) * inv_scale,
		tip, (Vector3(-0.35, y, -r + 0.45)) * inv_scale])
	gizmo.add_lines(arrow, get_material("facing", gizmo), false)
	# the knob sits on the arc at the facing direction
	gizmo.add_handles(PackedVector3Array([tip]), get_material("knob", gizmo), PackedInt32Array([0]))


func _inv_scale(node: Node3D) -> Vector3:
	var s := node.global_transform.basis.get_scale()
	return Vector3(1.0 / maxf(s.x, 0.001), 1.0 / maxf(s.y, 0.001), 1.0 / maxf(s.z, 0.001))


func _get_handle_name(_gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> String:
	return "Rotate"


func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().rotation


func _set_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	var centre := node.global_position + Vector3.UP * 0.15
	# intersect the mouse ray with the horizontal plane through the arc
	var pl := Plane(Vector3.UP, centre.y)
	var p = pl.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if p == null:
		return
	var d: Vector3 = p - centre
	if Vector2(d.x, d.z).length() < 0.05:
		return
	# Godot forward is -Z: yaw so that -Z points at the cursor
	var yaw := atan2(-d.x, -d.z)
	var step := deg_to_rad(1.0 if Input.is_key_pressed(KEY_SHIFT) else 15.0)
	yaw = snappedf(yaw, step)
	# keep the node's own pitch/roll; only change yaw in its parent's space
	var parent_yaw := 0.0
	var par := node.get_parent()
	if par is Node3D:
		parent_yaw = (par as Node3D).global_rotation.y
	var r := node.rotation
	r.y = wrapf(yaw - parent_yaw, -PI, PI)
	node.rotation = r
	plugin._status("Rotation  %d°   (Shift = free, release to keep)" % roundi(rad_to_deg(node.global_rotation.y)))
	node.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	if cancel:
		node.rotation = restore
		return
	var ur := plugin.get_undo_redo()
	ur.create_action("Rotate " + node.name)
	ur.add_do_property(node, "rotation", node.rotation)
	ur.add_undo_property(node, "rotation", restore)
	ur.add_do_method(node, "update_gizmos")
	ur.add_undo_method(node, "update_gizmos")
	ur.commit_action(false)
