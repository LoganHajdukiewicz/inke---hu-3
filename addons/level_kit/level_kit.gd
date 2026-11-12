@tool
extends EditorPlugin
## LEVEL KIT - fast greyboxing for Inke & HU-3.
##
## Dock (right side, "Level Kit" tab):
##   PLACE   - pick anything (platform shapes, every game object) and
##             click in the 3D viewport to drop it ON the surface you clicked.
##             Keeps placing until you right-click / Esc. Hold Shift to
##             stack on top of whatever you clicked instead of the hit point.
##   COURSES - one-click jump-tested layouts (stones, spiral tower, block
##             climb, floating islands, mixed gauntlet). Gaps come from
##             Inke's MEASURED jump arcs, so they are always makeable.
##   TERRAIN - sculpt brushes (raise/lower/flatten/smooth/plateau) on the
##             selected Terrain, plus one-click island/valley/mountain shapes.
##   CHECK   - reach rings + reachability lines, and a level validator.
##   PLAY    - Play From Here: runs the scene with Inke at the viewport.
##
## Viewport hotkeys (3D viewport focused, a Level Kit node selected):
##   D  duplicate the selection one jump forward (along its facing)
##   G  drop the selection onto the ground under it
##   F5-style: dock "Play From Here" button (Ctrl+Shift+P)

const Gizmo = preload("res://addons/level_kit/platform_gizmo.gd")
const JumpArcs = preload("res://addons/level_kit/jump_arcs.gd")
const Gen = preload("res://addons/level_kit/generators.gd")
const PlatformScript = preload("res://addons/level_kit/nodes/platform.gd")

# Settings mirrored from the dock
var grid_snap: float = 0.5
var show_reach: bool = true
var show_links: bool = true
var align_to_surface: bool = false
var random_yaw: bool = false

var _gizmo: Gizmo
var _dock: Control
var _ui := {}

# Placement state
var _place_item: Dictionary = {}   # {} = not placing
var _ghost: Node3D
var _ghost_ok := false
var _ghost_xf := Transform3D.IDENTITY

# Terrain brush state
var _brush_mode := ""     # "", "raise", "lower", "flatten", "smooth", "plateau"
var _brush_terrain: Node = null
var _brushing := false
var _brush_hit := Vector3.ZERO
var _brush_has_hit := false
var _brush_before := PackedFloat32Array()
var _flatten_target := 0.0
var _brush_ring: MeshInstance3D

