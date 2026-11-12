@tool
extends RefCounted
## LEVEL KIT TOOLS tab: play-test panel, align/spread, looks, hide/lock,
## bookmarks, auto checkpoints.

var kit: EditorPlugin
var ui := {}
const BOOKMARK_KEY := "level_kit_bookmarks"

const LOOKS := [
	["Stone", Color(0.58, 0.56, 0.54)], ["Wood", Color(0.55, 0.38, 0.22)], ["Metal", Color(0.52, 0.58, 0.64)],
	["Grass", Color(0.38, 0.6, 0.28)], ["Sand", Color(0.86, 0.76, 0.52)], ["Snow", Color(0.93, 0.95, 0.98)],
	["Crystal", Color(0.45, 0.75, 1.0)], ["Punk Pink", Color(1.0, 0.3, 0.6)], ["Toxic", Color(0.55, 0.9, 0.2)],
	["Brick", Color(0.65, 0.3, 0.22)], ["Night", Color(0.22, 0.22, 0.32)], ["Gold", Color(0.95, 0.75, 0.25)],
]

const CATEGORIES := {
	"Enemies": ["/Enemies/", "enemy_spawner"],
	"Pickups": ["/Collectibles/"],
	"Breakables": ["/Breakables/"],
	"Scenery": ["LKProp"],
	"Dialogue": ["dialogue_trigger", "/Signs/"],
	"NPCs": ["Friendly NPCs"],
	"Terrain": ["Terrain"],
	"Water": ["water_zone"],
	"Platforms": ["Platform", "floor.tscn"],
}


