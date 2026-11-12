@tool
extends RefCounted
## DRAG-TO-BUILD + SURFACE SNAP + QUICK MENU
##
## DRAW BOXES: pick a shape in the dock (Platform, Wall, Room, Water,
##   Floor types, Climb fence, Heal patch, Trigger, Flag), then in the 3D view
##   PRESS on a surface, DRAG out the footprint, RELEASE. While dragging:
##     - move the mouse UP/DOWN while holding Shift to set the HEIGHT
##     - it's snapped to the grid and sits on what you started on
##   Keeps drawing until right-click / Esc.
##
## SURFACE SNAP (toggle in the dock, default ON): while you move anything
##   with the normal move gizmo, it slides ALONG the ground under it -
##   over hills, onto roofs and platforms - instead of floating or sinking.
##
## QUICK MENU: with the 3D view focused press Q - a pie of common items
##   appears at the cursor; click one to drop it right there.

var kit: EditorPlugin
var ui := {}
var tool := {}                  # current draw tool spec ({} = off)
var dragging := false
var start := Vector3.ZERO
var cur := Vector3.ZERO
var height := 4.0
var _shift_y0 := 0.0
var preview: MeshInstance3D
var surface_snap := true
var _snap_watch := {}           # node -> last position (for surface snap)
var _pie: Control
var _pie_pos := Vector3.ZERO

var DRAW_TOOLS := [
	{"name": "Platform", "kind": "platform", "h": 1.0, "min_h": 0.3},
	{"name": "Pillar / Block", "kind": "platform", "h": 6.0, "solid": true},
	{"name": "Wall", "kind": "platform", "h": 6.0, "solid": true, "thin": 1.0},
	{"name": "Ramp", "kind": "ramp", "h": 4.0},
	{"name": "Stairs", "kind": "stairs", "h": 4.0},
	{"name": "Room", "kind": "room", "h": 7.0},
	{"name": "Water", "kind": "water", "h": 8.0},
	{"name": "Spring Floor", "kind": "floor", "ftype": 1, "h": 0.5},
	{"name": "Moving Floor", "kind": "floor", "ftype": 4, "h": 0.5},
	{"name": "Falling Floor", "kind": "floor", "ftype": 2, "h": 0.5},
	{"name": "Ice Floor", "kind": "floor", "ftype": 6, "h": 0.5},
	{"name": "Damage Floor", "kind": "floor", "ftype": 5, "h": 0.5},
	{"name": "Slide Floor", "kind": "floor", "ftype": 7, "h": 0.5},
	{"name": "Climb Fence", "kind": "fence", "h": 6.0, "thin": 0.5},
	{"name": "Heal Patch", "kind": "heal", "h": 0.2},
	{"name": "Dialogue Box", "kind": "trigger", "h": 4.0},
	{"name": "Goal Flag", "kind": "flag", "h": 4.0},
]

const PIE := ["Slab", "Pillar", "Ramp", "CRED", "Gear", "Crate", "Inkling", "Checkpoint", "Grapple Point", "Spring Floor", "Sign", "Health"]


# ===========================================================================
func build(root: VBoxContainer) -> void:
	root.add_child(kit._header("DRAW TO SIZE  (press, drag the footprint, release - Shift+drag up/down = height)"))
	var flow := HFlowContainer.new()
	for t in DRAW_TOOLS:
		var b := Button.new()
		b.text = t.name
		b.toggle_mode = true
		b.pressed.connect(_pick.bind(t, b))
		flow.add_child(b)
		t["button"] = b
	root.add_child(flow)
	var row := HFlowContainer.new()
	var snap := CheckBox.new()
	snap.text = "Surface snap while moving"
	snap.button_pressed = surface_snap
	snap.tooltip_text = "Dragging things with the move tool slides them over the ground/roofs under them"
	snap.toggled.connect(func(v): surface_snap = v)
	row.add_child(snap)
	var hint := Label.new()
	hint.text = "  Q in the 3D view = quick place menu"
	hint.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
	row.add_child(hint)
	root.add_child(row)


func _pick(t: Dictionary, b: Button) -> void:
	if tool == t:
		cancel()
		return
	cancel()
	kit._cancel_place()
	kit._end_brush()
	if kit.plus: kit.plus.cancel()
	tool = t
	height = t.h
	b.button_pressed = true
	kit._status("%s: press on a surface and drag out the size. Shift+drag = height. Right-click/Esc to stop." % t.name)


func active() -> bool:
	return not tool.is_empty()


func cancel() -> void:
	if tool.has("button") and is_instance_valid(tool.button):
		tool.button.button_pressed = false
	tool = {}
	dragging = false
	_free_preview()


