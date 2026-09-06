extends Node

## Pause screen (Start / Esc) - graffiti/punk themed (PunkTheme).
## Two tabs: STATS (level, health, gears, CRED, wisps, paint, upgrades)
## and CONTROLS (live-rebindable input map via InputManager).
## Built entirely in code so it works in every scene.

var paused: bool = false
var canvas_layer: CanvasLayer = null
var root_panel: Panel = null

# Tabs
var stats_page: Control
var controls_page: Control
var tab_stats_btn: Button
var tab_controls_btn: Button
var current_tab: String = "stats"

# Dynamic labels refreshed on open
var level_label: Label
var health_label: Label
var gears_label: Label
var cred_label: Label
var wisp_label: Label
var paint_label: Label
var upgrades_label: Label
var objective_label: Label
var hints_label: Label

# Rebind state
var rebind_rows: Array = []        # [{action, name_lbl, kb_btn, pad_btn}]
var listening_action: String = ""  # Action waiting for a new binding
var listening_device: String = ""  # "kb" | "pad"
var listening_btn: Button = null

const COLOR_TEXT = Color(0.92, 0.92, 0.97)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func _input(event: InputEvent):
	# REBIND CAPTURE MODE: swallow everything until a valid press arrives
	if listening_action != "":
		_handle_rebind_capture(event)
		get_viewport().set_input_as_handled()
		return
	
	if event.is_action_pressed("start") or event.is_action_pressed("ui_cancel"):
		# Don't fight the merchant shop or dialogue for the pause button
		if _is_other_ui_active():
			return
		toggle_pause()
		get_viewport().set_input_as_handled()

func _handle_rebind_capture(event: InputEvent):
	# ESC cancels the capture
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_stop_listening()
		return
	var im = get_node_or_null("/root/InputManager")
	if not im:
		_stop_listening()
		return
	# Only accept events matching the column being rebound
	var is_pad_event = event is InputEventJoypadButton or event is InputEventJoypadMotion
	var is_kb_event = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if listening_device == "pad" and not is_pad_event:
		return
	if listening_device == "kb" and not is_kb_event:
		return
	if is_pad_event:
		if event is InputEventJoypadButton and not event.pressed:
			return
		if event is InputEventJoypadMotion and absf(event.axis_value) < 0.6:
			return
	if im.apply_rebind(listening_action, event):
		_stop_listening()
		_refresh_bindings()

func _stop_listening():
	if listening_btn and is_instance_valid(listening_btn):
		listening_btn.text = "..."
	listening_action = ""
	listening_device = ""
	listening_btn = null
	_refresh_bindings()

func _is_other_ui_active() -> bool:
	if get_tree().get_nodes_in_group("Player").is_empty():
		return true
	var dm = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("is_dialogue_active") and dm.is_dialogue_active():
		return true
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
	_refresh_bindings()
	_show_tab("stats")
	canvas_layer.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_menu():
	if listening_action != "":
		_stop_listening()
	paused = false
	get_tree().paused = false
	canvas_layer.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ---------------------------------------------------------------------------
# UI construction - PUNK
# ---------------------------------------------------------------------------