# --- Placeable catalogue ---------------------------------------------------
# kind "platform" builds a Platform with the given props; kind "scene"
# instances a .tscn. "lift" = how far the object's origin sits above the
# surface it's dropped on.
var CATALOG := [
	{"group": "Platforms", "name": "Slab", "kind": "platform", "props": {"shape": 0, "size": Vector3(6, 1, 6)}},
	{"group": "Platforms", "name": "Big Slab", "kind": "platform", "props": {"shape": 0, "size": Vector3(14, 1, 14)}},
	{"group": "Platforms", "name": "Pillar", "kind": "platform", "props": {"shape": 1, "size": Vector3(4, 1, 4), "pillar_depth": 6.0}},
	{"group": "Platforms", "name": "Round Top", "kind": "platform", "props": {"shape": 1, "size": Vector3(6, 1, 6)}},
	{"group": "Platforms", "name": "Ramp", "kind": "platform", "props": {"shape": 2, "size": Vector3(6, 1, 10), "rise": 4.0}},
	{"group": "Platforms", "name": "Stairs", "kind": "platform", "props": {"shape": 3, "size": Vector3(5, 1, 8), "rise": 4.0, "segments": 8}},
	{"group": "Platforms", "name": "Arch Bridge", "kind": "platform", "props": {"shape": 4, "size": Vector3(4, 0.6, 18), "rise": 3.0, "segments": 12, "look": 1}},
	{"group": "Platforms", "name": "Wall Block", "kind": "platform", "props": {"shape": 0, "size": Vector3(8, 1, 1), "pillar_depth": 7.0}},
	{"group": "Gameplay floors", "name": "Spring Floor", "kind": "scene", "path": "res://scenes/environments/floor.tscn", "props": {"floor_type": 1, "floor_size": Vector3(4, 0.5, 4)}, "lift": 0.25},
	{"group": "Gameplay floors", "name": "Moving Floor", "kind": "scene", "path": "res://scenes/environments/floor.tscn", "props": {"floor_type": 4, "floor_size": Vector3(6, 0.5, 6)}, "lift": 0.25},
	{"group": "Gameplay floors", "name": "Falling Floor", "kind": "scene", "path": "res://scenes/environments/floor.tscn", "props": {"floor_type": 2, "floor_size": Vector3(5, 0.5, 5)}, "lift": 0.25},
	{"group": "Gameplay floors", "name": "Spinning Floor", "kind": "scene", "path": "res://scenes/environments/floor.tscn", "props": {"floor_type": 3, "floor_size": Vector3(8, 0.5, 8)}, "lift": 0.25},
	{"group": "Gameplay floors", "name": "Ice Floor", "kind": "scene", "path": "res://scenes/environments/floor.tscn", "props": {"floor_type": 6, "floor_size": Vector3(10, 0.5, 10)}, "lift": 0.25},
	{"group": "Gameplay floors", "name": "Damage Floor", "kind": "scene", "path": "res://scenes/environments/floor.tscn", "props": {"floor_type": 5, "floor_size": Vector3(6, 0.5, 6)}, "lift": 0.25},
	{"group": "Gameplay floors", "name": "Treadmill", "kind": "scene", "path": "res://scenes/environments/floor.tscn", "props": {"floor_type": 8, "floor_size": Vector3(4, 0.5, 12)}, "lift": 0.25},
	{"group": "Traversal", "name": "Grapple Point", "kind": "scene", "path": "res://scenes/environments/grapple_point.tscn", "lift": 8.0},
	{"group": "Traversal", "name": "Swing Bar", "kind": "scene", "path": "res://scenes/environments/swing_bar.tscn", "lift": 0.0},
	{"group": "Traversal", "name": "Rope", "kind": "scene", "path": "res://scenes/environments/rope.tscn", "lift": 10.0},
	{"group": "Traversal", "name": "Ladder", "kind": "scene", "path": "res://scenes/environments/ladder.tscn", "lift": 0.0},
	{"group": "Traversal", "name": "Climb Fence", "kind": "scene", "path": "res://scenes/environments/climbable_wall.tscn", "lift": 0.0},
	{"group": "Traversal", "name": "Balance Beam", "kind": "scene", "path": "res://scenes/environments/balance_beam.tscn", "lift": 0.0},
	{"group": "Traversal", "name": "Rail", "kind": "scene", "path": "res://scenes/items/Rails/rail.tscn", "lift": 1.0},
	{"group": "Traversal", "name": "Ground Pound Mound", "kind": "scene", "path": "res://scenes/environments/ground_pound_mound.tscn", "lift": 0.0},
	{"group": "Pickups", "name": "CRED", "kind": "scene", "path": "res://scenes/items/Collectibles/cred.tscn", "lift": 1.0},
	{"group": "Pickups", "name": "Gear", "kind": "scene", "path": "res://scenes/items/Collectibles/six_teeth_gear.tscn", "lift": 1.0},
	{"group": "Pickups", "name": "Spray Can", "kind": "scene", "path": "res://scenes/items/Collectibles/spray_can.tscn", "lift": 1.0},
	{"group": "Pickups", "name": "Health", "kind": "scene", "path": "res://scenes/items/Collectibles/health_pickup.tscn", "lift": 0.8},
	{"group": "Pickups", "name": "Key", "kind": "scene", "path": "res://scenes/items/Collectibles/key.tscn", "lift": 1.0},
	{"group": "Breakables", "name": "Crate", "kind": "scene", "path": "res://scenes/items/Breakables/box.tscn", "lift": 0.5},
	{"group": "Breakables", "name": "Explosive Barrel", "kind": "scene", "path": "res://scenes/items/Breakables/explosive_barrel.tscn", "lift": 0.6},
	{"group": "Enemies", "name": "Inkling", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Charger", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/charger_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Hopper", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/hopper_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Bomber", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/bomber_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Laser", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/laser_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Shield", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/shield_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Splitter", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/splitter_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Coward", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/coward_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Climber", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/climbing_enemy.tscn", "lift": 1.0},
	{"group": "Enemies", "name": "Turret", "kind": "scene", "path": "res://scenes/characters/NPCs/Enemies/turret_enemy.tscn", "lift": 0.0},
	{"group": "Enemies", "name": "Enemy Spawner", "kind": "scene", "path": "res://scenes/environments/enemy_spawner.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Checkpoint", "kind": "scene", "path": "res://scenes/environments/checkpoint.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Reset Plane", "kind": "scene", "path": "res://scenes/environments/reset_plane.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Heal Patch", "kind": "scene", "path": "res://scenes/environments/heal_patch.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Sign", "kind": "scene", "path": "res://scenes/items/Signs/sign.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Button", "kind": "scene", "path": "res://scenes/environments/button.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Door", "kind": "scene", "path": "res://scenes/environments/door.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Scene Exit", "kind": "scene", "path": "res://scenes/environments/scene_transitioner.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Dialogue Trigger", "kind": "scene", "path": "res://scenes/environments/dialogue_trigger.tscn", "lift": 0.0},
	{"group": "Level flow", "name": "Water", "kind": "scene", "path": "res://scenes/environments/water_zone.tscn", "lift": 0.0},
	{"group": "Worldbuilding", "name": "Room", "kind": "scene", "path": "res://scenes/environments/worldbuilding/room.tscn", "lift": 0.0},
	{"group": "Worldbuilding", "name": "Hallway", "kind": "scene", "path": "res://scenes/environments/worldbuilding/hallway.tscn", "lift": 0.0},
	{"group": "Worldbuilding", "name": "Terrain", "kind": "scene", "path": "res://scenes/environments/worldbuilding/terrain.tscn", "lift": 0.0},
]


func _enter_tree() -> void:
	_gizmo = Gizmo.new()
	_gizmo.plugin = self
	add_node_3d_gizmo_plugin(_gizmo)
	add_custom_type("Platform", "StaticBody3D", PlatformScript, null)
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	if not ProjectSettings.has_setting("autoload/LevelKitPlayHere"):
		add_autoload_singleton("LevelKitPlayHere", "res://addons/level_kit/runtime/play_here.gd")
	set_input_event_forwarding_always_enabled()


func _exit_tree() -> void:
	_cancel_place()
	_end_brush()
	remove_node_3d_gizmo_plugin(_gizmo)
	remove_custom_type("Platform")
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()


func _handles(object: Object) -> bool:
	return object is Node3D


# ===========================================================================
# DOCK UI
# ===========================================================================

func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Level Kit"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	# --- Status line ---
	var status := Label.new()
	status.text = "Pick something, then click in the 3D view."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	root.add_child(status)
	_ui["status"] = status

	# --- PLAY ---
	var play := Button.new()
	play.text = "▶  Play From Here  (Ctrl+Shift+P)"
	play.tooltip_text = "Save, then run this scene with Inke standing where the 3D viewport camera is looking. All movement upgrades are granted."
	play.pressed.connect(_play_from_here)
	root.add_child(play)

	# --- Settings row ---
	var grid_row := HBoxContainer.new()
	var gl := Label.new(); gl.text = "Grid"
	grid_row.add_child(gl)
	var grid := SpinBox.new()
	grid.min_value = 0.0; grid.max_value = 10.0; grid.step = 0.25; grid.value = grid_snap
	grid.tooltip_text = "Snap for placement and handle drags (0 = off)"
	grid.value_changed.connect(func(v): grid_snap = v)
	grid_row.add_child(grid)
	var al := CheckBox.new(); al.text = "Align"; al.tooltip_text = "Tilt placed objects to the surface normal"
	al.toggled.connect(func(v): align_to_surface = v)
	grid_row.add_child(al)
	var ry := CheckBox.new(); ry.text = "Rand yaw"; ry.tooltip_text = "Random rotation for each placed object (props, rocks)"
	ry.toggled.connect(func(v): random_yaw = v)
	grid_row.add_child(ry)
	root.add_child(grid_row)

	# --- PLACE ---
	root.add_child(_header("PLACE  (click to drop, right-click/Esc to stop, Shift = stack)"))
	var groups := {}
	for item in CATALOG:
		if not groups.has(item.group):
			var lab := Label.new(); lab.text = item.group
			lab.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
			root.add_child(lab)
			var flow := HFlowContainer.new()
			root.add_child(flow)
			groups[item.group] = flow
		var b := Button.new()
		b.text = item.name
		b.toggle_mode = true
		b.pressed.connect(_start_place.bind(item, b))
		groups[item.group].add_child(b)
		item["button"] = b

	# --- COURSES ---
	root.add_child(_header("COURSES  (generated at the viewport, jump-tested)"))
	var crow := HBoxContainer.new()
	var ml := Label.new(); ml.text = "Move"
	crow.add_child(ml)
	var move := OptionButton.new()
	for k in ["walk", "run", "double", "long"]:
		move.add_item(JumpArcs.LABELS[k])
	move.select(1)
	crow.add_child(move)
	_ui["move"] = move
	root.add_child(crow)
	var drow := HBoxContainer.new()
	var dl := Label.new(); dl.text = "Difficulty"
	drow.add_child(dl)
	var diff := HSlider.new()
	diff.min_value = 0.0; diff.max_value = 1.0; diff.step = 0.05; diff.value = 0.4
	diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff.tooltip_text = "0 = gaps at 55% of max jump reach (forgiving), 1 = 90% (tight)"
	drow.add_child(diff)
	_ui["diff"] = diff
	root.add_child(drow)
	var nrow := HBoxContainer.new()
	var nl := Label.new(); nl.text = "Count"
	nrow.add_child(nl)
	var cnt := SpinBox.new(); cnt.min_value = 2; cnt.max_value = 60; cnt.value = 8
	nrow.add_child(cnt)
	_ui["count"] = cnt
	var rl := Label.new(); rl.text = "Rise"
	nrow.add_child(rl)
	var rise := SpinBox.new(); rise.min_value = -6; rise.max_value = 6; rise.step = 0.5; rise.value = 1.0
	rise.tooltip_text = "Height change per jump (meters)"
	nrow.add_child(rise)
	_ui["rise"] = rise
	root.add_child(nrow)
	var cflow := HFlowContainer.new()
	for spec in [["Stepping Stones", "stones"], ["Spiral Tower", "spiral"], ["Block Climb", "climb"], ["Floating Islands", "islands"], ["Gauntlet", "gauntlet"]]:
		var cb := Button.new()
		cb.text = spec[0]
		cb.pressed.connect(_generate.bind(spec[1]))
		cflow.add_child(cb)
	root.add_child(cflow)

	# --- TERRAIN ---
	root.add_child(_header("TERRAIN  (select a Terrain first)"))
	var tflow := HFlowContainer.new()
	for spec in [["Raise", "raise"], ["Lower", "lower"], ["Flatten", "flatten"], ["Smooth", "smooth"], ["Plateau", "plateau"]]:
		var tb := Button.new()
		tb.text = spec[0]
		tb.toggle_mode = true
		tb.tooltip_text = {
			"raise": "Drag to raise ground",
			"lower": "Drag to dig down",
			"flatten": "Drag to level ground to the height where you first clicked",
			"smooth": "Drag to soften bumps and spikes",
			"plateau": "Drag to make a flat-topped mesa at the height where you first clicked + brush strength",
		}[spec[1]]
		tb.pressed.connect(_start_brush.bind(spec[1], tb))
		tflow.add_child(tb)
		_ui["brush_" + spec[1]] = tb
	root.add_child(tflow)
	var brow := HBoxContainer.new()
	var bl := Label.new(); bl.text = "Size"
	brow.add_child(bl)
	var bsize := HSlider.new()
	bsize.min_value = 2; bsize.max_value = 60; bsize.value = 10
	bsize.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(bsize)
	_ui["bsize"] = bsize
	var sl := Label.new(); sl.text = "Strength"
	brow.add_child(sl)
	var bstr := HSlider.new()
	bstr.min_value = 1; bstr.max_value = 40; bstr.value = 10
	bstr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(bstr)
	_ui["bstr"] = bstr
	root.add_child(brow)
	var shflow := HFlowContainer.new()
	for spec in [["Island", "island"], ["Mountain", "mountain"], ["Valley", "valley"], ["Crater", "crater"], ["Ridge", "ridge"], ["Clear Sculpt", "clear"]]:
		var sb := Button.new()
		sb.text = spec[0]
		sb.tooltip_text = "Stamp at the terrain centre (or the viewport point if it's over the terrain)."
		sb.pressed.connect(_terrain_shape.bind(spec[1]))
		shflow.add_child(sb)
	root.add_child(shflow)

	# --- CHECK ---
	root.add_child(_header("CHECK"))
	var chk := HFlowContainer.new()
	var reach := CheckBox.new(); reach.text = "Jump reach rings"; reach.button_pressed = show_reach
	reach.tooltip_text = "Rings around the selected Platform: how far each move reaches at the same height"
	reach.toggled.connect(func(v): show_reach = v; _refresh_gizmos())
	chk.add_child(reach)
	var links := CheckBox.new(); links.text = "Reach lines"; links.button_pressed = show_links
	links.tooltip_text = "Lines to nearby platforms: green = jumpable, red = too far/high"
	links.toggled.connect(func(v): show_links = v; _refresh_gizmos())
	chk.add_child(links)
	root.add_child(chk)
	var val := Button.new()
	val.text = "Validate Level"
	val.tooltip_text = "Finds: missing player, no reset plane, unreachable platforms, pickups floating in the air or buried, duplicate checkpoint IDs."
	val.pressed.connect(_validate)
	root.add_child(val)
	var calc := Label.new()
	calc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	calc.text = _reach_table()
	calc.add_theme_font_size_override("font_size", 11)
	root.add_child(calc)
	var out := RichTextLabel.new()
	out.fit_content = true
	out.bbcode_enabled = true
	out.selection_enabled = true
	root.add_child(out)
	_ui["report"] = out


func _header(t: String) -> Control:
	var v := VBoxContainer.new()
	v.add_child(HSeparator.new())
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	v.add_child(l)
	return v


func _reach_table() -> String:
	var s := "Inke jump reach (edge→edge, measured):\n"
	for k in ["walk", "run", "double", "long"]:
		s += "  %s: %.1fm flat · %.1fm up 2m · apex %.1fm\n" % [JumpArcs.LABELS[k], JumpArcs.reach_at(k, 0.0), maxf(JumpArcs.reach_at(k, 2.0), 0.0), JumpArcs.apex(k)]
	return s


func _status(t: String) -> void:
	if _ui.has("status"):
		_ui["status"].text = t


func _refresh_gizmos() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	for n in root.get_tree().get_nodes_in_group("LevelKitPlatform"):
		if n is Node3D:
			(n as Node3D).update_gizmos()


# ===========================================================================
# GROUND QUERIES
# Editor physics doesn't reliably expose Terrain's HeightMapShape to
# raycasts, so terrain is sampled ANALYTICALLY (Terrain.get_height) and
# physics is used for everything else (platforms, floors, rooms...).
# ===========================================================================

func _terrains() -> Array:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return []
	var out := []
	for t in root.find_children("*", "Terrain", true, false):
		if t is Terrain and (t as Terrain).is_inside_tree():
			out.append(t)
	if root is Terrain:
		out.append(root)
	return out


func _terrain_height_at(p: Vector3, below_y: float = INF) -> Dictionary:
	"""Highest terrain surface under XZ p that is at or below below_y."""
	var best := {}
	for t in _terrains():
		if not t.contains_xz(p) or t._heights.is_empty():
			continue
		var h: float = t.get_height(p)
		if h <= below_y and (best.is_empty() or h > best.y):
			best = {"y": h, "terrain": t}
	return best


func _ground_below(p: Vector3, exclude: Array = [], from_above: float = 300.0) -> Dictionary:
	"""{y, collider} of the first surface found straight down from
	p + from_above. Combines physics with analytic terrain."""
	var root := get_editor_interface().get_edited_scene_root() as Node3D
	var top := p.y + from_above
	var best := {}
	if root:
		var space := root.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, p.y - 2000.0, p.z))
		q.collide_with_areas = false
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = {"y": hit.position.y, "collider": hit.collider}
	var th := _terrain_height_at(p, top)
	if not th.is_empty() and (best.is_empty() or th.y > best.y):
		best = {"y": th.y, "collider": th.terrain}
	return best