# ===========================================================================
# DRAWING
# ===========================================================================
func input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel(); kit._status("Stopped drawing.")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel(); kit._status("Stopped drawing.")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit: Dictionary = kit._raycast(camera, event.position)
			if hit.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			start = _snap(hit.position)
			cur = start
			dragging = true
			height = tool.h
			_shift_y0 = event.position.y
			_update_preview()
		elif dragging:
			dragging = false
			_commit()
			_free_preview()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and dragging:
		if event.shift_pressed:
			# vertical mouse motion sets height
			height = maxf(tool.get("min_h", 0.2), height + (-event.relative.y) * 0.05)
			if kit.grid_snap > 0.0:
				height = maxf(snappedf(height, kit.grid_snap * 0.5), tool.get("min_h", 0.2))
		else:
			# project the cursor on the horizontal plane of the start point
			var pl := Plane(Vector3.UP, start.y)
			var p = pl.intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if p != null:
				cur = _snap(p)
		_update_preview()
		kit._status("%s  %.1f × %.1f m, height %.1f m" % [tool.name, _size().x, _size().z, height])
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _snap(p: Vector3) -> Vector3:
	var g: float = kit.grid_snap
	if g > 0.0:
		p.x = snappedf(p.x, g)
		p.z = snappedf(p.z, g)
	return p


func _size() -> Vector3:
	var s := Vector3(absf(cur.x - start.x), height, absf(cur.z - start.z))
	var minw := 1.0
	if tool.has("thin"):
		# walls/fences: the short side collapses to the thickness
		if s.x >= s.z:
			s.z = tool.thin
		else:
			s.x = tool.thin
	if not tool.has("thin") or s.x != tool.thin:
		s.x = maxf(s.x, minw)
	if not tool.has("thin") or s.z != tool.thin:
		s.z = maxf(s.z, minw)
	return s


func _center() -> Vector3:
	return Vector3((start.x + cur.x) * 0.5, start.y, (start.z + cur.z) * 0.5)


func _update_preview() -> void:
	var root := kit.get_editor_interface().get_edited_scene_root() as Node3D
	if root == null:
		return
	if preview == null or not is_instance_valid(preview):
		preview = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 0.6, 0.15, 0.35)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		preview.material_override = m
		root.add_child(preview)
	var s := _size()
	var bm := BoxMesh.new()
	bm.size = s
	preview.mesh = bm
	preview.global_position = _center() + Vector3(0, s.y * 0.5 if not tool.kind in ["water"] else -s.y * 0.5, 0)
	preview.rotation = Vector3.ZERO


func _free_preview() -> void:
	if preview and is_instance_valid(preview):
		preview.queue_free()
	preview = null


func _commit() -> void:
	var root := kit.get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var s := _size()
	var c := _center()
	var long_x := absf(cur.x - start.x) >= absf(cur.z - start.z)
	var n: Node3D
	var group := "Platforms"
	var y := c.y
	match tool.kind:
		"platform":
			n = kit.PlatformScript.new()
			if tool.get("solid", false):
				# block/wall: top at start + height, body reaches down to the start surface
				n.size = Vector3(s.x, 0.5, s.z)
				n.pillar_depth = maxf(s.y - 0.5, 0.0)
			else:
				n.size = Vector3(s.x, maxf(s.y, 0.3), s.z)
			y = c.y + s.y   # Platform origin = its top surface
		"ramp", "stairs":
			n = kit.PlatformScript.new()
			n.shape = 2 if tool.kind == "ramp" else 3
			# ramps climb along the dragged direction (from press to release)
			var run: float = s.x if long_x else s.z
			var wid: float = s.z if long_x else s.x
			n.size = Vector3(wid, 0.5, run)
			n.rise = s.y
			var d := cur - start
			n.rotation.y = atan2(-d.x, -d.z) if d.length() > 0.1 else 0.0
			y = c.y + 0.5
		"room":
			n = load("res://scenes/environments/worldbuilding/room.tscn").instantiate()
			n.interior_size = s
			group = "Worldbuilding"
		"water":
			n = load("res://scenes/environments/water_zone.tscn").instantiate()
			n.water_size = Vector2(s.x, s.z)
			n.water_depth = maxf(s.y, 1.0)
			group = "Levelflow"
		"floor":
			n = load("res://scenes/environments/floor.tscn").instantiate()
			n.floor_type = tool.ftype
			n.floor_size = Vector3(s.x, clampf(s.y, 0.25, 2.0), s.z)
			y = c.y + n.floor_size.y
			group = "Gameplayfloors"
		"fence":
			n = load("res://scenes/environments/climbable_wall.tscn").instantiate()
			n.wall_size = Vector3(s.x if long_x else s.z, s.y, 0.5)
			n.rotation.y = 0.0 if long_x else PI * 0.5
			y = c.y + s.y * 0.5
			group = "Traversal"
		"heal":
			n = load("res://scenes/environments/heal_patch.tscn").instantiate()
			n.patch_size = Vector2(s.x, s.z)
			group = "Levelflow"
		"trigger":
			n = load("res://scenes/environments/dialogue_trigger.tscn").instantiate()
			n.box_size = s
			y = c.y + s.y * 0.5
			group = "Dialogue"
		"flag":
			n = load("res://scenes/quests/location_flag.tscn").instantiate()
			n.size = s
			n.visible_in_game = true
			y = c.y + s.y * 0.5
			group = "Quests"
	if n == null:
		return
	var parent: Node = kit._placement_parent(root, group)
	n.name = kit._unique_name(parent, tool.name.replace(" ", "").replace("/", ""))
	var xf := Transform3D(Basis.from_euler(n.rotation), Vector3(c.x, y, c.z))
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: draw " + tool.name)
	ur.add_do_method(parent, "add_child", n, true)
	ur.add_do_method(kit, "_own_recursive", n, root)
	ur.add_do_property(n, "global_transform", xf)
	ur.add_do_reference(n)
	ur.add_undo_method(parent, "remove_child", n)
	ur.commit_action()
	var es := kit.get_editor_interface().get_selection()
	es.clear()
	es.add_node(n)
	kit._status("%s %.1f × %.1f × %.1f m placed. Drag again for another, or tweak its orange handles." % [tool.name, s.x, s.y, s.z])


