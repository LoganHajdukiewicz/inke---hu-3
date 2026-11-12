@tool
extends RefCounted
## BUILD ASSIST - runs while you move things with Godot's normal tools.
##   EDGE SNAP     - drag a Platform/Floor/Room/Fence near another one and it
##                   clicks flush (side-by-side, on top, or level with it).
##                   A green guide flashes. Hold Ctrl while dragging to skip.
##   ALT-DRAG COPY - hold Alt when you START dragging: a copy stays behind.
##   GAP RULER     - while a Platform is selected/dragged: line + label to
##                   the nearest platform, "12.4m · Run jump ✓" (measured).
##   SCATTER BRUSH - paint rocks/trees/bushes/grass onto terrain.
##   LEVEL STATS   - counts + estimated run time vs the 10-minute target.

const JumpArcs = preload("res://addons/level_kit/jump_arcs.gd")
const PropScript = preload("res://addons/level_kit/nodes/prop.gd")

var kit: EditorPlugin
var ui := {}

var edge_snap := true
var show_ruler := true
const SNAP_DIST := 1.2         # within this many metres -> snap

# drag tracking
var _drag_node: Node3D = null
var _drag_start := Vector3.ZERO
var _alt_done := false
var _was_down := false
var _overlay: MeshInstance3D
var _label: Label3D
var _guide_t := 0.0

# scatter brush
var scattering := false
var _painting := false
var _last_paint := Vector3(INF, 0, INF)
var _ring: MeshInstance3D
var _hit := Vector3.ZERO
var _has_hit := false
const SCATTER_SETS := {
	"Forest": [[3, 4], [2, 3], [5, 3], [0, 2], [6, 4], [8, 1]],
	"Beach": [[4, 5], [0, 3], [5, 2], [6, 2]],
	"Meadow": [[6, 8], [7, 4], [5, 2], [2, 1]],
	"Rocky": [[0, 6], [1, 2], [6, 2]],
	"Pines": [[3, 5], [0, 2], [6, 3], [9, 1]],
}


# ===========================================================================
# UI
# ===========================================================================
func build(root: VBoxContainer) -> void:
	root.add_child(kit._header("ASSIST  (while you move things)"))
	var row := HFlowContainer.new()
	var es := CheckBox.new(); es.text = "Edge snap"; es.button_pressed = edge_snap
	es.tooltip_text = "Dragged platforms/floors/rooms click flush to neighbours (hold Ctrl to skip)"
	es.toggled.connect(func(v): edge_snap = v)
	row.add_child(es)
	var gr := CheckBox.new(); gr.text = "Gap ruler"; gr.button_pressed = show_ruler
	gr.tooltip_text = "Shows the gap to the nearest platform and the easiest jump that clears it"
	gr.toggled.connect(func(v): show_ruler = v; if not v: _hide_overlay())
	row.add_child(gr)
	var alt := Label.new(); alt.text = "  Alt+drag = copy"
	alt.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
	row.add_child(alt)
	root.add_child(row)

	root.add_child(kit._header("SCATTER BRUSH  (select a Terrain, paint props)"))
	var srow := HBoxContainer.new()
	var set_opt := OptionButton.new()
	for k in SCATTER_SETS:
		set_opt.add_item(k)
	srow.add_child(set_opt)
	ui["set"] = set_opt
	var sb := Button.new(); sb.text = "Paint"; sb.toggle_mode = true
	sb.tooltip_text = "Drag over terrain to scatter. Shift+drag ERASES props under the brush."
	sb.pressed.connect(_toggle_scatter.bind(sb))
	srow.add_child(sb)
	ui["paint_btn"] = sb
	root.add_child(srow)
	var drow := HBoxContainer.new()
	var dl := Label.new(); dl.text = "Size"
	drow.add_child(dl)
	var rad := HSlider.new(); rad.min_value = 2; rad.max_value = 40; rad.value = 8
	rad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(rad)
	ui["s_radius"] = rad
	var dn := Label.new(); dn.text = "Density"
	drow.add_child(dn)
	var den := HSlider.new(); den.min_value = 0.2; den.max_value = 4.0; den.step = 0.1; den.value = 1.0
	den.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(den)
	ui["s_density"] = den
	root.add_child(drow)
	var keep := CheckBox.new(); keep.text = "Keep off paths, pads and flat play areas"; keep.button_pressed = true
	keep.tooltip_text = "Skips steep cliffs, roads, flatten pads and anything with a Platform/Floor/Room above or near it"
	root.add_child(keep)
	ui["s_keep"] = keep

	root.add_child(kit._header("LEVEL STATS"))
	var stats_b := Button.new(); stats_b.text = "Refresh stats"
	stats_b.pressed.connect(refresh_stats)
	root.add_child(stats_b)
	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	out.fit_content = true
	out.selection_enabled = true
	root.add_child(out)
	ui["stats"] = out


