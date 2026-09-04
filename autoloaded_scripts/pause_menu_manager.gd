extends Node

## Pause screen (Start / Esc). Shows: current level, health, gears, CRED,
## Ink Wisp progress, paint, upgrades owned, and controls.
## Built entirely in code so it works in every scene.

var paused: bool = false
var canvas_layer: CanvasLayer = null
var root_panel: Panel = null

# Dynamic labels refreshed on open
var level_label: Label
var health_label: Label
var gears_label: Label
var cred_label: Label
var wisp_label: Label
var paint_label: Label
var upgrades_label: Label
var objective_label: Label

const COLOR_BG = Color(0.07, 0.07, 0.12, 0.92)
const COLOR_ACCENT = Color(0.3, 0.75, 1.0)
const COLOR_TEXT = Color(0.92, 0.92, 0.97)
const COLOR_DIM = Color(0.65, 0.65, 0.75)
const COLOR_GOOD = Color(0.35, 0.95, 0.5)
const COLOR_WARN = Color(1.0, 0.85, 0.3)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func _input(event: InputEvent):
	if event.is_action_pressed("start") or event.is_action_pressed("ui_cancel"):
		# Don't fight the merchant shop or dialogue for the pause button
		if _is_other_ui_active():
			return
		toggle_pause()
		get_viewport().set_input_as_handled()

func _is_other_ui_active() -> bool:
	# No player in the scene = nothing to pause. Blocks the pause menu on
	# the startup logos, main menu, and any other player-less screen.
	if get_tree().get_nodes_in_group("Player").is_empty():
		return true
	# Dialogue open?
	var dm = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("is_dialogue_active") and dm.is_dialogue_active():
		return true
	# Merchant shop pauses the tree itself; if tree is paused but not by us, stay out
	if get_tree().paused and not paused:
		return true
	return false

func toggle_pause():
	if paused:
		close_menu()
	else:
		open_menu()

func open_menu():
	paused = true
	get_tree().paused = true
	_refresh_stats()
	canvas_layer.visible = true
	# Free the mouse so you can read/quit
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_menu():
	paused = false
	get_tree().paused = false
	canvas_layer.visible = false
	# Give the mouse back to the game (matches camera controller behavior)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui():
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "PauseMenuCanvas"
	canvas_layer.layer = 120
	canvas_layer.visible = false
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas_layer)
	
	# Dim the whole screen behind the panel
	var dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.55)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(dimmer)
	
	# Main panel, centered
	root_panel = Panel.new()
	root_panel.set_anchors_preset(Control.PRESET_CENTER)
	root_panel.custom_minimum_size = Vector2(760, 720)
	root_panel.position = Vector2(-380, -360)
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	root_panel.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(root_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	root_panel.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	level_label = _add_stat_line(vbox, 24, COLOR_DIM)
	vbox.add_child(_separator())
	
	_add_section_header(vbox, "STATUS")
	health_label = _add_stat_line(vbox, 26, COLOR_TEXT)
	paint_label = _add_stat_line(vbox, 22, COLOR_TEXT)
	
	_add_section_header(vbox, "COLLECTABLES")
	gears_label = _add_stat_line(vbox, 22, COLOR_TEXT)
	cred_label = _add_stat_line(vbox, 22, COLOR_TEXT)
	wisp_label = _add_stat_line(vbox, 22, COLOR_TEXT)
	objective_label = _add_stat_line(vbox, 18, COLOR_WARN)
	
	_add_section_header(vbox, "UPGRADES")
	upgrades_label = _add_stat_line(vbox, 20, COLOR_TEXT)
	upgrades_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	vbox.add_child(_separator())
	
	# Controls / hints
	var hints = Label.new()
	hints.text = "[Esc / Start]  Resume        [Hold F1]  Quit Game"
	hints.add_theme_font_size_override("font_size", 18)
	hints.add_theme_color_override("font_color", COLOR_DIM)
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hints)
	
	# Resume button (mouse/touch friendly)
	var resume_btn = Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(220, 48)
	resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume_btn.add_theme_font_size_override("font_size", 22)
	resume_btn.pressed.connect(close_menu)
	vbox.add_child(resume_btn)

func _add_section_header(parent: Control, text: String):
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", COLOR_ACCENT)
	parent.add_child(lbl)

func _add_stat_line(parent: Control, size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl

func _separator() -> HSeparator:
	var sep = HSeparator.new()
	return sep

# ---------------------------------------------------------------------------
# Stats refresh
# ---------------------------------------------------------------------------

func _refresh_stats():
	var gm = get_node_or_null("/root/GameManager")
	var pm = get_node_or_null("/root/PaintManager")
	
	# Level name from the current scene
	var scene = get_tree().current_scene
	var level_name = "Unknown"
	if scene:
		level_name = String(scene.name).replace("_", " ")
	level_label.text = "Level:  " + level_name
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	if gm:
		# Health as hearts
		var hp = gm.get_player_health()
		var max_hp = gm.get_player_max_health()
		var hearts = ""
		for i in range(max_hp):
			hearts += "\u2665 " if i < hp else "\u2661 "
		health_label.text = "Health:  " + hearts + " (%d / %d)" % [hp, max_hp]
		
		gears_label.text = "\u2699 Gears:  %d" % gm.get_gear_count()
		cred_label.text = "\u2726 CRED:  %d" % gm.get_CRED_count()
		
		# Wisp progress
		var wp = gm.get_wisp_progress()
		if wp.total > 0:
			wisp_label.text = "\u25cf Spray Cans:  %d / %d" % [wp.collected, wp.total]
			if wp.collected >= wp.total:
				objective_label.text = "All spray cans found! Your CRED reward has appeared."
			else:
				objective_label.text = "Find all %d Ink Wisps in this level to earn a CRED." % wp.total
		else:
			wisp_label.text = "\u25cf Spray Cans:  none in this level"
			objective_label.text = ""
		
		# Upgrades owned
		var owned: Array[String] = []
		if gm.double_jump_purchased: owned.append("Double Jump")
		if gm.wall_jump_purchased: owned.append("Wall Jump")
		if gm.dash_purchased: owned.append("Dash")
		if gm.speed_upgrade_purchased: owned.append("Speed+")
		if gm.health_upgrade_purchased: owned.append("Health+")
		if gm.damage_upgrade_purchased: owned.append("Damage+")
		upgrades_label.text = ", ".join(owned) if owned.size() > 0 else "None yet - visit the Merchant!"
	
	# Paint
	if pm and pm.has_method("get_paint_amount"):
		var paint_type_name = ""
		if "paint_names" in pm and "current_paint" in pm:
			paint_type_name = "  (%s)" % str(pm.paint_names.get(pm.current_paint, ""))
		paint_label.text = "Paint:  %d / %d%s" % [pm.get_paint_amount(), pm.get_max_paint_amount(), paint_type_name]
		paint_label.visible = true
	else:
		paint_label.visible = false