# ===========================================================================
# SURFACE SNAP while moving with the regular gizmo
# ===========================================================================
func process_snap() -> void:
	if not surface_snap or active():
		_snap_watch.clear()
		return
	var sel := kit.get_editor_interface().get_selection().get_top_selected_nodes()
	if sel.size() != 1 or not (sel[0] is Node3D):
		_snap_watch.clear()
		return
	var n := sel[0] as Node3D
	if n is Terrain or n is WaterZone or n == kit.get_editor_interface().get_edited_scene_root():
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_snap_watch.erase(n)
		_snap_watch[n] = n.global_position
		return
	var last: Vector3 = _snap_watch.get(n, n.global_position)
	var now := n.global_position
	# only react to HORIZONTAL drags (a vertical drag means "I want it up there")
	var dh := Vector2(now.x - last.x, now.z - last.z).length()
	if dh < 0.01 or absf(now.y - last.y) > 0.01:
		_snap_watch[n] = now
		return
	var ex := []
	for c in [n] + n.find_children("*", "CollisionObject3D", true, false):
		if c is CollisionObject3D:
			ex.append((c as CollisionObject3D).get_rid())
	var bottom := _bottom_offset(n)
	var g: Dictionary = kit._ground_below(now + Vector3.UP * 0.5, ex, 30.0)
	if not g.is_empty():
		var target: float = g.y + bottom
		if absf(target - now.y) < 30.0:
			n.global_position = Vector3(now.x, target, now.z)
	_snap_watch[n] = n.global_position


func _bottom_offset(n: Node3D) -> float:
	if n is Platform:
		return (n as Platform).size.y + (n as Platform).pillar_depth
	for item in kit.CATALOG:
		if item.get("path", "") != "" and item.path == n.scene_file_path:
			return item.get("lift", 0.0)
	return 0.0


# ===========================================================================
# QUICK MENU (Q)
# ===========================================================================
func open_pie(camera: Camera3D, mouse: Vector2) -> void:
	close_pie()
	var hit: Dictionary = kit._raycast(camera, mouse)
	if hit.is_empty():
		return
	_pie_pos = _snap(hit.position)
	var vp := kit.get_editor_interface().get_editor_viewport_3d(0)
	if vp == null:
		return
	_pie = Control.new()
	_pie.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.get_parent().add_child(_pie)
	var r := 110.0
	for i in range(PIE.size()):
		var a := TAU * i / PIE.size() - PI * 0.5
		var b := Button.new()
		b.text = PIE[i]
		b.position = mouse + Vector2(cos(a), sin(a)) * r - Vector2(48, 14)
		b.custom_minimum_size = Vector2(96, 28)
		b.pressed.connect(_pie_pick.bind(PIE[i]))
		_pie.add_child(b)
	var x := Button.new()
	x.text = "✕"
	x.position = mouse - Vector2(14, 14)
	x.pressed.connect(close_pie)
	_pie.add_child(x)


func close_pie() -> void:
	if _pie and is_instance_valid(_pie):
		_pie.queue_free()
	_pie = null


func pie_open() -> bool:
	return _pie != null and is_instance_valid(_pie)


func _pie_pick(nm: String) -> void:
	close_pie()
	for item in kit.CATALOG:
		if item.name == nm or (nm == "Pillar" and item.name == "Pillar") or (nm == "Sign" and item.name == "Sign"):
			kit._place_item = item
			kit._ghost_xf = Transform3D(Basis(), _pie_pos + Vector3.UP * item.get("lift", 0.0))
			kit._commit_place()
			kit._place_item = {}
			return