func _ray_terrain(from: Vector3, dir: Vector3) -> Dictionary:
	"""March a camera ray against all terrains (analytic heights)."""
	var best := {}
	for t in _terrains():
		if t._heights.is_empty():
			continue
		var step: float = maxf(minf(t.size.x / t.resolution, t.size.y / t.resolution) * 0.5, 0.25)
		var prev_above := true
		var dist := 0.0
		var last := from
		while dist < 4000.0:
			var p := from + dir * dist
			if t.contains_xz(p):
				var above: bool = p.y > t.get_height(p)
				if not above and prev_above and dist > 0.0:
					# refine between last and p
					var a := last; var b := p
					for _i in range(12):
						var m := (a + b) * 0.5
						if m.y > t.get_height(m): a = m
						else: b = m
					var hit_d: float = from.distance_to(b)
					if best.is_empty() or hit_d < best.dist:
						best = {"position": b, "normal": _terrain_normal(t, b), "collider": t, "dist": hit_d}
					break
				prev_above = above
			last = p
			dist += step
	return best


func _terrain_normal(t: Terrain, p: Vector3) -> Vector3:
	var e := 0.5
	var hx := t.get_height(p + Vector3(e, 0, 0)) - t.get_height(p - Vector3(e, 0, 0))
	var hz := t.get_height(p + Vector3(0, 0, e)) - t.get_height(p - Vector3(0, 0, e))
	return Vector3(-hx, 2.0 * e, -hz).normalized()