func _build_ui():
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "PauseMenuCanvas"
	canvas_layer.layer = 120
	canvas_layer.visible = false
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas_layer)
	
	var dimmer = ColorRect.new()
	dimmer.color = Color(0.02, 0.01, 0.04, 0.72)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(dimmer)
	
	# Main panel - slapped-on asphalt sticker
	root_panel = Panel.new()
	root_panel.set_anchors_preset(Control.PRESET_CENTER)
	root_panel.custom_minimum_size = Vector2(780, 680)
	root_panel.position = Vector2(-390, -340)
	var style = PunkTheme.panel(PunkTheme.CYAN, 0.04)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	root_panel.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(root_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	root_panel.add_child(vbox)
	
	# Title - stencil spray
	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PunkTheme.style_headline(title, PunkTheme.PINK, 40)
	vbox.add_child(title)
	PunkTheme.tag_underline(vbox, PunkTheme.PINK, 240)
	
	# Tab strip
	var tabs = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 18)
	vbox.add_child(tabs)
	tab_stats_btn = Button.new()
	tab_stats_btn.text = "STATS"
	PunkTheme.style_button(tab_stats_btn, PunkTheme.CYAN, 20)
	tab_stats_btn.pressed.connect(func(): _show_tab("stats"))
	tabs.add_child(tab_stats_btn)
	tab_controls_btn = Button.new()
	tab_controls_btn.text = "CONTROLS"
	PunkTheme.style_button(tab_controls_btn, PunkTheme.GREEN, 20)
	tab_controls_btn.pressed.connect(func(): _show_tab("controls"))
	tabs.add_child(tab_controls_btn)
	
	# ── STATS PAGE ─────────────────────────────────────────────────────
	stats_page = VBoxContainer.new()
	stats_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(stats_page as VBoxContainer).add_theme_constant_override("separation", 8)
	vbox.add_child(stats_page)
	
	level_label = _add_stat_line(stats_page, 22, PunkTheme.DIM)
	
	_add_section_header(stats_page, "STATUS", PunkTheme.PINK)
	health_label = _add_stat_line(stats_page, 26, COLOR_TEXT)
	paint_label = _add_stat_line(stats_page, 22, COLOR_TEXT)
	
	_add_section_header(stats_page, "LOOT", PunkTheme.YELLOW)
	gears_label = _add_stat_line(stats_page, 22, COLOR_TEXT)
	cred_label = _add_stat_line(stats_page, 22, COLOR_TEXT)
	wisp_label = _add_stat_line(stats_page, 22, COLOR_TEXT)
	objective_label = _add_stat_line(stats_page, 18, PunkTheme.YELLOW)
	
	_add_section_header(stats_page, "UPGRADES", PunkTheme.GREEN)
	upgrades_label = _add_stat_line(stats_page, 20, COLOR_TEXT)
	upgrades_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# ── CONTROLS PAGE (rebind menu) ────────────────────────────────────
	controls_page = VBoxContainer.new()
	controls_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(controls_page as VBoxContainer).add_theme_constant_override("separation", 4)
	controls_page.visible = false
	vbox.add_child(controls_page)
	
	var explain = Label.new()
	explain.text = "CLICK A BINDING, THEN PRESS THE NEW KEY / BUTTON. ESC CANCELS."
	explain.add_theme_font_size_override("font_size", 15)
	explain.add_theme_color_override("font_color", PunkTheme.DIM)
	explain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_page.add_child(explain)
	
	# Column headers
	var head = HBoxContainer.new()
	controls_page.add_child(head)
	var h_a = Label.new(); h_a.text = "ACTION"; h_a.custom_minimum_size.x = 280
	h_a.add_theme_font_size_override("font_size", 16)
	h_a.add_theme_color_override("font_color", PunkTheme.PINK)
	head.add_child(h_a)
	var h_k = Label.new(); h_k.text = "KEYBOARD"; h_k.custom_minimum_size.x = 200
	h_k.add_theme_font_size_override("font_size", 16)
	h_k.add_theme_color_override("font_color", PunkTheme.CYAN)
	head.add_child(h_k)
	var h_p = Label.new(); h_p.text = "DUALSHOCK"; h_p.custom_minimum_size.x = 200
	h_p.add_theme_font_size_override("font_size", 16)
	h_p.add_theme_color_override("font_color", PunkTheme.GREEN)
	head.add_child(h_p)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 310
	controls_page.add_child(scroll)
	var rows_box = VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 4)
	scroll.add_child(rows_box)
	
	var im = get_node_or_null("/root/InputManager")
	if im:
		for action in im.REBINDABLE:
			var row = HBoxContainer.new()
			rows_box.add_child(row)
			
			var name_lbl = Label.new()
			name_lbl.text = str(im.REBINDABLE[action]).to_upper()
			name_lbl.custom_minimum_size.x = 280
			name_lbl.add_theme_font_size_override("font_size", 19)
			name_lbl.add_theme_color_override("font_color", COLOR_TEXT)
			row.add_child(name_lbl)
			
			var kb_btn = Button.new()
			kb_btn.custom_minimum_size = Vector2(180, 36)
			PunkTheme.style_button(kb_btn, PunkTheme.CYAN, 17)
			kb_btn.pressed.connect(_start_listening.bind(action, "kb", kb_btn))
			row.add_child(kb_btn)
			
			var spacer = Control.new()
			spacer.custom_minimum_size.x = 20
			row.add_child(spacer)
			
			var pad_btn = Button.new()
			pad_btn.custom_minimum_size = Vector2(180, 36)
			PunkTheme.style_button(pad_btn, PunkTheme.GREEN, 17)
			pad_btn.pressed.connect(_start_listening.bind(action, "pad", pad_btn))
			row.add_child(pad_btn)
			
			rebind_rows.append({"action": action, "name": name_lbl, "kb": kb_btn, "pad": pad_btn})
	
	var reset_btn = Button.new()
	reset_btn.text = "RESET TO DEFAULTS"
	reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	PunkTheme.style_button(reset_btn, PunkTheme.RED, 17)
	reset_btn.pressed.connect(func():
		var imr = get_node_or_null("/root/InputManager")
		if imr:
			imr.reset_to_defaults()
			_refresh_bindings())
	controls_page.add_child(reset_btn)
	
	# ── Footer ─────────────────────────────────────────────────────────
	vbox.add_child(_separator())
	hints_label = Label.new()
	hints_label.add_theme_font_size_override("font_size", 17)
	hints_label.add_theme_color_override("font_color", PunkTheme.DIM)
	hints_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hints_label)
	
	var resume_btn = Button.new()
	resume_btn.text = "RESUME"
	resume_btn.custom_minimum_size = Vector2(220, 48)
	resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	PunkTheme.style_button(resume_btn, PunkTheme.PINK, 22)
	resume_btn.pressed.connect(close_menu)
	vbox.add_child(resume_btn)