func build(root: VBoxContainer) -> void:
	var st := Label.new()
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.add_theme_color_override("font_color", Color(0.5, 1, 0.8))
	st.text = "Tools ready."
	root.add_child(st)
	ui["status"] = st

	# ---------- PLAY TEST ----------
	root.add_child(kit._header("PLAY TEST"))
	var pf := HFlowContainer.new()
	var b1 := Button.new(); b1.text = "▶ Play from here (game window)"
	b1.pressed.connect(func(): kit._play_from_here())
	pf.add_child(b1)
	var b2 := Button.new(); b2.text = "▶ Play from selected"
	b2.tooltip_text = "Spawns Inke ON TOP of the selected object (platform, checkpoint...) instead of the viewport centre"
	b2.pressed.connect(_play_from_selected)
	pf.add_child(b2)
	var b3 := Button.new(); b3.text = "■ Stop"
	b3.pressed.connect(func(): kit.get_editor_interface().stop_playing_scene())
	pf.add_child(b3)
	root.add_child(pf)
	var embed := CheckBox.new(); embed.text = "Play inside the editor (embedded window)"
	embed.tooltip_text = "Godot 4.4+: game runs in the Game tab instead of a separate window. F8 stops."
	embed.button_pressed = true
	embed.toggled.connect(_set_embed)
	root.add_child(embed)
	_set_embed(true)
	var hot := Label.new(); hot.text = "Ctrl+Shift+P from the viewport = play from here. Edit, press it again: the scene saves and restarts instantly."
	hot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hot.add_theme_font_size_override("font_size", 11)
	root.add_child(hot)

	# ---------- ALIGN / SPREAD ----------
	root.add_child(kit._header("ALIGN & SPREAD  (select 2+ objects)"))
	var ag := GridContainer.new(); ag.columns = 3
	for spec in [["Align X", "ax"], ["Align Z", "az"], ["Same height", "ay"], ["Spread X", "sx"], ["Spread Z", "sz"], ["Spread line", "sl"], ["Ground all", "g"], ["Face same way (as last clicked)", "rot"], ["Random turn", "rr"]]:
		var b := Button.new(); b.text = spec[0]
		b.pressed.connect(_arrange.bind(spec[1]))
		ag.add_child(b)
	root.add_child(ag)
	var gaprow := HBoxContainer.new()
	var gl := Label.new(); gl.text = "Fixed gap (m, 0 = even)"
	gaprow.add_child(gl)
	var gap := SpinBox.new(); gap.min_value = 0.0; gap.max_value = 60.0; gap.step = 0.5; gap.value = 0.0
	gap.tooltip_text = "Spread X/Z/line: put exactly this many metres between edges (0 = keep first & last, space evenly)"
	gaprow.add_child(gap)
	ui["gap"] = gap
	root.add_child(gaprow)

	# ---------- LOOKS ----------
	root.add_child(kit._header("LOOKS  (click a swatch to restyle the selection)"))
	var lg := GridContainer.new(); lg.columns = 4
	for l in LOOKS:
		var b := Button.new()
		b.text = l[0]
		b.custom_minimum_size = Vector2(0, 26)
		var sb := StyleBoxFlat.new(); sb.bg_color = l[1]; sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color.BLACK if l[1].get_luminance() > 0.5 else Color.WHITE)
		b.pressed.connect(_apply_look.bind(l[0], l[1]))
		lg.add_child(b)
	root.add_child(lg)
	var cl := HFlowContainer.new()
	var copy := Button.new(); copy.text = "Copy look from active"
	copy.tooltip_text = "Select several objects; the LAST clicked one's look is copied onto the others"
	copy.pressed.connect(_copy_look)
	cl.add_child(copy)
	var trim := Button.new(); trim.text = "Toggle edge trim"
	trim.pressed.connect(func(): _set_on_platforms("edge_trim", null))
	cl.add_child(trim)
	root.add_child(cl)

	# ---------- HIDE / LOCK ----------
	root.add_child(kit._header("HIDE & LOCK  (eye = visible in editor, lock = can't be clicked/moved)"))
	var hl := GridContainer.new(); hl.columns = 3
	for c in CATEGORIES:
		var name_l := Label.new(); name_l.text = c
		hl.add_child(name_l)
		var eye := CheckBox.new(); eye.text = "👁"; eye.button_pressed = true
		eye.toggled.connect(_set_visible.bind(c))
		hl.add_child(eye)
		var lock := CheckBox.new(); lock.text = "🔒"
		lock.toggled.connect(_set_lock.bind(c))
		hl.add_child(lock)
	root.add_child(hl)
	var hn := Label.new(); hn.text = "Hiding is editor-only - everything still appears when you play."
	hn.add_theme_font_size_override("font_size", 11)
	root.add_child(hn)

	# ---------- BOOKMARKS ----------
	root.add_child(kit._header("CAMERA BOOKMARKS"))
	var br := HBoxContainer.new()
	var bn := LineEdit.new(); bn.placeholder_text = "name (e.g. Summit)"
	bn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(bn)
	ui["bm_name"] = bn
	var bs := Button.new(); bs.text = "Save view"
	bs.pressed.connect(_save_bookmark)
	br.add_child(bs)
	root.add_child(br)
	var bl := ItemList.new(); bl.custom_minimum_size = Vector2(0, 90)
	bl.item_clicked.connect(func(i, _p, mb):
		if mb == MOUSE_BUTTON_LEFT: _goto_bookmark(i)
		elif mb == MOUSE_BUTTON_RIGHT: _delete_bookmark(i))
	bl.allow_rmb_select = true
	root.add_child(bl)
	ui["bm_list"] = bl
	var bh := Label.new(); bh.text = "Click = fly there · right-click = delete. Saved inside the scene file."
	bh.add_theme_font_size_override("font_size", 11)
	root.add_child(bh)

	# ---------- AUTO CHECKPOINTS ----------
	root.add_child(kit._header("AUTO CHECKPOINTS"))
	var ar := HBoxContainer.new()
	var al := Label.new(); al.text = "Max spacing (m)"
	ar.add_child(al)
	var sp := SpinBox.new(); sp.min_value = 30; sp.max_value = 400; sp.step = 10; sp.value = 90
	ar.add_child(sp)
	ui["cp_spacing"] = sp
	root.add_child(ar)
	var ab := HFlowContainer.new()
	var sug := Button.new(); sug.text = "Suggest"
	sug.tooltip_text = "Shows where checkpoints are missing along your level (spawn -> checkpoints -> boss)"
	sug.pressed.connect(func(): _checkpoints(false))
	ab.add_child(sug)
	var add := Button.new(); add.text = "Add them"
	add.pressed.connect(func(): _checkpoints(true))
	ab.add_child(add)
	root.add_child(ab)
	var out := RichTextLabel.new(); out.fit_content = true; out.bbcode_enabled = true
	root.add_child(out)
	ui["cp_out"] = out