# ===========================================================================
# PLACEMENT
# ===========================================================================

func _start_place(item: Dictionary, button: Button) -> void:
	_end_brush()
	if _place_item == item:
		_cancel_place()
		return
	_cancel_place()
	_place_item = item
	button.button_pressed = true
	_ghost = _make_instance(item)
	if _ghost:
		_ghost.process_mode = Node.PROCESS_MODE_DISABLED
		var root := get_editor_interface().get_edited_scene_root()
		if root:
			root.add_child(_ghost)   # no owner: never saved
			_ghost.visible = false
	_status("Placing %s - click the 3D view. Right-click/Esc to stop." % item.name)


func _cancel_place() -> void:
	if _place_item.has("button") and is_instance_valid(_place_item.button):
		_place_item.button.button_pressed = false
	_place_item = {}
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_status("Pick something, then click in the 3D view.")


func _make_instance(item: Dictionary) -> Node3D:
	var n: Node3D
	if item.kind == "platform":
		n = PlatformScript.new()
		n.name = item.name.replace(" ", "")
	else:
		var ps: PackedScene = load(item.path)
		if ps == null:
			return null
		n = ps.instantiate()
	for k in item.get("props", {}):
		n.set(k, item.props[k])
	return n


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	# Terrain brushes
	if _brush_mode != "":
		return _brush_input(camera, event)
	# Placement
	if not _place_item.is_empty():
		if event is InputEventMouseMotion:
			_update_ghost(camera, event.position, event.shift_pressed)
			return AFTER_GUI_INPUT_PASS
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_update_ghost(camera, event.position, event.shift_pressed)
				if _ghost_ok:
					_commit_place()
				return AFTER_GUI_INPUT_STOP
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_place()
				return AFTER_GUI_INPUT_STOP
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_place()
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS
	# Hotkeys on selection
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P and event.ctrl_pressed and event.shift_pressed:
			_play_from_here()
			return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_D and not event.ctrl_pressed and not event.alt_pressed:
			if _duplicate_forward():
				return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_G and event.alt_pressed:
			if _drop_selection():
				return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _raycast(camera: Camera3D, mouse: Vector2, exclude: Array = []) -> Dictionary:
	var root := get_editor_interface().get_edited_scene_root() as Node3D
	if root == null:
		return {}
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var space := root.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 5000.0)
	params.collide_with_areas = false
	params.exclude = exclude
	var hit := space.intersect_ray(params)
	var th := _ray_terrain(from, dir)
	if not th.is_empty() and (hit.is_empty() or from.distance_to(th.position) < from.distance_to(hit.position)):
		hit = th
	if not hit.is_empty():
		return hit
	# Nothing under the cursor: fall back to the y=0 plane so you can place
	# into an empty scene.
	var pl := Plane(Vector3.UP, 0.0)
	var p = pl.intersects_ray(from, dir)
	if p != null:
		return {"position": p, "normal": Vector3.UP, "collider": null}
	return {}


