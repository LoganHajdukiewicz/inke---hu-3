@tool
extends RefCounted
## LEVEL KIT+ : the slow parts of building a level, made fast.
##   SCRIPT WRITER  - type dialogue as plain text -> JSON + a sign in one click
##   DRAW-A-RAIL    - click points on any surface -> grindable rail
##   QUEST WIZARD   - fill 5 fields -> quest .tres + quest giver placed
##   STAMPS         - save a selection as a reusable chunk, stamp it anywhere
##   PATH SCATTER   - click a line, drop N copies of any item along it
## Owned by level_kit.gd (shares its raycast/undo/placement helpers).

var kit: EditorPlugin           # the main Level Kit plugin
var ui := {}
var mode := ""                  # "", "rail", "sign", "giver", "scatter", "stamp"
var points: Array[Vector3] = []
var preview: MeshInstance3D
var pending := {}

const STAMP_DIR := "res://addons/level_kit/stamps/"
const PORTRAIT_DIR := "res://assets/portraits/"


# ===========================================================================
# UI
# ===========================================================================
func build(root: VBoxContainer) -> void:
	_status_label(root)

	# ---------------- SCRIPT WRITER ----------------
	root.add_child(kit._header("SCRIPT WRITER  (dialogue without JSON)"))
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 11)
	help.text = "One line per message.  Speaker: text   (no speaker = same as last line)\nAdd [uwu] [owo] [anxious] for a portrait.  Blank lines are ignored."
	root.add_child(help)
	var nrow := HBoxContainer.new()
	var nl := Label.new(); nl.text = "File"
	nrow.add_child(nl)
	var fname := LineEdit.new(); fname.placeholder_text = "e.g. Sign_Beach"
	fname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(fname)
	ui["dlg_name"] = fname
	var load_b := Button.new(); load_b.text = "Load"
	load_b.tooltip_text = "Load an existing dialogue file of this scene into the editor box"
	load_b.pressed.connect(_load_dialogue)
	nrow.add_child(load_b)
	root.add_child(nrow)
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 150)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.placeholder_text = "S-1GN: Oh hey! You stopped to read me! [uwu]\nPress X to jump.\nBut you're so smart I bet you already knew that. [owo]\nHU3: The sign is talking again."
	root.add_child(te)
	ui["dlg_text"] = te
	var drow := HFlowContainer.new()
	var save_b := Button.new(); save_b.text = "Save dialogue"
	save_b.pressed.connect(func(): _save_dialogue())
	drow.add_child(save_b)
	var place_sign := Button.new(); place_sign.text = "Save + place S-1GN sign"
	place_sign.tooltip_text = "Saves, then click in the 3D view to drop a sign that plays it"
	place_sign.pressed.connect(func(): if _save_dialogue(): _begin("sign"))
	drow.add_child(place_sign)
	var place_trig := Button.new(); place_trig.text = "Save + place walk-in trigger"
	place_trig.tooltip_text = "Saves, then click to drop an invisible box that auto-plays the dialogue once when Inke walks in (S-1GN 'surprise' lines)"
	place_trig.pressed.connect(func(): if _save_dialogue(): _begin("walkin"))
	drow.add_child(place_trig)
	root.add_child(drow)

	# ---------------- QUEST WIZARD ----------------
	root.add_child(kit._header("QUEST WIZARD  (quest + giver in one step)"))
	var qgrid := GridContainer.new(); qgrid.columns = 2
	ui["q_name"] = _field(qgrid, "NPC name", "Rust")
	ui["q_title"] = _field(qgrid, "Quest title", "Rust's Sunken Gears")
	var tl := Label.new(); tl.text = "Type"
	qgrid.add_child(tl)
	var qtype := OptionButton.new()
	for t in ["collect_gears", "break_boxes", "defeat_enemy", "reach_location", "fetch_item", "defeat_timed"]:
		qtype.add_item(t)
	qgrid.add_child(qtype)
	ui["q_type"] = qtype
	var cl := Label.new(); cl.text = "Count"
	qgrid.add_child(cl)
	var qcount := SpinBox.new(); qcount.min_value = 1; qcount.max_value = 99; qcount.value = 5
	qgrid.add_child(qcount)
	ui["q_count"] = qcount
	var rl := Label.new(); rl.text = "CRED reward"
	qgrid.add_child(rl)
	var qcred := SpinBox.new(); qcred.min_value = 0; qcred.max_value = 500; qcred.value = 15
	qgrid.add_child(qcred)
	ui["q_cred"] = qcred
	var gl := Label.new(); gl.text = "CRED to talk"
	gl.tooltip_text = "Minimum CRED before this NPC gives the quest (boss gates). 0 = anyone."
	qgrid.add_child(gl)
	var qgate := SpinBox.new(); qgate.min_value = 0; qgate.max_value = 999; qgate.value = 0
	qgrid.add_child(qgate)
	ui["q_gate"] = qgate
	root.add_child(qgrid)
	var qdesc := LineEdit.new(); qdesc.placeholder_text = "Quest description (shown in the tracker)"
	root.add_child(qdesc)
	ui["q_desc"] = qdesc
	var qtalk := TextEdit.new(); qtalk.custom_minimum_size = Vector2(0, 60)
	qtalk.placeholder_text = "Small talk, one line each...\nMy gears! A wave took them!"
	root.add_child(qtalk)
	ui["q_talk"] = qtalk
	var qask := LineEdit.new(); qask.placeholder_text = "The ask: 'Bring back 5 gears and the CRED is yours. Deal?'"
	root.add_child(qask)
	ui["q_ask"] = qask
	var qb := Button.new(); qb.text = "Create quest + click to place giver"
	qb.pressed.connect(_quest_wizard)
	root.add_child(qb)
	var qhint := Label.new()
	qhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qhint.add_theme_font_size_override("font_size", 11)
	qhint.text = "reach_location: also drops a goal flag on your 2nd click.  fetch_item: 2nd click places the item to fetch."
	root.add_child(qhint)

	# ---------------- DRAW A RAIL / SCATTER ----------------
	root.add_child(kit._header("DRAW  (click points in the 3D view, Enter = done, Esc = cancel)"))
	var rrow := HBoxContainer.new()
	var hl := Label.new(); hl.text = "Height"
	rrow.add_child(hl)
	var rh := SpinBox.new(); rh.min_value = 0.0; rh.max_value = 20.0; rh.step = 0.25; rh.value = 1.2
	rh.tooltip_text = "Rail height above each clicked point"
	rrow.add_child(rh)
	ui["rail_h"] = rh
	var smooth := CheckBox.new(); smooth.text = "Smooth"; smooth.button_pressed = true
	rrow.add_child(smooth)
	ui["rail_smooth"] = smooth
	root.add_child(rrow)
	var dflow := HFlowContainer.new()
	var rail_b := Button.new(); rail_b.text = "Draw Rail"
	rail_b.pressed.connect(func(): _begin("rail"))
	dflow.add_child(rail_b)
	var path_b := Button.new(); path_b.text = "Draw Terrain Road"
	path_b.tooltip_text = "Click points ON a Terrain: makes a TerrainPath (flat walkable road) child"
	path_b.pressed.connect(func(): _begin("road"))
	dflow.add_child(path_b)
	root.add_child(dflow)
	var srow := HBoxContainer.new()
	var sl := Label.new(); sl.text = "Scatter"
	srow.add_child(sl)
	var sitem := OptionButton.new()
	for it in kit.CATALOG:
		sitem.add_item(it.name)
	sitem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sitem)
	ui["scatter_item"] = sitem
	var sgap := SpinBox.new(); sgap.min_value = 0.5; sgap.max_value = 50; sgap.step = 0.5; sgap.value = 3.0
	sgap.tooltip_text = "Spacing (m) between copies along the line"
	srow.add_child(sgap)
	ui["scatter_gap"] = sgap
	root.add_child(srow)
	var sb := Button.new(); sb.text = "Draw Scatter Line  (e.g. a trail of CRED / gears / crates)"
	sb.pressed.connect(func(): _begin("scatter"))
	root.add_child(sb)

	# ---------------- STAMPS ----------------
	root.add_child(kit._header("STAMPS  (reusable sections)"))
	var strow := HBoxContainer.new()
	var stname := LineEdit.new(); stname.placeholder_text = "stamp name"
	stname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strow.add_child(stname)
	ui["stamp_name"] = stname
	var save_stamp := Button.new(); save_stamp.text = "Save selection"
	save_stamp.tooltip_text = "Saves the selected nodes (and their children) as a stamp. Positions are kept relative to the first selected node."
	save_stamp.pressed.connect(_save_stamp)
	strow.add_child(save_stamp)
	root.add_child(strow)
	var slist := ItemList.new()
	slist.custom_minimum_size = Vector2(0, 90)
	slist.item_activated.connect(func(i): _begin_stamp(slist.get_item_text(i)))
	root.add_child(slist)
	ui["stamp_list"] = slist
	var stb := HFlowContainer.new()
	var use_b := Button.new(); use_b.text = "Stamp selected (click to place)"
	use_b.pressed.connect(func():
		var s: PackedInt32Array = slist.get_selected_items()
		if s.size() > 0:
			_begin_stamp(slist.get_item_text(s[0])))
	stb.add_child(use_b)
	var del_b := Button.new(); del_b.text = "Delete stamp"
	del_b.pressed.connect(_delete_stamp)
	stb.add_child(del_b)
	root.add_child(stb)
	_refresh_stamps()