# ===========================================================================
# PER-FRAME: edge snap, alt-copy, gap ruler
# ===========================================================================
func process(delta: float) -> void:
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var sel := kit.get_editor_interface().get_selection().get_top_selected_nodes()
	var n: Node3D = sel[0] if sel.size() == 1 and sel[0] is Node3D else null
	# start of a drag
	if down and not _was_down and n:
		_drag_node = n
		_drag_start = n.global_position
		_alt_done = false
	if not down:
		_drag_node = null
	_was_down = down
	if n and down and n == _drag_node:
		var moved := n.global_position.distance_to(_drag_start) > 0.05
		# ALT-DRAG: leave a copy at the starting spot
		if moved and not _alt_done and Input.is_key_pressed(KEY_ALT):
			_alt_done = true
			_leave_copy(n, _drag_start)
		if moved and edge_snap and not Input.is_key_pressed(KEY_CTRL):
			_edge_snap(n)
	if _guide_t > 0.0:
		_guide_t -= delta
	if show_ruler and n and n is Platform:
		_draw_ruler(n as Platform)
	elif _overlay:
		_hide_overlay()


func _leave_copy(n: Node3D, at: Vector3) -> void:
	var root := kit.get_editor_interface().get_edited_scene_root()
	var dup: Node3D = n.duplicate()
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: Alt-drag copy")
	ur.add_do_method(n.get_parent(), "add_child", dup, true)
	ur.add_do_method(kit, "_own_recursive", dup, root)
	ur.add_do_property(dup, "global_transform", Transform3D(n.global_transform.basis, at))
	ur.add_do_reference(dup)
	ur.add_undo_method(n.get_parent(), "remove_child", dup)
	ur.commit_action()
	dup.name = kit._unique_name(n.get_parent(), str(n.name).rstrip("0123456789"))
	kit._status("Copy left behind - keep dragging the original.")


# ---- footprints ------------------------------------------------------------
static func footprint(n: Node3D) -> AABB:
	"""World-space box (axis-aligned) of a snappable node, or empty AABB."""
	var local := AABB()
	if n is Platform:
		local = (n as Platform).local_bounds()
	elif n is Floor:
		var fs: Vector3 = n.floor_size
		local = AABB(Vector3(-fs.x * 0.5, -fs.y, -fs.z * 0.5), fs)
	elif n is Room:
		var s: Vector3 = n.interior_size
		var t: float = n.wall_thickness
		local = AABB(Vector3(-s.x * 0.5 - t, 0, -s.z * 0.5 - t), Vector3(s.x + 2 * t, s.y, s.z + 2 * t))
	elif n is ClimbableWall:
		var ws: Vector3 = n.wall_size
		local = AABB(-ws * 0.5, ws)
	else:
		return AABB()
	# transform the 8 corners (handles rotation)
	var out := AABB()
	for i in range(8):
		var c := local.position + Vector3(local.size.x * (i & 1), local.size.y * ((i >> 1) & 1), local.size.z * ((i >> 2) & 1))
		var w := n.global_transform * c
		if i == 0:
			out = AABB(w, Vector3.ZERO)
		else:
			out = out.expand(w)
	return out