func _update_ghost(camera: Camera3D, mouse: Vector2, stack: bool) -> void:
	_ghost_ok = false
	if _ghost == null or not is_instance_valid(_ghost):
		return
	var ex := []
	if _ghost is CollisionObject3D:
		ex.append((_ghost as CollisionObject3D).get_rid())
	var hit := _raycast(camera, mouse, ex)
	if hit.is_empty():
		_ghost.visible = false
		return
	var pos: Vector3 = hit.position
	var nrm: Vector3 = hit.normal
	if stack and hit.collider is Node3D:
		# Stack on the top of whatever was clicked
		var target := hit.collider as Node3D
		var top := target.global_position.y
		if target is Platform:
			top = (target as Platform).top_y()
		else:
			var bb := _world_aabb(target)
			if bb.size != Vector3.ZERO:
				top = bb.end.y
		pos.y = top
		nrm = Vector3.UP
	if grid_snap > 0.0:
		pos.x = snappedf(pos.x, grid_snap)
		pos.z = snappedf(pos.z, grid_snap)
	var basis := Basis()
	if align_to_surface and nrm.dot(Vector3.UP) > 0.2:
		var x := nrm.cross(Vector3.FORWARD).normalized()
		if x.length() < 0.1:
			x = Vector3.RIGHT
		basis = Basis(x, nrm, x.cross(nrm)).orthonormalized()
	var lift: float = _place_item.get("lift", 0.0)
	_ghost_xf = Transform3D(basis, pos + nrm * lift)
	_ghost.global_transform = _ghost_xf
	_ghost.visible = true
	_ghost_ok = true


func _commit_place() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var n := _make_instance(_place_item)
	if n == null:
		return
	var xf := _ghost_xf
	if random_yaw:
		xf.basis = xf.basis.rotated(xf.basis.y.normalized(), randf() * TAU)
	var parent := _placement_parent(root, _place_item.group)
	n.name = _unique_name(parent, _place_item.name.replace(" ", ""))
	var ur := get_undo_redo()
	ur.create_action("Level Kit: place " + _place_item.name)
	ur.add_do_method(parent, "add_child", n, true)
	ur.add_do_method(n, "set_owner", root)
	ur.add_do_property(n, "global_transform", xf)
	ur.add_do_reference(n)
	ur.add_undo_method(parent, "remove_child", n)
	ur.commit_action()
	_status("Placed %s. Keep clicking, or right-click/Esc to stop." % _place_item.name)


func _placement_parent(root: Node, group: String) -> Node:
	"""Keep levels tidy: everything lands in a folder node per category."""
	var folder := "LK_" + group.replace(" ", "")
	var existing := root.get_node_or_null(folder)
	if existing:
		return existing
	var f := Node3D.new()
	f.name = folder
	root.add_child(f, true)
	f.owner = root
	return f


func _unique_name(parent: Node, base: String) -> String:
	var i := 1
	var nm := base
	while parent.has_node(nm):
		i += 1
		nm = "%s%d" % [base, i]
	return nm


func _world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if c is VisualInstance3D:
			var vi := c as VisualInstance3D
			var bb := vi.global_transform * vi.get_aabb()
			if first:
				out = bb; first = false
			else:
				out = out.merge(bb)
	return out


# --- selection hotkeys ---

func _duplicate_forward() -> bool:
	"""D: copy the selected node(s) one comfortable run jump forward."""
	var sel := get_editor_interface().get_selection().get_selected_nodes()
	if sel.is_empty():
		return false
	var root := get_editor_interface().get_edited_scene_root()
	var ur := get_undo_redo()
	ur.create_action("Level Kit: duplicate forward")
	var new_sel := []
	for s in sel:
		if not (s is Node3D) or s == root:
			continue
		var n3 := s as Node3D
		var dup := n3.duplicate()
		var span := 0.0
		if n3 is Platform:
			span = (n3 as Platform).size.z
		var gap := Gen.safe_gap("run", 0.0, 0.35, maxf(span, 4.0))
		var fwd := -n3.global_transform.basis.z.normalized()
		var xf := n3.global_transform
		xf.origin += fwd * (span + gap)
		ur.add_do_method(n3.get_parent(), "add_child", dup, true)
		ur.add_do_method(dup, "set_owner", root)
		ur.add_do_property(dup, "global_transform", xf)
		ur.add_do_reference(dup)
		ur.add_undo_method(n3.get_parent(), "remove_child", dup)
		new_sel.append(dup)
	ur.commit_action()
	var es := get_editor_interface().get_selection()
	es.clear()
	for n in new_sel:
		es.add_node(n)
	_status("Duplicated forward by a run-jump gap. Press D again to keep going.")
	return true