func _status_label(root: Control) -> void:
	var s := Label.new()
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.add_theme_color_override("font_color", Color(0.5, 1, 0.8))
	s.text = "Level Kit+ ready."
	root.add_child(s)
	ui["status"] = s


func status(t: String) -> void:
	ui["status"].text = t


func _field(grid: GridContainer, label: String, placeholder: String) -> LineEdit:
	var l := Label.new(); l.text = label
	grid.add_child(l)
	var e := LineEdit.new(); e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(e)
	return e


# ===========================================================================
# SCRIPT WRITER
# ===========================================================================
static func parse_script(text: String) -> Array:
	"""Plain text -> DialogueManager lines. 'Speaker: text [portrait]'."""
	var out := []
	var speaker := "S-1GN"
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var portrait := ""
		var m := RegEx.create_from_string("\\[(uwu|owo|anxious|[A-Za-z0-9_\\-]+)\\]\\s*$").search(line)
		if m:
			portrait = m.get_string(1)
			line = line.substr(0, m.get_start()).strip_edges()
		# "Speaker: text" - speaker = 1-3 words before the first colon
		var colon := line.find(":")
		if colon > 0 and colon <= 24:
			var head := line.substr(0, colon).strip_edges()
			if head != "" and head.split(" ", false).size() <= 3 and line.substr(colon + 1).begins_with(" "):
				speaker = head
				line = line.substr(colon + 1).strip_edges()
		var d := {"speaker": speaker, "text": line}
		if portrait != "":
			if portrait in ["uwu", "owo", "anxious"] and speaker == "S-1GN":
				portrait = "S-1GN-" + portrait
			d["portrait"] = portrait
		out.append(d)
	return out