func _snappables(except: Node) -> Array:
	var root := kit.get_editor_interface().get_edited_scene_root()
	if root == null:
		return []
	var out := []
	for t in ["StaticBody3D", "Node3D"]:
		for c in root.find_children("*", t, true, false):
			if c != except and c is Node3D and not out.has(c) and footprint(c).size != Vector3.ZERO and not except.is_ancestor_of(c):
				out.append(c)
	return out


func _edge_snap(n: Node3D) -> void:
	var me := footprint(n)
	if me.size == Vector3.ZERO:
		return
	var best_off := Vector3.ZERO
	var best_d := SNAP_DIST
	var hit_other: Node3D = null
	for o in _snappables(n):
		var ob := footprint(o)
		if ob.position.distance_to(me.position) > 200.0:
			continue
		var cands := []
		# X faces flush (me right edge -> other left edge, and vice versa)
		cands.append(Vector3(ob.position.x - me.end.x, 0, 0))
		cands.append(Vector3(ob.end.x - me.position.x, 0, 0))
		cands.append(Vector3(0, 0, ob.position.z - me.end.z))
		cands.append(Vector3(0, 0, ob.end.z - me.position.z))
		# align edges (same side lines up)
		cands.append(Vector3(ob.position.x - me.position.x, 0, 0))
		cands.append(Vector3(ob.end.x - me.end.x, 0, 0))
		cands.append(Vector3(0, 0, ob.position.z - me.position.z))
		cands.append(Vector3(0, 0, ob.end.z - me.end.z))
		# tops level / stack on top
		cands.append(Vector3(0, ob.end.y - me.end.y, 0))
		cands.append(Vector3(0, ob.end.y - me.position.y, 0))
		for off in cands:
			var d: float = off.length()
			if d < best_d and d > 0.001:
				# must actually be adjacent on the other axes (overlap or near)
				var moved := AABB(me.position + off, me.size)
				var grow := moved.grow(SNAP_DIST)
				if grow.intersects(ob):
					best_d = d
					best_off = off
					hit_other = o
	if hit_other:
		n.global_position += best_off
		_guide_t = 0.6
		kit._status("Snapped to %s  (hold Ctrl to place freely)" % hit_other.name)


# ---- gap ruler -------------------------------------------------------------
func _draw_ruler(p: Platform) -> void:
	var me := footprint(p)
	var best: Node3D = null
	var best_gap := INF
	var best_a := Vector3.ZERO
	var best_b := Vector3.ZERO
	for o in _snappables(p):
		if not (o is Platform or o is Floor):
			continue
		var ob := footprint(o)
		var dx := maxf(0.0, maxf(ob.position.x - me.end.x, me.position.x - ob.end.x))
		var dz := maxf(0.0, maxf(ob.position.z - me.end.z, me.position.z - ob.end.z))
		var gap := Vector2(dx, dz).length()
		if gap < 0.05 or gap > 45.0 or gap >= best_gap:
			continue
		best_gap = gap
		best = o
		# closest points on the two top rectangles
		var a := Vector3(clampf(ob.get_center().x, me.position.x, me.end.x), me.end.y, clampf(ob.get_center().z, me.position.z, me.end.z))
		var b := Vector3(clampf(a.x, ob.position.x, ob.end.x), ob.end.y, clampf(a.z, ob.position.z, ob.end.z))
		best_a = a; best_b = b
	if best == null:
		_hide_overlay()
		return
	var dh := best_b.y - best_a.y
	var move := JumpArcs.best_move(best_gap, dh)
	var down_move := JumpArcs.best_move(best_gap, -dh)
	var col := Color(0.3, 1, 0.4) if move != "" else Color(1, 0.3, 0.3)
	# dh = neighbour top - this top. "to" = jumping from here to there.
	var txt := "%.1fm gap · %s %.1fm\n" % [best_gap, "up" if dh > 0.05 else ("down" if dh < -0.05 else "level"), absf(dh)]
	txt += ("to %s: %s ✓" % [best.name, JumpArcs.LABELS[move]]) if move != "" else ("to %s: too far ✗" % best.name)
	if down_move != move:
		txt += "\nback: " + (JumpArcs.LABELS[down_move] + " ✓" if down_move != "" else "too far ✗")
	if _guide_t > 0.0 and _drag_node != null:
		txt = "SNAPPED\n" + txt
	_show_overlay(best_a, best_b, col, txt)