func _drop_selection() -> bool:
	"""Alt+G: drop selected nodes straight down onto whatever is below."""
	var sel := get_editor_interface().get_selection().get_selected_nodes()
	if sel.is_empty():
		return false
	var ur := get_undo_redo()
	ur.create_action("Level Kit: drop to ground")
	for s in sel:
		if not (s is Node3D):
			continue
		var n3 := s as Node3D
		var ex := []
		for c in [n3] + n3.find_children("*", "CollisionObject3D", true, false):
			if c is CollisionObject3D:
				ex.append((c as CollisionObject3D).get_rid())
		# from_above small: drop onto what's BELOW, not a roof above
		var g := _ground_below(n3.global_position + Vector3.UP * 0.5, ex, 0.0)
		if g.is_empty():
			continue
		var p := n3.global_position
		var bottom_offset := 0.0
		if n3 is Platform:
			bottom_offset = (n3 as Platform).size.y + (n3 as Platform).pillar_depth
		else:
			for item in CATALOG:
				if item.get("path", "") != "" and item.path == n3.scene_file_path:
					bottom_offset = item.get("lift", 0.0)
					break
		p.y = g.y + bottom_offset
		ur.add_do_property(n3, "global_position", p)
		ur.add_undo_property(n3, "global_position", n3.global_position)
	ur.commit_action()
	return true


# ===========================================================================
# COURSE GENERATORS
# ===========================================================================

func _viewport_focus() -> Vector3:
	"""Point on the ground in the centre of the 3D viewport."""
	var vp := get_editor_interface().get_editor_viewport_3d(0)
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var hit := _raycast(cam, vp.size * 0.5)
	if hit.is_empty():
		return cam.global_position + -cam.global_transform.basis.z * 20.0
	return hit.position


func _generate(kind: String) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null or not (root is Node3D):
		_status("Open a 3D scene first.")
		return
	var moves := ["walk", "run", "double", "long"]
	var move: String = moves[_ui["move"].selected]
	var diff: float = _ui["diff"].value
	var count := int(_ui["count"].value)
	var rise: float = _ui["rise"].value
	var seed_v := randi()
	var specs := []
	match kind:
		"stones": specs = Gen.stepping_stones(count, move, diff, rise, 5.0, 0.35, seed_v)
		"spiral": specs = Gen.spiral_tower(count, move, diff, 9.0, maxf(rise, 1.0), 4.0)
		"climb": specs = Gen.staircase_climb(count, clampf(absf(rise), 0.5, JumpArcs.apex("run") * 0.75), 4.0, 8.0)
		"islands": specs = Gen.floating_islands(count, 30.0 + count * 3.0, 0.0, 8.0, seed_v)
		"gauntlet": specs = Gen.gauntlet(maxi(count / 2, 2), seed_v)
	var origin := _viewport_focus()
	var parent_name := _unique_name(root, "Course_" + kind.capitalize())
	var course := Node3D.new()
	course.name = parent_name
	var i := 0
	for sp in specs:
		var p := PlatformScript.new()
		p.name = "Goal" if sp.get("goal", false) else ("Column" if sp.get("column", false) else "P%02d" % i)
		p.shape = sp.shape
		p.size = sp.size
		p.look = sp.look
		p.rise = sp.get("rise", 0.0)
		p.segments = sp.get("segments", 8)
		p.pillar_depth = sp.get("pillar", 0.0)
		p.position = sp.pos
		p.rotation.y = sp.get("yaw", 0.0)
		course.add_child(p)
		i += 1
	course.position = origin
	var ur := get_undo_redo()
	ur.create_action("Level Kit: generate " + kind)
	ur.add_do_method(root, "add_child", course, true)
	ur.add_do_method(self, "_own_recursive", course, root)
	ur.add_do_reference(course)
	ur.add_undo_method(root, "remove_child", course)
	ur.commit_action()
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(course)
	_status("Generated %d platforms (%s, %s). Move the course node to reposition the whole thing." % [specs.size(), kind, JumpArcs.LABELS[move]])


func _own_recursive(n: Node, owner_node: Node) -> void:
	n.owner = owner_node
	for c in n.get_children():
		if not str(c.name).begins_with("_"):
			_own_recursive(c, owner_node)


# ===========================================================================
# TERRAIN BRUSHES
# ===========================================================================

func _selected_terrain() -> Node:
	for s in get_editor_interface().get_selection().get_selected_nodes():
		if s is Terrain:
			return s
	return null


func _start_brush(mode: String, button: Button) -> void:
	_cancel_place()
	if _brush_mode == mode:
		_end_brush()
		return
	_end_brush()
	var t := _selected_terrain()
	if t == null:
		button.button_pressed = false
		_status("Select a Terrain node first (in the Scene tree), then pick a brush.")
		return
	_brush_terrain = t
	_brush_mode = mode
	button.button_pressed = true
	_status("%s brush on %s - drag in the 3D view. Click the button again or Esc to stop." % [mode.capitalize(), t.name])


func _end_brush() -> void:
	if _brush_mode != "" and _ui.has("brush_" + _brush_mode):
		_ui["brush_" + _brush_mode].button_pressed = false
	_stop_stroke()
	_brush_mode = ""
	_brush_terrain = null
	if _brush_ring and is_instance_valid(_brush_ring):
		_brush_ring.queue_free()
	_brush_ring = null