static func to_script(lines: Array) -> String:
	var out := PackedStringArray()
	var last := ""
	for d in lines:
		var s := ""
		var sp := str(d.get("speaker", ""))
		if sp != last:
			s = sp + ": "
			last = sp
		s += str(d.get("text", ""))
		var p := str(d.get("portrait", ""))
		if p != "":
			s += " [" + p.trim_prefix("S-1GN-") + "]"
		out.append(s)
	return "\n".join(out)


func _dialogue_dir() -> String:
	var root := kit.get_editor_interface().get_edited_scene_root()
	return "res://dialogue/%s/" % (root.name if root else "Shared")


func _save_dialogue() -> bool:
	var root := kit.get_editor_interface().get_edited_scene_root()
	if root == null:
		status("Open a scene first.")
		return false
	var fname: String = ui["dlg_name"].text.strip_edges().replace(" ", "_")
	if fname == "":
		status("Give the dialogue a file name.")
		return false
	var lines := parse_script(ui["dlg_text"].text)
	if lines.is_empty():
		status("Write at least one line.")
		return false
	var dir := _dialogue_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir + fname + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"dialogue": lines}, "\t"))
	f.close()
	kit.get_editor_interface().get_resource_filesystem().scan()
	pending["dialogue"] = fname
	status("Saved %s%s.json (%d lines). Dialogue files are found by SCENE ROOT NAME '%s'." % [dir, fname, lines.size(), root.name])
	return true