func status(t: String) -> void:
	ui["status"].text = t


func _root() -> Node:
	return kit.get_editor_interface().get_edited_scene_root()


func _sel3d() -> Array:
	var out := []
	for n in kit.get_editor_interface().get_selection().get_top_selected_nodes():
		if n is Node3D and n != _root():
			out.append(n)
	return out


func _editor_setting(k: String, d):
	var es := kit.get_editor_interface().get_editor_settings()
	return es.get_setting(k) if es.has_setting(k) else d


func _set_embed(on: bool) -> void:
	var es := kit.get_editor_interface().get_editor_settings()
	if es.has_setting("run/window_placement/game_embed_mode"):
		es.set_setting("run/window_placement/game_embed_mode", 1 if on else 0)


# ---------------------------------------------------------------- play test
func _play_from_selected() -> void:
	var s := _sel3d()
	var root := _root()
	if s.is_empty() or root == null:
		status("Select something to stand on.")
		return
	var n: Node3D = s[0]
	var p := n.global_position
	if n is Platform:
		p.y = (n as Platform).top_y()
	elif n is Floor:
		p.y += 0.1
	var data := {"scene": root.scene_file_path, "x": p.x, "y": p.y + 1.0, "z": p.z, "yaw": n.global_rotation.y,
		"time": Time.get_unix_time_from_system(), "all_upgrades": true}
	var f := FileAccess.open("user://level_kit_play_here.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	kit.get_editor_interface().save_scene()
	kit.get_editor_interface().play_current_scene()
	status("Playing from %s." % n.name)


# ---------------------------------------------------------------- arrange
func _arrange(mode: String) -> void:
	var s := _sel3d()
	if s.size() < (1 if mode in ["g", "rr"] else 2):
		status("Select at least %d objects." % (1 if mode in ["g", "rr"] else 2))
		return
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: arrange " + mode)
	var first: Node3D = s[0]
	var gap: float = ui["gap"].value
	match mode:
		"ax", "az", "ay":
			var ax: int = {"ax": 0, "ay": 1, "az": 2}[mode]
			for n in s:
				var p: Vector3 = n.global_position
				p[ax] = first.global_position[ax] if mode != "ay" else _top(first) - (_top(n) - n.global_position.y)
				ur.add_do_property(n, "global_position", p); ur.add_undo_property(n, "global_position", n.global_position)
		"sx", "sz", "sl":
			var sorted := s.duplicate()
			var key := 0 if mode == "sx" else 2
			if mode == "sl":
				sorted.sort_custom(func(a, b): return a.global_position.distance_to(first.global_position) < b.global_position.distance_to(first.global_position))
			else:
				sorted.sort_custom(func(a, b): return a.global_position[key] < b.global_position[key])
			var a0: Vector3 = sorted[0].global_position
			var a1: Vector3 = sorted[-1].global_position
			var dir := (a1 - a0)
			dir.y = 0
			if mode == "sx": dir = Vector3(signf(dir.x) if dir.x != 0 else 1.0, 0, 0)
			elif mode == "sz": dir = Vector3(0, 0, signf(dir.z) if dir.z != 0 else 1.0)
			else: dir = dir.normalized()
			var pos := a0
			for i in range(sorted.size()):
				var n: Node3D = sorted[i]
				var target: Vector3
				if gap > 0.0:
					if i > 0:
						pos += dir * (_half(sorted[i - 1], dir) + gap + _half(n, dir))
					target = Vector3(pos.x, n.global_position.y, pos.z) if mode != "sl" else Vector3(pos.x, n.global_position.y, pos.z)
				else:
					var t := float(i) / maxf(sorted.size() - 1, 1)
					var lp := a0.lerp(a1, t)
					target = Vector3(lp.x if mode != "sz" else n.global_position.x, n.global_position.y, lp.z if mode != "sx" else n.global_position.z)
				ur.add_do_property(n, "global_position", target); ur.add_undo_property(n, "global_position", n.global_position)
		"g":
			for n in s:
				var ex := []
				for c in [n] + n.find_children("*", "CollisionObject3D", true, false):
					if c is CollisionObject3D: ex.append((c as CollisionObject3D).get_rid())
				var g: Dictionary = kit._ground_below(n.global_position + Vector3.UP * 0.5, ex, 0.0)
				if g.is_empty(): continue
				var p: Vector3 = n.global_position
				p.y = g.y + kit.drag._bottom_offset(n)
				ur.add_do_property(n, "global_position", p); ur.add_undo_property(n, "global_position", n.global_position)
		"rot":
			var src: Node3D = s[-1]   # last clicked = the one to match
			for n in s:
				var r: Vector3 = n.rotation
				r.y = src.global_rotation.y - (n.get_parent().global_rotation.y if n.get_parent() is Node3D else 0.0)
				ur.add_do_property(n, "rotation", r); ur.add_undo_property(n, "rotation", n.rotation)
		"rr":
			for n in s:
				var r: Vector3 = n.rotation
				r.y = randf() * TAU
				ur.add_do_property(n, "rotation", r); ur.add_undo_property(n, "rotation", n.rotation)
	ur.commit_action()
	status("Arranged %d objects." % s.size())


func _top(n: Node3D) -> float:
	if n is Platform: return (n as Platform).top_y()
	return n.global_position.y


func _half(n: Node3D, dir: Vector3) -> float:
	var fb: AABB = kit.assist.footprint(n)
	if fb.size == Vector3.ZERO:
		return 0.0
	return absf(dir.x) * fb.size.x * 0.5 + absf(dir.z) * fb.size.z * 0.5


# ---------------------------------------------------------------- looks
func _apply_look(look_name: String, col: Color) -> void:
	var s := _sel3d()
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: look " + look_name)
	var count := 0
	var looks := ["Stone", "Wood", "Metal", "Grass", "Sand", "Snow", "Crystal"]
	for n in s:
		for t in [n] + n.find_children("*", "", true, false):
			if t is Platform:
				var li := looks.find(look_name)
				ur.add_do_property(t, "look", li if li >= 0 else 7)
				ur.add_undo_property(t, "look", t.look)
				ur.add_do_property(t, "color", Color.WHITE if li >= 0 else col)
				ur.add_undo_property(t, "color", t.color)
				count += 1
			elif t is LKProp:
				ur.add_do_property(t, "tint", col.lightened(0.4)); ur.add_undo_property(t, "tint", t.tint); count += 1
			elif t is Room:
				ur.add_do_property(t, "wall_color", col); ur.add_undo_property(t, "wall_color", t.wall_color); count += 1
			elif "wall_color" in t:
				ur.add_do_property(t, "wall_color", col); ur.add_undo_property(t, "wall_color", t.wall_color); count += 1
	ur.commit_action()
	status("Restyled %d objects as %s." % [count, look_name])


func _copy_look() -> void:
	var s := _sel3d()
	if s.size() < 2:
		status("Select the targets, then the source LAST.")
		return
	var src: Node3D = s[-1]
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: copy look")
	for n in s.slice(0, s.size() - 1):
		for p in ["look", "color", "edge_trim", "tint", "wall_color", "floor_color", "ceiling_color"]:
			if p in src and p in n:
				ur.add_do_property(n, p, src.get(p)); ur.add_undo_property(n, p, n.get(p))
	ur.commit_action()
	status("Copied %s's look onto %d objects." % [src.name, s.size() - 1])


func _set_on_platforms(prop: String, value) -> void:
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: " + prop)
	for n in _sel3d():
		if n is Platform:
			var v = (not n.get(prop)) if value == null else value
			ur.add_do_property(n, prop, v); ur.add_undo_property(n, prop, n.get(prop))
	ur.commit_action()


# ---------------------------------------------------------------- hide / lock
func _in_category(n: Node, cat: String) -> bool:
	if n == _root():
		return false
	for key in CATEGORIES[cat]:
		if key == "Platform" and n is Platform: return true
		if key == "LKProp" and n is LKProp: return true
		if key == "Terrain" and n is Terrain: return true
		if n.scene_file_path.contains(key): return true
	return false


func _category_nodes(cat: String) -> Array:
	var root := _root()
	if root == null:
		return []
	return root.find_children("*", "", true, false).filter(func(n): return _in_category(n, cat) and not _in_category(n.get_parent(), cat))


func _set_visible(on: bool, cat: String) -> void:
	var c := 0
	for n in _category_nodes(cat):
		if n is Node3D:
			# editor-only: remember + restore; play mode always shows them
			if on:
				if n.has_meta("_lk_hidden"):
					(n as Node3D).visible = true
					n.remove_meta("_lk_hidden")
			elif (n as Node3D).visible:
				(n as Node3D).visible = false
				n.set_meta("_lk_hidden", true)
			c += 1
	status("%s %s (%d)." % [cat, "shown" if on else "hidden", c])


func restore_hidden_before_save() -> void:
	"""Called before saving/playing so hidden categories are never saved invisible."""
	var root := _root()
	if root == null:
		return
	for n in root.find_children("*", "", true, false):
		if n.has_meta("_lk_hidden") and n is Node3D:
			(n as Node3D).visible = true


func rehide_after_save() -> void:
	var root := _root()
	if root == null:
		return
	for n in root.find_children("*", "", true, false):
		if n.has_meta("_lk_hidden") and n is Node3D:
			(n as Node3D).visible = false


func _set_lock(on: bool, cat: String) -> void:
	var c := 0
	for n in _category_nodes(cat):
		if on:
			n.set_meta("_edit_lock_", true)
		elif n.has_meta("_edit_lock_"):
			n.remove_meta("_edit_lock_")
		c += 1
	# deselect anything we just locked
	if on:
		var es := kit.get_editor_interface().get_selection()
		for n in es.get_selected_nodes():
			if _in_category(n, cat):
				es.remove_node(n)
	status("%s %s (%d)." % [cat, "locked" if on else "unlocked", c])


# ---------------------------------------------------------------- bookmarks
func refresh_bookmarks() -> void:
	var l: ItemList = ui["bm_list"]
	l.clear()
	var root := _root()
	if root == null:
		return
	for b in root.get_meta(BOOKMARK_KEY, []):
		l.add_item(str(b.name))


func _save_bookmark() -> void:
	var root := _root()
	var vp := kit.get_editor_interface().get_editor_viewport_3d(0)
	if root == null or vp == null:
		return
	var cam := vp.get_camera_3d()
	var nm: String = ui["bm_name"].text.strip_edges()
	if nm == "":
		nm = "View %d" % (root.get_meta(BOOKMARK_KEY, []).size() + 1)
	var list: Array = root.get_meta(BOOKMARK_KEY, []).duplicate()
	list.append({"name": nm, "xf": cam.global_transform})
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: bookmark")
	ur.add_do_method(root, "set_meta", BOOKMARK_KEY, list)
	ur.add_undo_method(root, "set_meta", BOOKMARK_KEY, root.get_meta(BOOKMARK_KEY, []))
	ur.add_do_method(self, "refresh_bookmarks")
	ur.add_undo_method(self, "refresh_bookmarks")
	ur.commit_action()
	ui["bm_name"].text = ""
	status("Bookmarked '%s'." % nm)


func _goto_bookmark(i: int) -> void:
	var root := _root()
	var list: Array = root.get_meta(BOOKMARK_KEY, [])
	if i >= list.size():
		return
	var xf: Transform3D = list[i].xf
	# Move the editor's 3D camera: select a temporary marker at the target
	# and focus it, then restore the user's selection. The editor camera
	# can't be set directly from a plugin, so we orbit around the look-at
	# point the bookmark was saved with.
	var look_at := xf.origin - xf.basis.z * 15.0
	var m := Marker3D.new()
	root.add_child(m)
	m.global_position = look_at
	var es := kit.get_editor_interface().get_selection()
	var prev := es.get_selected_nodes()
	es.clear(); es.add_node(m)
	var vp := kit.get_editor_interface().get_editor_viewport_3d(0)
	# 'F' = focus selection in the 3D editor
	var ev := InputEventKey.new(); ev.keycode = KEY_F; ev.physical_keycode = KEY_F; ev.pressed = true
	vp.push_input(ev)
	await kit.get_tree().process_frame
	await kit.get_tree().process_frame
	es.clear()
	for n in prev:
		if is_instance_valid(n): es.add_node(n)
	m.queue_free()
	status("Flew to '%s'." % list[i].name)


func _delete_bookmark(i: int) -> void:
	var root := _root()
	var list: Array = root.get_meta(BOOKMARK_KEY, []).duplicate()
	if i < list.size():
		list.remove_at(i)
		root.set_meta(BOOKMARK_KEY, list)
		refresh_bookmarks()


# ---------------------------------------------------------------- auto checkpoints
func _route_points() -> Dictionary:
	var root := _root()
	var spawn = null
	var cps := []
	var boss = null
	var interest := []
	for n in root.find_children("*", "", true, false):
		var sp: String = n.scene_file_path
		if not (n is Node3D): continue
		var p: Vector3 = (n as Node3D).global_position
		if sp.ends_with("inke.tscn") or sp.ends_with("inke_no_hu3.tscn"): spawn = p
		elif sp.ends_with("checkpoint.tscn"): cps.append(p)
		elif n.get("is_boss") == true: boss = p
		elif n is Platform or sp.ends_with("quest_giver.tscn") or sp.ends_with("rail.tscn") or (n is LocationFlag): interest.append(p)
	return {"spawn": spawn, "cps": cps, "boss": boss, "interest": interest}


func _checkpoints(add: bool) -> void:
	var root := _root()
	var out: RichTextLabel = ui["cp_out"]
	out.clear()
	if root == null:
		return
	var r := _route_points()
	if r.spawn == null:
		out.append_text("[color=orange]No Inke in the scene.[/color]")
		return
	var spacing: float = ui["cp_spacing"].value
	# Every 'interesting' spot (platforms, quest givers, rails, flags, boss)
	# must be within `spacing` of a checkpoint (or spawn). Greedy: repeatedly
	# cover the farthest uncovered spot with a new checkpoint on the ground there.
	var covered: Array = r.cps.duplicate()
	covered.append(r.spawn)
	var targets: Array = r.interest.duplicate()
	if r.boss != null: targets.append(r.boss)
	var new_spots := []
	for _i in range(40):
		var worst = null
		var worst_d := spacing
		for t in targets:
			var d := INF
			for c in covered + new_spots:
				d = minf(d, Vector2(t.x - c.x, t.z - c.z).length())
			if d > worst_d:
				worst_d = d; worst = t
		if worst == null:
			break
		new_spots.append(worst)
	if new_spots.is_empty():
		out.append_text("[color=lime]✔ Every area is within %.0fm of a checkpoint.[/color]" % spacing)
		return
	out.append_text("%d spot(s) need a checkpoint:\n" % new_spots.size())
	for p in new_spots:
		out.append_text("  • (%.0f, %.0f, %.0f)\n" % [p.x, p.y, p.z])
	if not add:
		out.append_text("Press [b]Add them[/b] to place checkpoints there.")
		return
	var parent: Node = kit._placement_parent(root, "Level flow")
	var ur := kit.get_undo_redo()
	ur.create_action("Level Kit: auto checkpoints")
	var i := 0
	for p in new_spots:
		var g: Dictionary = kit._ground_below(p + Vector3.UP * 1.5, [], 6.0)
		var y: float = (g.y if not g.is_empty() else p.y)
		var cp: Node3D = load("res://scenes/environments/checkpoint.tscn").instantiate()
		cp.name = kit._unique_name(parent, "AutoCheckpoint")
		cp.checkpoint_id = "auto_%d_%d" % [int(p.x), int(p.z)]
		ur.add_do_method(parent, "add_child", cp, true)
		ur.add_do_method(cp, "set_owner", root)
		ur.add_do_property(cp, "global_position", Vector3(p.x, y + 0.2, p.z))
		ur.add_do_reference(cp)
		ur.add_undo_method(parent, "remove_child", cp)
		i += 1
	ur.commit_action()
	out.append_text("[color=lime]Added %d checkpoints.[/color]" % i)