func _show_overlay(a: Vector3, b: Vector3, col: Color, txt: String) -> void:
	var root := kit.get_editor_interface().get_edited_scene_root() as Node3D
	if root == null:
		return
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.vertex_color_use_as_albedo = true
		_overlay.material_override = m
		root.add_child(_overlay)
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = true
		_label.pixel_size = 0.0012
		_label.font_size = 28
		_label.outline_size = 10
		root.add_child(_label)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(col)
	var lift := Vector3(0, 0.3, 0)
	im.surface_add_vertex(a + lift); im.surface_add_vertex(b + lift)
	for p in [a, b]:
		im.surface_add_vertex(p + lift); im.surface_add_vertex(p)
	im.surface_end()
	_overlay.mesh = im
	_label.text = txt
	_label.modulate = col
	_label.global_position = (a + b) * 0.5 + Vector3(0, 1.6, 0)


func _hide_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	if _label and is_instance_valid(_label):
		_label.queue_free()
	_overlay = null
	_label = null


# ===========================================================================
# SCATTER BRUSH
# ===========================================================================
func _toggle_scatter(b: Button) -> void:
	scattering = b.button_pressed
	if scattering:
		kit._cancel_place(); kit._end_brush()
		if kit.drag: kit.drag.cancel()
		if kit.plus: kit.plus.cancel()
		kit._status("Scatter: drag over terrain to paint %s. Shift+drag erases. Click Paint again / Esc to stop." % ui["set"].get_item_text(ui["set"].selected))
	else:
		_free_ring()


func stop_scatter() -> void:
	scattering = false
	_painting = false
	if ui.has("paint_btn"):
		ui["paint_btn"].button_pressed = false
	_free_ring()


func scatter_input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		stop_scatter()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouse:
		var h: Dictionary = kit._raycast(camera, event.position)
		_has_hit = not h.is_empty()
		if _has_hit:
			_hit = h.position
		_update_ring(event.shift_pressed if event is InputEventMouse else false)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = event.pressed
		if _painting and _has_hit:
			_dab(event.shift_pressed)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _painting and _has_hit:
		_dab(event.shift_pressed)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _dab(erase: bool) -> void:
	var radius: float = ui["s_radius"].value
	if _hit.distance_to(_last_paint) < radius * 0.45 and not erase:
		return
	_last_paint = _hit
	var root := kit.get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	if erase:
		var gone := []
		for p in root.get_tree().get_nodes_in_group("LKProp"):
			if p is Node3D and Vector2(p.global_position.x - _hit.x, p.global_position.z - _hit.z).length() < radius:
				gone.append(p)
		if gone.is_empty():
			return
		var ur := kit.get_undo_redo()
		ur.create_action("Level Kit: erase props")
		for p in gone:
			ur.add_do_method(p.get_parent(), "remove_child", p)
			ur.add_undo_method(p.get_parent(), "add_child", p, true)
			ur.add_undo_method(p, "set_owner", root)
			ur.add_undo_reference(p)
		ur.commit_action()
		return
	var set_name: String = ui["set"].get_item_text(ui["set"].selected)
	var parts: Array = SCATTER_SETS[set_name]
	var total := 0
	for pr in parts:
		total += pr[1]
	var area := PI * radius * radius
	var count := int(area / 18.0 * float(ui["s_density"].value)) + 1
	var parent: Node = kit._placement_parent(root, "Scenery")
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: scatter " + set_name)
	var placed := 0
	for i in range(count):
		var a := randf() * TAU
		var d := sqrt(randf()) * radius
		var p := _hit + Vector3(cos(a) * d, 0, sin(a) * d)
		var g: Dictionary = kit._ground_below(p + Vector3.UP * 3.0, [], 60.0)
		if g.is_empty():
			continue
		if ui["s_keep"].button_pressed and not _ok_spot(g, Vector3(p.x, g.y, p.z)):
			continue
		# weighted kind pick
		var r := randi() % total
		var kind := 0
		for pr in parts:
			if r < pr[1]:
				kind = pr[0]; break
			r -= pr[1]
		var prop = PropScript.new()
		prop.kind = kind
		prop.seed = randi() % 9999
		prop.name = kit._unique_name(parent, ["Rock", "Boulder", "Tree", "Pine", "Palm", "Bush", "Grass", "Flowers", "Stump", "Log"][kind])
		var sc := randf_range(0.75, 1.3)
		var xf := Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, g.y - 0.05, p.z))
		ur.add_do_method(parent, "add_child", prop, true)
		ur.add_do_method(prop, "set_owner", root)
		ur.add_do_property(prop, "global_transform", xf)
		ur.add_do_reference(prop)
		ur.add_undo_method(parent, "remove_child", prop)
		placed += 1
	ur.commit_action()
	kit._status("Scattered %d props (%s)." % [placed, set_name])