func _load_dialogue() -> void:
	var fname: String = ui["dlg_name"].text.strip_edges()
	var path := _dialogue_dir() + fname + ".json"
	if not FileAccess.file_exists(path):
		status("No file " + path)
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary and d.has("dialogue"):
		ui["dlg_text"].text = to_script(d["dialogue"])
		status("Loaded " + path)


# ===========================================================================
# QUEST WIZARD
# ===========================================================================
func _quest_wizard() -> void:
	var npc: String = ui["q_name"].text.strip_edges()
	var title: String = ui["q_title"].text.strip_edges()
	if npc == "" or title == "":
		status("NPC name and quest title are required.")
		return
	var qtype: String = ui["q_type"].get_item_text(ui["q_type"].selected)
	var qid := ("q_" + npc + "_" + title).to_lower().replace(" ", "_").replace("'", "")
	var q := Quest.new()
	q.quest_id = qid
	q.title = title
	q.description = ui["q_desc"].text if ui["q_desc"].text != "" else title
	q.quest_type = qtype
	q.target_count = int(ui["q_count"].value)
	q.cred_reward = int(ui["q_cred"].value)
	if qtype in ["reach_location", "fetch_item"]:
		q.target_count = 1
		q.target_id = qid + "_target"
	if qtype == "defeat_enemy" and q.target_count == 1:
		q.require_boss = true
	var path := "res://quests/%s.tres" % qid
	var err := ResourceSaver.save(q, path)
	if err != OK:
		status("Couldn't save " + path)
		return
	kit.get_editor_interface().get_resource_filesystem().scan()
	pending = {"quest_file": qid + ".tres", "npc": npc, "qtype": qtype, "target_id": q.target_id,
		"talk": ui["q_talk"].text, "ask": ui["q_ask"].text, "gate": int(ui["q_gate"].value)}
	_begin("giver")
	status("Saved %s. Click to place %s.%s" % [path, npc, " Then click again for the goal flag." if qtype == "reach_location" else (" Then click again for the fetch item." if qtype == "fetch_item" else "")])


# ===========================================================================
# CLICK MODES
# ===========================================================================
func _begin(m: String) -> void:
	kit._cancel_place()
	kit._end_brush()
	mode = m
	points.clear()
	_clear_preview()
	match m:
		"rail", "road", "scatter":
			status("Click points in the 3D view. Enter (or right-click) = finish, Esc = cancel, Backspace = undo last point.")
		"sign", "walkin":
			status("Click where the %s goes. Esc cancels." % ("sign" if m == "sign" else "trigger"))
		"giver":
			status("Click where %s stands." % pending.get("npc", "the NPC"))


func active() -> bool:
	return mode != ""


func cancel() -> void:
	mode = ""
	points.clear()
	_clear_preview()


func input(camera: Camera3D, event: InputEvent) -> int:
	if mode == "":
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				cancel(); status("Cancelled.")
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			KEY_ENTER, KEY_KP_ENTER:
				_finish()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			KEY_BACKSPACE:
				if points.size() > 0:
					points.pop_back(); _draw_preview()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_finish()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hit: Dictionary = kit._raycast(camera, event.position)
			if hit.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_click(hit.position, hit.get("collider"))
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _click(p: Vector3, collider) -> void:
	match mode:
		"rail", "scatter", "road":
			if mode == "road" and not (collider is Terrain):
				status("Road points must be ON a Terrain.")
				return
			points.append(p)
			_draw_preview()
			status("%d point(s). Enter / right-click to finish." % points.size())
		"sign":
			_place_sign(p, false); cancel()
		"walkin":
			_place_sign(p, true); cancel()
		"giver":
			_place_giver(p)
		"giver_target":
			_place_target(p); cancel()
		"stamp":
			_place_stamp(p)


func _finish() -> void:
	match mode:
		"rail": _make_rail()
		"road": _make_road()
		"scatter": _make_scatter()
	cancel()