func _brush_input(camera: Camera3D, event: InputEvent) -> int:
	if _brush_terrain == null or not is_instance_valid(_brush_terrain):
		_end_brush()
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_end_brush()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouse:
		var hit := _raycast(camera, event.position)
		_brush_has_hit = not hit.is_empty() and _brush_terrain.contains_xz(hit.position)
		if _brush_has_hit:
			_brush_hit = hit.position
		_update_ring()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _brush_has_hit:
			_brushing = true
			_brush_terrain._ensure_paint_grid()
			_brush_before = _brush_terrain.paint_data.duplicate()
			_flatten_target = _brush_terrain.to_local(_brush_hit).y
			_apply_brush(0.06)
			return AFTER_GUI_INPUT_STOP
		elif not event.pressed and _brushing:
			_stop_stroke()
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _brushing:
		if _brush_has_hit:
			_apply_brush(0.03)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _apply_brush(dt: float) -> void:
	var t: Terrain = _brush_terrain
	var radius: float = _ui["bsize"].value
	var strength: float = _ui["bstr"].value
	var n: int = t.resolution
	var w1 := n + 1
	var step := Vector2(t.size.x / n, t.size.y / n)
	var local := t.to_local(_brush_hit)
	var cx := (local.x + t.size.x * 0.5) / step.x
	var cz := (local.z + t.size.y * 0.5) / step.y
	var rx := int(ceilf(radius / step.x)) + 1
	var rz := int(ceilf(radius / step.y)) + 1
	var pd: PackedFloat32Array = t.paint_data
	var base := PackedFloat32Array()
	if _brush_mode in ["flatten", "smooth", "plateau"]:
		base = t._heights   # current final surface (noise + paint)
	for iz in range(maxi(int(cz) - rz, 0), mini(int(cz) + rz, n) + 1):
		for ix in range(maxi(int(cx) - rx, 0), mini(int(cx) + rx, n) + 1):
			var d := Vector2((ix - cx) * step.x, (iz - cz) * step.y).length()
			if d >= radius:
				continue
			var fall := 0.5 + 0.5 * cos(PI * d / radius)
			var i := iz * w1 + ix
			match _brush_mode:
				"raise":
					pd[i] += strength * dt * fall
				"lower":
					pd[i] -= strength * dt * fall
				"flatten":
					if base.size() == pd.size():
						pd[i] += (_flatten_target - base[i]) * fall * 0.5
				"plateau":
					# Flat-topped mesa: hard flat core at the click height +
					# strength*0.4 m, steep-ish soft rim. Only ever RAISES
					# (dragging across lower ground builds a wider mesa).
					if base.size() == pd.size():
						var target := _flatten_target + strength * 0.4
						var k := 1.0 if d < radius * 0.7 else smoothstep(radius, radius * 0.7, d)
						var want := lerpf(base[i], target, k)
						if want > base[i]:
							pd[i] += want - base[i]
				"smooth":
					if base.size() == pd.size():
						var avg := 0.0
						var cnt := 0
						for oz in range(-1, 2):
							for ox in range(-1, 2):
								var jx := clampi(ix + ox, 0, n)
								var jz := clampi(iz + oz, 0, n)
								avg += base[jz * w1 + jx]
								cnt += 1
						avg /= cnt
						pd[i] += (avg - base[i]) * 0.5 * fall
	t.paint_data = pd
	t._rebuild()   # immediate so flatten/smooth read the new surface next dab


func _stop_stroke() -> void:
	if not _brushing:
		return
	_brushing = false
	var t: Terrain = _brush_terrain
	if t == null or not is_instance_valid(t):
		return
	var after: PackedFloat32Array = t.paint_data.duplicate()
	if after == _brush_before:
		return
	var ur := get_undo_redo()
	ur.create_action("Level Kit: terrain " + _brush_mode, UndoRedo.MERGE_DISABLE, t)
	ur.add_do_property(t, "paint_data", after)
	ur.add_undo_property(t, "paint_data", _brush_before)
	ur.add_do_method(t, "_request_rebuild")
	ur.add_undo_method(t, "_request_rebuild")
	ur.commit_action(false)


func _update_ring() -> void:
	if not _brush_has_hit:
		if _brush_ring and is_instance_valid(_brush_ring):
			_brush_ring.visible = false
		return
	if _brush_ring == null or not is_instance_valid(_brush_ring):
		_brush_ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.95; tor.outer_radius = 1.0; tor.rings = 48; tor.ring_segments = 4
		_brush_ring.mesh = tor
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		_brush_ring.material_override = m
		_brush_ring.top_level = true
		_brush_terrain.add_child(_brush_ring)
	var col := {"raise": Color(0.3, 1, 0.5), "lower": Color(1, 0.4, 0.3), "flatten": Color(0.4, 0.8, 1), "smooth": Color(1, 1, 1), "plateau": Color(1, 0.85, 0.3)}.get(_brush_mode, Color.WHITE)
	col.a = 0.8
	(_brush_ring.material_override as StandardMaterial3D).albedo_color = col
	var r: float = _ui["bsize"].value
	_brush_ring.scale = Vector3(r, 1, r)
	_brush_ring.global_position = _brush_hit + Vector3.UP * 0.2
	_brush_ring.visible = true


func _terrain_shape(kind: String) -> void:
	var t := _selected_terrain() as Terrain
	if t == null:
		_status("Select a Terrain node first.")
		return
	t._ensure_paint_grid()
	var before: PackedFloat32Array = t.paint_data.duplicate()
	var pd: PackedFloat32Array = t.paint_data.duplicate()
	var n: int = t.resolution
	var w1 := n + 1
	var focus := _viewport_focus()
	var c := Vector2.ZERO
	if t.contains_xz(focus):
		var l := t.to_local(focus)
		c = Vector2(l.x, l.z)
	var half := t.size * 0.5
	var big := minf(t.size.x, t.size.y)
	for iz in range(w1):
		for ix in range(w1):
			var x := -half.x + ix * t.size.x / n
			var z := -half.y + iz * t.size.y / n
			var i := iz * w1 + ix
			var d := Vector2(x, z).distance_to(c)
			match kind:
				"clear":
					pd[i] = 0.0
				"island":
					# raised plateau with beaches dropping off at the rim
					var r := big * 0.38
					var k := 1.0 - smoothstep(r * 0.7, r, d)
					var edge := Vector2(absf(x) / half.x, absf(z) / half.y)
					var rim := smoothstep(0.75, 1.0, maxf(edge.x, edge.y))
					pd[i] += k * 6.0 - rim * 6.0
				"mountain":
					var r2 := big * 0.22
					pd[i] += maxf(0.0, 1.0 - d / r2) ** 1.6 * 40.0
				"valley":
					var r3 := big * 0.3
					pd[i] -= (1.0 - smoothstep(0.0, r3, d)) * 8.0
				"crater":
					var r4 := big * 0.15
					var ring := exp(-pow((d - r4) / (r4 * 0.35), 2.0))
					pd[i] += ring * 10.0 - (1.0 - smoothstep(0.0, r4, d)) * 6.0
				"ridge":
					var dist := absf((x - c.x) * 0.7 + (z - c.y) * 0.7) / 0.99
					var along := absf(-(x - c.x) * 0.7 + (z - c.y) * 0.7)
					var len := big * 0.35
					pd[i] += (1.0 - smoothstep(0.0, big * 0.06, dist)) * (1.0 - smoothstep(len * 0.7, len, along)) * 14.0
	var ur := get_undo_redo()
	ur.create_action("Level Kit: terrain " + kind, UndoRedo.MERGE_DISABLE, t)
	ur.add_do_property(t, "paint_data", pd)
	ur.add_undo_property(t, "paint_data", before)
	ur.add_do_method(t, "_request_rebuild")
	ur.add_undo_method(t, "_request_rebuild")
	ur.commit_action()
	_status("Stamped %s on %s (Ctrl+Z to undo)." % [kind, t.name])


