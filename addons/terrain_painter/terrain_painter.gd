@tool
extends EditorPlugin
## TERRAIN PAINTER
## Select a Terrain node, turn ON its paint_mode export, then in the 3D
## viewport:
##   - Left-click / drag  = raise the ground under the cursor
##   - Shift + click/drag = lower it
##   - Ctrl-Z / Ctrl-Shift-Z = undo / redo strokes (one stroke = one click)
##   - Brush radius & strength are on the Terrain in the Inspector
## A translucent brush ring under the cursor shows exactly what you'll hit.

var _terrain: Terrain = null       # Currently edited Terrain
var _painting := false
var _lower := false
var _last_hit := Vector3.ZERO
var _has_hit := false
var _brush_vis: MeshInstance3D = null
var _brush_mat: StandardMaterial3D = null
var _stroke_before: PackedFloat32Array = PackedFloat32Array()   # Undo snapshot


func _get_plugin_name() -> String:
	return "Terrain Painter"


func _handles(object: Object) -> bool:
	return object is Terrain


func _edit(object: Object) -> void:
	_terrain = object as Terrain
	if _terrain == null:
		_stop_painting()
		_free_brush()


func _make_visible(visible: bool) -> void:
	if not visible:
		_stop_painting()
		_free_brush()


func _exit_tree() -> void:
	_free_brush()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _terrain == null or not is_instance_valid(_terrain) or not _terrain.paint_mode:
		_free_brush()
		return AFTER_GUI_INPUT_PASS
	
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_update_hit(camera, event.position)
		_update_brush_vis()
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _has_hit:
			_painting = true
			_lower = event.shift_pressed
			_stroke_before = _terrain.paint_data.duplicate()   # For undo
			_apply_stroke(0.0)   # Immediate dab on click
			return AFTER_GUI_INPUT_STOP
		elif not event.pressed and _painting:
			_stop_painting()
			return AFTER_GUI_INPUT_STOP
	
	if event is InputEventMouseMotion and _painting:
		_lower = event.shift_pressed
		return AFTER_GUI_INPUT_STOP
	
	return AFTER_GUI_INPUT_PASS


func _process(delta: float) -> void:
	if _painting and _terrain and is_instance_valid(_terrain) and _has_hit:
		_apply_stroke(delta)


func _apply_stroke(delta: float) -> void:
	# A click gives one fixed dab; holding adds strength * dt continuously
	var amount: float = _terrain.brush_strength * (delta if delta > 0.0 else 0.06)
	if _lower:
		amount = -amount
	_terrain.paint_at(_last_hit, amount)


func _stop_painting() -> void:
	if not _painting:
		return
	_painting = false
	# Register the whole stroke (press -> release) as ONE undo step
	if _terrain and is_instance_valid(_terrain) \
			and _stroke_before.size() > 0 \
			and _stroke_before != _terrain.paint_data:
		var after: PackedFloat32Array = _terrain.paint_data.duplicate()
		var before: PackedFloat32Array = _stroke_before
		var ur := get_undo_redo()
		ur.create_action("Paint Terrain", UndoRedo.MERGE_DISABLE, _terrain)
		ur.add_do_property(_terrain, "paint_data", after)
		ur.add_undo_property(_terrain, "paint_data", before)
		ur.add_do_method(_terrain, "_request_rebuild")
		ur.add_undo_method(_terrain, "_request_rebuild")
		# paint_data is already 'after' - commit without re-running do methods
		ur.commit_action(false)
		_terrain._request_rebuild()
	_stroke_before = PackedFloat32Array()


func _update_hit(camera: Camera3D, mouse_pos: Vector2) -> void:
	_has_hit = false
	if _terrain == null or not is_instance_valid(_terrain):
		return
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	
	# Physics ray against the terrain's own collision first (exact surface)
	var space: PhysicsDirectSpaceState3D = _terrain.get_world_3d().direct_space_state
	if space:
		var params := PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0)
		var hit: Dictionary = space.intersect_ray(params)
		if not hit.is_empty() and _is_own_collider(hit.collider):
			_last_hit = hit.position
			_has_hit = true
			return
	
	# Fallback: intersect the terrain's base plane (lets you paint slightly
	# off the current surface or before collision has built)
	var plane := Plane(Vector3.UP, _terrain.global_position.y)
	var p = plane.intersects_ray(from, dir)
	if p != null:
		var local: Vector3 = _terrain.to_local(p)
		if absf(local.x) <= _terrain.size.x * 0.5 and absf(local.z) <= _terrain.size.y * 0.5:
			_last_hit = p
			_has_hit = true


func _is_own_collider(collider: Object) -> bool:
	var node := collider as Node
	while node:
		if node == _terrain:
			return true
		node = node.get_parent()
	return false


# --- Brush ring visual --------------------------------------------------------

func _update_brush_vis() -> void:
	if not _has_hit or _terrain == null or not is_instance_valid(_terrain):
		_free_brush()
		return
	if _brush_vis == null or not is_instance_valid(_brush_vis):
		_brush_vis = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.94
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 6
		_brush_vis.mesh = torus
		_brush_mat = StandardMaterial3D.new()
		_brush_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_brush_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_brush_mat.albedo_color = Color(0.2, 0.9, 1.0, 0.75)
		_brush_mat.no_depth_test = true
		_brush_vis.material_override = _brush_mat
		_brush_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_brush_vis.top_level = true
		_terrain.add_child(_brush_vis)
	var r: float = _terrain.brush_radius
	_brush_vis.scale = Vector3(r, 1.0, r)
	_brush_vis.global_position = _last_hit + Vector3.UP * 0.15
	_brush_mat.albedo_color = Color(1.0, 0.45, 0.15, 0.75) if _lower else Color(0.2, 0.9, 1.0, 0.75)


func _free_brush() -> void:
	if _brush_vis and is_instance_valid(_brush_vis):
		_brush_vis.queue_free()
	_brush_vis = null