# --- preview polyline -------------------------------------------------------
func _draw_preview() -> void:
	var root := kit.get_editor_interface().get_edited_scene_root() as Node3D
	if root == null:
		return
	if preview == null or not is_instance_valid(preview):
		preview = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.albedo_color = Color(0.3, 1, 0.8)
		preview.material_override = m
		root.add_child(preview)   # no owner = never saved
	var im := ImmediateMesh.new()
	if points.size() >= 1:
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		var lift := Vector3(0, ui["rail_h"].value if mode == "rail" else 0.2, 0)
		for i in range(points.size()):
			var a := points[i] + lift
			# little cross at each point
			for d in [Vector3(0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0.4, 0)]:
				im.surface_add_vertex(a - d); im.surface_add_vertex(a + d)
			if i > 0:
				im.surface_add_vertex(points[i - 1] + lift); im.surface_add_vertex(a)
		im.surface_end()
	preview.mesh = im


func _clear_preview() -> void:
	if preview and is_instance_valid(preview):
		preview.queue_free()
	preview = null


# --- builders ---------------------------------------------------------------
func _add_undoable(n: Node, parent: Node, label: String, xf := Transform3D.IDENTITY, set_xf := true) -> void:
	var root := kit.get_editor_interface().get_edited_scene_root()
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit+: " + label)
	ur.add_do_method(parent, "add_child", n, true)
	ur.add_do_method(kit, "_own_recursive", n, root)
	if set_xf:
		ur.add_do_property(n, "global_transform", xf)
	ur.add_do_reference(n)
	ur.add_undo_method(parent, "remove_child", n)
	ur.commit_action()


func _make_rail() -> void:
	if points.size() < 2:
		status("A rail needs at least 2 points.")
		return
	var root := kit.get_editor_interface().get_edited_scene_root()
	var r: Path3D = load("res://scenes/items/Rails/rail.tscn").instantiate()
	r.name = kit._unique_name(kit._placement_parent(root, "Traversal"), "Rail")
	var lift := Vector3(0, ui["rail_h"].value, 0)
	var origin := points[0] + lift
	var c := Curve3D.new()
	for i in range(points.size()):
		var p := points[i] + lift - origin
		var tin := Vector3.ZERO
		var tout := Vector3.ZERO
		if ui["rail_smooth"].button_pressed and i > 0 and i < points.size() - 1:
			var t := (points[i + 1] - points[i - 1]) * 0.25
			tin = -t; tout = t
		c.add_point(p, tin, tout)
	r.curve = c
	_add_undoable(r, kit._placement_parent(root, "Traversal"), "rail", Transform3D(Basis(), origin))
	status("Rail with %d points placed (%.0fm). Land on it to grind." % [points.size(), c.get_baked_length()])


func _make_road() -> void:
	if points.size() < 2:
		status("A road needs at least 2 points.")
		return
	var root := kit.get_editor_interface().get_edited_scene_root()
	var terrain: Terrain = null
	for t in kit._terrains():
		if t.contains_xz(points[0]):
			terrain = t
	if terrain == null:
		status("First point isn't on a Terrain.")
		return
	var tp: Path3D = load("res://scripts/environments/worldbuilding/terrain_path.gd").new()
	tp.name = kit._unique_name(terrain, "Road")
	var c := Curve3D.new()
	for p in points:
		c.add_point(terrain.to_local(p))
	tp.curve = c
	_add_undoable(tp, terrain, "road", Transform3D.IDENTITY, false)
	terrain._request_rebuild()
	status("Road carved into %s. Tune width/blend/color on the TerrainPath." % terrain.name)


func _make_scatter() -> void:
	if points.size() < 2:
		status("Draw at least 2 points.")
		return
	var root := kit.get_editor_interface().get_edited_scene_root()
	var item: Dictionary = kit.CATALOG[ui["scatter_item"].selected]
	var gap: float = ui["scatter_gap"].value
	var parent: Node = kit._placement_parent(root, item.group)
	var spots := []
	var carry := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		var d := carry
		while d <= seg:
			spots.append(a.lerp(b, d / maxf(seg, 0.001)))
			d += gap
		carry = d - seg
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit+: scatter " + item.name)
	for p in spots:
		var g: Dictionary = kit._ground_below(p + Vector3.UP * 2.0)
		var y: float = (g.y if not g.is_empty() else p.y) + item.get("lift", 0.0)
		var n: Node3D = kit._make_instance(item)
		n.name = kit._unique_name(parent, item.name.replace(" ", ""))
		ur.add_do_method(parent, "add_child", n, true)
		ur.add_do_method(n, "set_owner", root)
		ur.add_do_property(n, "global_position", Vector3(p.x, y, p.z))
		ur.add_do_reference(n)
		ur.add_undo_method(parent, "remove_child", n)
	ur.commit_action()
	status("Scattered %d × %s along the line." % [spots.size(), item.name])