func _ok_spot(g: Dictionary, p: Vector3) -> bool:
	var col = g.get("collider")
	# only on terrain (never on platforms/floors/rooms)
	if not (col is Terrain):
		return false
	var t := col as Terrain
	if t.is_slide_at(p):
		return false
	# stay off roads + flatten pads
	for c in t.get_children():
		if c is FlattenPad and Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < (c as FlattenPad).radius:
			return false
	var l := t.to_local(p)
	var n := t.resolution
	var ix := int((l.x + t.size.x * 0.5) / t.size.x * n)
	var iz := int((l.z + t.size.y * 0.5) / t.size.y * n)
	if t._path_mask.size() == (n + 1) * (n + 1):
		var idx := clampi(iz, 0, n) * (n + 1) + clampi(ix, 0, n)
		if t._path_mask[idx] > 0.1:
			return false
	# not right next to authored gameplay
	for o in kit.get_editor_interface().get_edited_scene_root().get_tree().get_nodes_in_group("LevelKitPlatform"):
		if o is Node3D:
			var fb := footprint(o).grow(1.5)
			if fb.has_point(Vector3(p.x, fb.get_center().y, p.z)):
				return false
	return true


func _update_ring(erase: bool) -> void:
	var root := kit.get_editor_interface().get_edited_scene_root() as Node3D
	if not _has_hit or root == null:
		_free_ring(); return
	if _ring == null or not is_instance_valid(_ring):
		_ring = MeshInstance3D.new()
		var tor := TorusMesh.new(); tor.inner_radius = 0.95; tor.outer_radius = 1.0; tor.rings = 48; tor.ring_segments = 4
		_ring.mesh = tor
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring.material_override = m
		root.add_child(_ring)
	var r: float = ui["s_radius"].value
	_ring.scale = Vector3(r, 1, r)
	_ring.global_position = _hit + Vector3.UP * 0.2
	(_ring.material_override as StandardMaterial3D).albedo_color = Color(1, 0.35, 0.3, 0.8) if erase else Color(0.4, 1, 0.5, 0.8)


func _free_ring() -> void:
	if _ring and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