func _show_tab(tab: String):
	current_tab = tab
	stats_page.visible = tab == "stats"
	controls_page.visible = tab == "controls"
	# Active tab pops
	tab_stats_btn.modulate = Color.WHITE if tab == "stats" else Color(0.55, 0.55, 0.6)
	tab_controls_btn.modulate = Color.WHITE if tab == "controls" else Color(0.55, 0.55, 0.6)

func _start_listening(action: String, device: String, btn: Button):
	if listening_btn and is_instance_valid(listening_btn):
		_refresh_bindings()
	listening_action = action
	listening_device = device
	listening_btn = btn
	btn.text = "PRESS..."

func _refresh_bindings():
	var im = get_node_or_null("/root/InputManager")
	if not im:
		return
	for row in rebind_rows:
		var labels: Dictionary = im.binding_labels(row.action)
		row.kb.text = str(labels.kb)
		row.pad.text = str(labels.pad)

func _add_section_header(parent: Control, text: String, color: Color = PunkTheme.CYAN):
	var lbl = Label.new()
	lbl.text = "// " + text
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)

func _add_stat_line(parent: Control, size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl

func _separator() -> HSeparator:
	return HSeparator.new()

# ---------------------------------------------------------------------------
# Stats refresh
# ---------------------------------------------------------------------------

func _refresh_stats():
	var gm = get_node_or_null("/root/GameManager")
	var pm = get_node_or_null("/root/PaintManager")
	
	var scene = get_tree().current_scene
	var level_name = "Unknown"
	if scene:
		level_name = String(scene.name).replace("_", " ")
	level_label.text = "SPOT:  " + level_name.to_upper()
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Footer hints follow the live pause binding
	var im = get_node_or_null("/root/InputManager")
	var p_pause := "[ESC/START]"
	if im:
		p_pause = im.prompt("start")
	hints_label.text = p_pause + "  RESUME        [HOLD F1]  QUIT"
	
	if gm:
		var hp = gm.get_player_health()
		var max_hp = gm.get_player_max_health()
		var hearts = ""
		for i in range(max_hp):
			hearts += "\u2665 " if i < hp else "\u2661 "
		health_label.text = "HEALTH:  " + hearts + " (%d / %d)" % [hp, max_hp]
		
		gears_label.text = "\u2699 GEARS:  %d" % gm.get_gear_count()
		cred_label.text = "\u2726 CRED:  %d" % gm.get_CRED_count()
		
		var wp = gm.get_wisp_progress()
		if wp.total > 0:
			wisp_label.text = "\u25cf SPRAY CANS:  %d / %d" % [wp.collected, wp.total]
			if wp.collected >= wp.total:
				objective_label.text = "All spray cans found! Your CRED reward has appeared."
			else:
				objective_label.text = "Find all %d Ink Wisps in this level to earn a CRED." % wp.total
		else:
			wisp_label.text = "\u25cf SPRAY CANS:  none in this level"
			objective_label.text = ""
		
		# Upgrades owned - reads the canonical registry, shows ALL of them
		var owned: Array[String] = []
		for key in gm.ALL_UPGRADE_KEYS:
			if gm.is_upgrade_purchased(key):
				owned.append(gm.get_upgrade_name(key))
		upgrades_label.text = ", ".join(owned) if owned.size() > 0 else "None yet - visit the Merchant!"
	
	if pm and pm.has_method("get_paint_amount"):
		var paint_type_name = ""
		if "paint_names" in pm and "current_paint" in pm:
			paint_type_name = "  (%s)" % str(pm.paint_names.get(pm.current_paint, ""))
		paint_label.text = "PAINT:  %d / %d%s" % [pm.get_paint_amount(), pm.get_max_paint_amount(), paint_type_name]
		paint_label.visible = true
	else:
		paint_label.visible = false