func _place_sign(p: Vector3, walkin: bool) -> void:
	var root := kit.get_editor_interface().get_edited_scene_root()
	var parent: Node = kit._placement_parent(root, "Dialogue")
	var dfile: String = pending.get("dialogue", "")
	var n: Node3D
	if walkin:
		n = load("res://scenes/environments/dialogue_trigger.tscn").instantiate()
		n.dialogue_file = dfile
		n.auto_start = true
		n.show_prompt = false
		n.trigger_once = true
		n.dynamic_camera = false
		n.box_size = Vector3(8, 5, 4)
		n.name = kit._unique_name(parent, "Walkin_" + dfile)
		_add_undoable(n, parent, "walk-in trigger", Transform3D(Basis(), p + Vector3.UP * 2.5))
		status("Walk-in trigger for '%s' placed. Resize box_size in the Inspector." % dfile)
		return
	n = load("res://scenes/items/Signs/sign.tscn").instantiate()
	n.name = kit._unique_name(parent, "S1GN_" + dfile)
	var t: Node = load("res://scenes/environments/dialogue_trigger.tscn").instantiate()
	t.name = "DialogueTrigger"
	t.dialogue_file = dfile
	t.box_size = Vector3(5, 5, 5)
	t.camera_walls_enabled = true
	t.camera_wall_left = 6.0
	t.camera_wall_right = 6.0
	n.add_child(t)
	# face the sign toward the viewport camera
	var vp := kit.get_editor_interface().get_editor_viewport_3d(0)
	var yaw := 0.0
	if vp and vp.get_camera_3d():
		var to_cam := vp.get_camera_3d().global_position - p
		yaw = atan2(to_cam.x, to_cam.z) + PI * 0.5
	_add_undoable(n, parent, "sign", Transform3D(Basis(Vector3.UP, yaw), p))
	status("S-1GN sign for '%s' placed, facing the camera." % dfile)


func _place_giver(p: Vector3) -> void:
	var root := kit.get_editor_interface().get_edited_scene_root()
	var parent: Node = kit._placement_parent(root, "NPCs")
	var g: Node3D = load("res://scenes/characters/NPCs/Friendly NPCs/quest_giver.tscn").instantiate()
	g.name = kit._unique_name(parent, "QG_" + str(pending.npc))
	g.npc_name = pending.npc
	g.quest_file = pending.quest_file
	g.cred_minimum = pending.gate
	g.camera_walls_enabled = true
	g.camera_wall_left = 5.0
	g.camera_wall_right = 5.0
	var talk: Array[String] = []
	for l in str(pending.talk).split("\n"):
		if l.strip_edges() != "":
			talk.append(l.strip_edges())
	if not talk.is_empty():
		g.small_talk = talk
	if str(pending.ask) != "":
		g.quest_ask = pending.ask
	g.body_color = Color.from_hsv(randf(), 0.6, 0.95)
	_add_undoable(g, parent, "quest giver", Transform3D(Basis(), p + Vector3.UP * 0.3))
	if pending.qtype in ["reach_location", "fetch_item"]:
		mode = "giver_target"
		status("Now click the %s." % ("GOAL spot (flag)" if pending.qtype == "reach_location" else "item to fetch"))
	else:
		cancel()
		status("%s placed with quest '%s'." % [pending.npc, pending.quest_file])