# ===========================================================================
# LEVEL STATS
# ===========================================================================
func refresh_stats() -> void:
	var root := kit.get_editor_interface().get_edited_scene_root()
	var out: RichTextLabel = ui["stats"]
	out.clear()
	if root == null:
		return
	var counts := {"CRED": 0, "CRED value": 0, "Gears": 0, "Spray cans": 0, "Health": 0, "Enemies": 0, "Bosses": 0,
		"Checkpoints": 0, "Signs / dialogue": 0, "Quest givers": 0, "Crates & barrels": 0, "Rails": 0, "Grapple points": 0,
		"Platforms": 0, "Props": 0}
	var checkpoints := []
	var spawn := Vector3.ZERO
	var boss_pos = null
	var cred_gate := 0
	for n in root.find_children("*", "", true, false):
		var sp: String = n.scene_file_path
		if sp.ends_with("cred.tscn"):
			counts["CRED"] += 1; counts["CRED value"] += int(n.get("cred_value"))
		elif sp.contains("teeth_gear"): counts["Gears"] += 1
		elif sp.ends_with("spray_can.tscn"): counts["Spray cans"] += 1
		elif sp.ends_with("health_pickup.tscn"): counts["Health"] += 1
		elif sp.contains("/Enemies/"):
			counts["Enemies"] += 1
			if n.get("is_boss") == true:
				counts["Bosses"] += 1; boss_pos = (n as Node3D).global_position
		elif sp.ends_with("checkpoint.tscn"):
			counts["Checkpoints"] += 1; checkpoints.append((n as Node3D).global_position)
		elif sp.ends_with("dialogue_trigger.tscn"): counts["Signs / dialogue"] += 1
		elif sp.ends_with("quest_giver.tscn"): counts["Quest givers"] += 1
		elif sp.contains("/Breakables/"): counts["Crates & barrels"] += 1
		elif sp.ends_with("rail.tscn"): counts["Rails"] += 1
		elif sp.ends_with("grapple_point.tscn"): counts["Grapple points"] += 1
		elif sp.ends_with("inke.tscn") or sp.ends_with("inke_no_hu3.tscn"): spawn = (n as Node3D).global_position
		if n is Platform: counts["Platforms"] += 1
		if n is LKProp: counts["Props"] += 1
		if n is CredGate: cred_gate = maxi(cred_gate, int(n.get("cred_needed")))
	var quest_cred := 0
	for g in root.find_children("*", "", true, false):
		if g.scene_file_path.ends_with("quest_giver.tscn"):
			var qf := str(g.get("quest_file"))
			if qf != "" and ResourceLoader.exists("res://quests/" + qf):
				quest_cred += int(load("res://quests/" + qf).cred_reward)
	# Run-time estimate: walk the checkpoint chain from spawn (nearest-next),
	# at ~6 m/s average real platforming speed (incl. jumps/reading), plus
	# ~12s per sign, ~25s per quest giver chat, ~6s per enemy, boss 90s.
	var route := 0.0
	var at := spawn
	var left := checkpoints.duplicate()
	while not left.is_empty():
		var bi := 0
		for i in range(left.size()):
			if at.distance_to(left[i]) < at.distance_to(left[bi]): bi = i
		route += at.distance_to(left[bi])
		at = left[bi]
		left.remove_at(bi)
	if boss_pos != null:
		route += at.distance_to(boss_pos)
	var secs: float = route / 6.0 + counts["Signs / dialogue"] * 12.0 + counts["Quest givers"] * 25.0 + counts["Enemies"] * 6.0 + (90.0 if counts["Bosses"] > 0 else 0.0)
	var mins: float = secs / 60.0
	var colr := "lime" if mins >= 8.0 and mins <= 12.0 else ("yellow" if mins >= 6.0 and mins <= 14.0 else "orange")
	var t := "[b]Est. run time:[/b] [color=%s]%.1f min[/color]  (target 10)\n" % [colr, mins]
	t += "[color=gray]route %.0fm through %d checkpoints @6m/s + dialogue/fights[/color]\n" % [route, checkpoints.size()]
	if cred_gate > 0:
		var ok: bool = quest_cred + counts["CRED value"] >= cred_gate
		t += "[b]CRED gate %d:[/b] quests give %d + medallions %d = [color=%s]%d %s[/color]\n" % [cred_gate, quest_cred, counts["CRED value"], "lime" if ok else "red", quest_cred + counts["CRED value"], "✓" if ok else "✗ not enough!"]
	for k in counts:
		t += "%s: %d    " % [k, counts[k]]
	# checkpoint spacing warning
	var worst := 0.0
	checkpoints.append(spawn)
	for c in checkpoints:
		var nearest := INF
		for d in checkpoints:
			if d != c: nearest = minf(nearest, c.distance_to(d))
		worst = maxf(worst, nearest if nearest < INF else 0.0)
	if worst > 120.0:
		t += "\n[color=orange]⚠ A checkpoint is %.0fm from any other - add one in between.[/color]" % worst
	out.append_text(t)