# ===========================================================================
# PLAY FROM HERE
# ===========================================================================

func _play_from_here() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null or root.scene_file_path == "":
		_status("Save the scene first (it needs a file to run).")
		return
	var vp := get_editor_interface().get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		_status("No 3D viewport camera.")
		return
	var hit := _raycast(cam, vp.size * 0.5)
	var spawn: Vector3 = hit.position if not hit.is_empty() else cam.global_position
	spawn += Vector3.UP * 1.0
	var fwd := -cam.global_transform.basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	var data := {"scene": root.scene_file_path, "x": spawn.x, "y": spawn.y, "z": spawn.z, "yaw": yaw, "time": Time.get_unix_time_from_system(), "all_upgrades": true}
	var f := FileAccess.open("user://level_kit_play_here.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	get_editor_interface().save_scene()
	get_editor_interface().play_current_scene()
	_status("Playing from (%.0f, %.0f, %.0f) with all upgrades." % [spawn.x, spawn.y, spawn.z])


# ===========================================================================
# VALIDATOR
# ===========================================================================

func _validate() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	var out: RichTextLabel = _ui["report"]
	out.clear()
	if root == null:
		out.append_text("[color=orange]Open a scene first.[/color]")
		return
	var errors := 0
	var warns := 0
	var lines := []
	var all := root.find_children("*", "", true, false)
	all.append(root)
	# Player
	var players := all.filter(func(n): return n.is_in_group("Player") or (n.scene_file_path.ends_with("inke.tscn") or n.scene_file_path.ends_with("inke_no_hu3.tscn")))
	if players.is_empty():
		lines.append("[color=red]✖ No Inke in the scene.[/color] Place scenes/characters/Player/inke.tscn.")
		errors += 1
	# Reset plane
	var resets := all.filter(func(n): return n.scene_file_path.ends_with("reset_plane.tscn"))
	var waters := all.filter(func(n): return n.scene_file_path.ends_with("water_zone.tscn"))
	if resets.is_empty() and waters.is_empty():
		lines.append("[color=orange]⚠ No Reset Plane.[/color] Falling off the level only ends at death_y. Level Kit ▸ Level flow ▸ Reset Plane.")
		warns += 1
	# Checkpoint ids
	var ids := {}
	for n in all:
		if n.scene_file_path.ends_with("checkpoint.tscn"):
			var cid := str(n.get("checkpoint_id"))
			if cid != "" and ids.has(cid):
				lines.append("[color=orange]⚠ Duplicate checkpoint_id '%s'[/color] (%s, %s)" % [cid, ids[cid], n.name])
				warns += 1
			ids[cid] = n.name
	# Platform reachability (graph from the player's start)
	var plats := []
	for n in all:
		if n is Platform:
			plats.append(n)
	if plats.size() > 0 and not players.is_empty():
		var start: Vector3 = players[0].global_position
		var reached := {}
		var frontier := []
		# Seed: platforms the player can step/jump onto from their start
		for p in plats:
			var flat := Vector2(start.x - p.global_position.x, start.z - p.global_position.z)
			var bb: AABB = p.local_bounds()
			var gap := maxf(0.0, flat.length() - maxf(bb.size.x, bb.size.z) * 0.5)
			if JumpArcs.best_move(gap, p.top_y() - start.y) != "" or p.top_y() <= start.y + 0.5:
				reached[p] = true
				frontier.append(p)
		while not frontier.is_empty():
			var a: Platform = frontier.pop_back()
			for b in plats:
				if reached.has(b):
					continue
				var g := Gizmo._edge_gap(a, b)
				if JumpArcs.best_move(g, b.top_y() - a.top_y()) != "" or (b.top_y() < a.top_y() and g < JumpArcs.reach_at("long", b.top_y() - a.top_y())):
					reached[b] = true
					frontier.append(b)
		for p in plats:
			if not reached.has(p):
				lines.append("[color=orange]⚠ Platform '%s' may be unreachable[/color] from Inke's start with any move (gap/height too big; grapples/ropes not counted)." % root.get_path_to(p))
				warns += 1
	# Floating / buried pickups
	for n in all:
		var sp: String = n.scene_file_path
		if not (sp.contains("Collectibles") or sp.contains("Breakables")):
			continue
		if not (n is Node3D):
			continue
		var p3 := (n as Node3D).global_position
		var ex := []
		for c in [n] + n.find_children("*", "CollisionObject3D", true, false):
			if c is CollisionObject3D:
				ex.append((c as CollisionObject3D).get_rid())
		var g := _ground_below(p3, ex, 300.0)
		if g.is_empty():
			lines.append("[color=orange]⚠ '%s' has no ground under it[/color] (over the void - falls forever)." % n.name)
			warns += 1
			continue
		var gy: float = g.y
		if gy > p3.y + 0.4 and g.collider is Terrain:
			lines.append("[color=orange]⚠ '%s' is buried %.1fm under the terrain.[/color] Select it and press Alt+G." % [n.name, gy - p3.y])
			warns += 1
		elif gy <= p3.y + 0.4 and p3.y - gy > 8.0 and sp.contains("Breakables"):
			lines.append("[color=yellow]• '%s' is %.0fm above the ground[/color] - crates fall when the level starts." % [n.name, p3.y - gy])
	var head := "[b]Validate:[/b] %d error(s), %d warning(s)" % [errors, warns]
	if errors == 0 and warns == 0:
		head += "  [color=lime]✔ looks good[/color]"
	out.append_text(head + "\n" + "\n".join(lines))