func _place_target(p: Vector3) -> void:
	var root := kit.get_editor_interface().get_edited_scene_root()
	var parent: Node = kit._placement_parent(root, "Quests")
	var n: Node3D
	if pending.qtype == "reach_location":
		n = load("res://scenes/quests/location_flag.tscn").instantiate()
		n.flag_id = pending.target_id
		n.size = Vector3(6, 4, 6)
		n.visible_in_game = true
		n.discovery_text = str(pending.npc).to_upper() + "'S SPOT"
		n.name = kit._unique_name(parent, "Flag_" + str(pending.npc))
		_add_undoable(n, parent, "goal flag", Transform3D(Basis(), p + Vector3.UP * 2.0))
	else:
		n = load("res://scenes/quests/quest_item.tscn").instantiate()
		n.item_id = pending.target_id
		n.name = kit._unique_name(parent, "Item_" + str(pending.npc))
		_add_undoable(n, parent, "fetch item", Transform3D(Basis(), p + Vector3.UP * 1.0))
	status("Quest for %s is fully wired. Play From Here to test it." % pending.npc)


# ===========================================================================
# STAMPS
# ===========================================================================
func _refresh_stamps() -> void:
	var l: ItemList = ui["stamp_list"]
	l.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAMP_DIR))
	var d := DirAccess.open(STAMP_DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn"):
			l.add_item(f.get_basename())


func _save_stamp(nodes: Array = []) -> void:
	var es := kit.get_editor_interface().get_selection()
	var sel: Array = nodes if not nodes.is_empty() else es.get_top_selected_nodes()
	if sel.is_empty():
		sel = es.get_selected_nodes()
	var nm: String = ui["stamp_name"].text.strip_edges().replace(" ", "_")
	if sel.is_empty() or nm == "":
		status("Select nodes in the scene and type a stamp name.")
		return
	var anchor: Node3D = null
	for s in sel:
		if s is Node3D:
			anchor = s; break
	if anchor == null:
		status("Select at least one 3D node.")
		return
	var base := Node3D.new()
	base.name = nm
	var origin := anchor.global_position
	for s in sel:
		if not (s is Node3D):
			continue
		var dup: Node3D = s.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
		base.add_child(dup)
		dup.transform = Transform3D((s as Node3D).global_transform.basis, (s as Node3D).global_position - origin)
		_set_owner_recursive(dup, base)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAMP_DIR))
	var ps := PackedScene.new()
	var perr := ps.pack(base)
	var serr := ResourceSaver.save(ps, STAMP_DIR + nm + ".tscn") if perr == OK else perr
	base.free()
	if serr != OK:
		status("Couldn't save stamp (error %d)." % serr)
		return
	_refresh_stamps()
	status("Stamp '%s' saved (%d nodes). Double-click it in the list to place copies." % [nm, sel.size()])


func _set_owner_recursive(n: Node, o: Node) -> void:
	"""Own n and its children by o, but don't descend into instanced scenes
	(their insides belong to the instanced .tscn)."""
	if n != o:
		n.owner = o
	if n != o and not n.scene_file_path.is_empty():
		return
	for c in n.get_children():
		_set_owner_recursive(c, o)


func _begin_stamp(nm: String) -> void:
	pending["stamp"] = STAMP_DIR + nm + ".tscn"
	_begin("stamp")
	status("Stamping '%s' - click to place (keeps placing). Esc to stop." % nm)


func _place_stamp(p: Vector3) -> void:
	var ps: PackedScene = load(pending.stamp)
	if ps == null:
		cancel(); return
	var root := kit.get_editor_interface().get_edited_scene_root()
	var inst: Node3D = ps.instantiate()
	var parent: Node = kit._placement_parent(root, "Stamps")
	inst.name = kit._unique_name(parent, inst.name)
	var xf := Transform3D(Basis(), p)
	if kit.random_yaw:
		xf.basis = Basis(Vector3.UP, randf() * TAU)
	# Make the stamp's children editable copies, not a linked instance, so
	# each placement can be tweaked independently.
	var unpacked := Node3D.new()
	unpacked.name = inst.name
	for c in inst.get_children():
		inst.remove_child(c)
		unpacked.add_child(c)
	inst.free()
	_add_undoable(unpacked, parent, "stamp", xf)
	status("Stamped. Click again for another copy, Esc to stop.")


func _delete_stamp() -> void:
	var l: ItemList = ui["stamp_list"]
	var s := l.get_selected_items()
	if s.is_empty():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STAMP_DIR + l.get_item_text(s[0]) + ".tscn"))
	_refresh_stamps()
