extends CanvasLayer
class_name DebugOverlay

# ──────────────────────────────────────────────────────────────
#  GREYBOX DEBUG OVERLAY
#  Toggle with: ` (backtick — mapped to "display" action in project.godot)
#  Shows comprehensive platformer diagnostics for Inke + HU-3
# ──────────────────────────────────────────────────────────────

var visible_overlay: bool = false

# ── References ────────────────────────────────────────────────
var player: CharacterBody3D = null
var game_manager: Node = null
var checkpoint_manager: Node = null
var paint_manager: Node = null
var state_machine: Node = null

# ── UI Nodes ──────────────────────────────────────────────────
var bg_panel: ColorRect
var label_left: RichTextLabel
var label_right: RichTextLabel

# ── Jump tracking ─────────────────────────────────────────────
var launch_y: float = 0.0
var peak_y: float = 0.0
var last_jump_height: float = 0.0
var last_jump_apex_speed: float = 0.0
var was_on_floor: bool = true
var tracking_jump: bool = false

# ── Speed history for ASCII graphs ───────────────────────────
const GRAPH_SAMPLES: int = 80
var speed_history: Array[float] = []
var vert_history: Array[float] = []

# ── Internal ──────────────────────────────────────────────────
var _tick: float = 0.0

# ── BBCode colour tags ────────────────────────────────────────
const C_HEADER := "[color=#00ffcc]"
const C_KEY    := "[color=#aaffee]"
const C_VAL    := "[color=#ffffff]"
const C_WARN   := "[color=#ffdd00]"
const C_DANGER := "[color=#ff4444]"
const C_GOOD   := "[color=#44ff88]"
const C_DIM    := "[color=#557766]"
const C_RESET  := "[/color]"

# ═════════════════════════════════════════════════════════════
func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_set_visible(false)
	call_deferred("_find_references")
	for i in GRAPH_SAMPLES:
		speed_history.append(0.0)
		vert_history.append(0.0)

# ─── Build UI ─────────────────────────────────────────────────
func _build_ui() -> void:
	bg_panel = ColorRect.new()
	bg_panel.name = "DebugBG"
	bg_panel.color = Color(0.0, 0.04, 0.06, 0.88)
	bg_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg_panel.position = Vector2(0, 0)
	bg_panel.size = Vector2(760, 760)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_panel)

	var accent := ColorRect.new()
	accent.color = Color(0.0, 1.0, 0.8, 1.0)
	accent.position = Vector2(0, 0)
	accent.size = Vector2(760, 3)
	bg_panel.add_child(accent)

	var title := Label.new()
	title.text = "  ◈ INKE & HU-3 DEBUG OVERLAY  [` to close]"
	title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8))
	title.add_theme_font_size_override("font_size", 13)
	title.position = Vector2(4, 6)
	bg_panel.add_child(title)

	label_left = RichTextLabel.new()
	label_left.bbcode_enabled = true
	label_left.scroll_active = false
	label_left.fit_content = true
	label_left.position = Vector2(6, 26)
	label_left.size = Vector2(370, 730)
	label_left.add_theme_font_size_override("normal_font_size", 12)
	label_left.add_theme_font_size_override("bold_font_size", 12)
	label_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_panel.add_child(label_left)

	var div := ColorRect.new()
	div.color = Color(0.0, 1.0, 0.8, 0.15)
	div.position = Vector2(380, 26)
	div.size = Vector2(1, 730)
	bg_panel.add_child(div)

	label_right = RichTextLabel.new()
	label_right.bbcode_enabled = true
	label_right.scroll_active = false
	label_right.fit_content = true
	label_right.position = Vector2(384, 26)
	label_right.size = Vector2(370, 730)
	label_right.add_theme_font_size_override("normal_font_size", 12)
	label_right.add_theme_font_size_override("bold_font_size", 12)
	label_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_panel.add_child(label_right)

# ─── Find runtime references ──────────────────────────────────
func _find_references() -> void:
	game_manager       = get_node_or_null("/root/GameManager")
	checkpoint_manager = get_node_or_null("/root/CheckpointManager")
	paint_manager      = get_node_or_null("/root/PaintManager")
	var players := get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0] as CharacterBody3D
		if player and player.has_node("StateMachine"):
			state_machine = player.get_node("StateMachine")

# ═════════════════════════════════════════════════════════════
func _input(_event: InputEvent) -> void:
	# "display" action is bound to backtick (keycode 96) in project.godot
	if Input.is_action_just_pressed("display"):
		_set_visible(not visible_overlay)
		get_viewport().set_input_as_handled()

func _set_visible(v: bool) -> void:
	visible_overlay = v
	bg_panel.visible = v

# ═════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	_tick += delta
	_track_jump()
	_track_speed_history()
	if not visible_overlay:
		return
	if not player or not is_instance_valid(player):
		_find_references()
	_update_left_column(delta)
	_update_right_column()

# ─── Jump tracking ────────────────────────────────────────────
func _track_jump() -> void:
	if not player or not is_instance_valid(player):
		return
	var on_floor := player.is_on_floor()
	if was_on_floor and not on_floor:
		launch_y = player.global_position.y
		peak_y   = launch_y
		tracking_jump = true
		last_jump_apex_speed = 0.0
	if tracking_jump and not on_floor:
		if player.global_position.y > peak_y:
			peak_y = player.global_position.y
			last_jump_apex_speed = Vector2(player.velocity.x, player.velocity.z).length()
	if not was_on_floor and on_floor and tracking_jump:
		last_jump_height = peak_y - launch_y
		tracking_jump = false
	was_on_floor = on_floor

# ─── Speed history ────────────────────────────────────────────
func _track_speed_history() -> void:
	if not player or not is_instance_valid(player):
		return
	speed_history.append(Vector2(player.velocity.x, player.velocity.z).length())
	vert_history.append(player.velocity.y)
	if speed_history.size() > GRAPH_SAMPLES:
		speed_history.pop_front()
		vert_history.pop_front()

# ═════════════════════════════════════════════════════════════
#  LEFT COLUMN — physics / movement
# ═════════════════════════════════════════════════════════════
func _update_left_column(delta: float) -> void:
	var txt := ""

	var fps := Engine.get_frames_per_second()
	var fps_col := C_GOOD if fps >= 55 else (C_WARN if fps >= 30 else C_DANGER)
	txt += _header("◆ PERFORMANCE")
	txt += _row("FPS",        fps_col + str(fps) + C_RESET)
	txt += _row("Physics Hz", C_VAL + str(Engine.physics_ticks_per_second) + C_RESET)
	txt += _row("δ frame",    C_DIM + "%.4f s" % delta + C_RESET)
	txt += _row("δ physics",  C_DIM + "%.4f s" % get_physics_process_delta_time() + C_RESET)
	txt += "\n"

	if not player or not is_instance_valid(player):
		txt += C_DANGER + "  !! Player not found !!" + C_RESET + "\n"
		label_left.text = txt
		return

	var pos := player.global_position
	txt += _header("◆ WORLD POSITION")
	txt += _row("X", C_VAL + "%.3f" % pos.x + C_RESET)
	txt += _row("Y", C_VAL + "%.3f" % pos.y + C_RESET)
	txt += _row("Z", C_VAL + "%.3f" % pos.z + C_RESET)
	txt += "\n"

	var vel     := player.velocity
	var h_speed := Vector2(vel.x, vel.z).length()
	var h_col   := C_GOOD if h_speed < 20 else (C_WARN if h_speed < 50 else C_DANGER)
	txt += _header("◆ VELOCITY")
	txt += _row("vel.X",   C_VAL + "%.3f" % vel.x + C_RESET)
	txt += _row("vel.Y",   _vert_col(vel.y) + "%.3f" % vel.y + C_RESET)
	txt += _row("vel.Z",   C_VAL + "%.3f" % vel.z + C_RESET)
	txt += _row("H-speed", h_col + "%.2f u/s" % h_speed + C_RESET)
	txt += _row("V-speed", _vert_col(vel.y) + "%.2f u/s" % vel.y + C_RESET)
	txt += _row("3D mag",  C_VAL + "%.2f u/s" % vel.length() + C_RESET)
	txt += "\n"

	txt += _header("◆ H-SPEED GRAPH  [0 ──► 60 u/s]")
	txt += _ascii_graph(speed_history, 60.0, 8)
	txt += "\n"
	txt += _header("◆ V-SPEED GRAPH  [fall ◄─ 0 ─► rise]")
	txt += _ascii_graph_bipolar(vert_history, 30.0, 5)
	txt += "\n"

	txt += _header("◆ JUMP STATS")
	if tracking_jump:
		var cur_h := maxf(0.0, player.global_position.y - launch_y)
		txt += _row("Height NOW",  C_WARN + "%.3f u" % cur_h + C_RESET)
		txt += _row("Peak so far", C_VAL  + "%.3f u" % (peak_y - launch_y) + C_RESET)
		txt += _row("Launch Y",    C_DIM  + "%.3f" % launch_y + C_RESET)
	else:
		txt += _row("Last height", C_VAL + "%.3f u" % last_jump_height + C_RESET)
		txt += _row("Apex H-spd",  C_VAL + "%.2f u/s" % last_jump_apex_speed + C_RESET)
	txt += _row("On floor",    _bool(player.is_on_floor()))
	txt += _row("On wall",     _bool(player.is_on_wall()))
	txt += _row("On ceiling",  _bool(player.is_on_ceiling()))
	txt += "\n"

	txt += _header("◆ PHYSICS VARS")
	txt += _row("Gravity",      C_VAL + "%.4f" % _get(player, "gravity", 9.8) + C_RESET)
	txt += _row("Grav default", C_DIM + "%.4f" % _get(player, "gravity_default", 9.8) + C_RESET)
	txt += _row("On ice",       _bool(_get(player, "is_on_ice", false)))
	txt += _row("Being sprung", _bool(_get(player, "is_being_sprung", false)))
	txt += _row("Controls off", _bool(_get(player, "controls_disabled", false)))

	label_left.text = txt

# ═════════════════════════════════════════════════════════════
#  RIGHT COLUMN — state / abilities / economy
# ═════════════════════════════════════════════════════════════
func _update_right_column() -> void:
	var txt := ""

	if not player or not is_instance_valid(player):
		label_right.text = ""
		return

	txt += _header("◆ STATE MACHINE")
	var state_name := "UNKNOWN"
	if state_machine and state_machine.get("current_state") != null:
		var cs = state_machine.current_state
		if cs and cs.get_script():
			state_name = cs.get_script().get_global_name()
	txt += _row("Current", C_GOOD + state_name + C_RESET)
	txt += "\n"

	txt += _header("◆ COYOTE TIME")
	var coyote     := _get(player, "coyote_time_counter", 0.0)
	var coyote_dur := _get(player, "coyote_time_duration", 0.15)
	var c_pct      := coyote / coyote_dur if coyote_dur > 0 else 0.0
	txt += _row("Counter",    (C_GOOD if coyote > 0.05 else C_DANGER) + "%.3f s" % coyote + C_RESET)
	txt += _row("Duration",   C_DIM + "%.3f s" % coyote_dur + C_RESET)
	txt += _mini_bar_row("Bar", c_pct)
	txt += _row("Ignore jump", _bool(_get(player, "ignore_next_jump", false)))
	txt += "\n"

	txt += _header("◆ RUNTIME ABILITIES")
	var has_dj  := _get(player, "can_double_jump",   false)
	var used_dj := _get(player, "has_double_jumped",  false)
	var has_ad  := _get(player, "can_air_dash",      false)
	var used_ad := _get(player, "has_air_dashed",    false)
	var can_lj  := _get(player, "can_long_jump",     false)
	var lj_t    := _get(player, "long_jump_timer",   0.0)
	var lj_w    := _get(player, "long_jump_window",  0.3)
	var sdm_raw := _get(player, "stored_dash_momentum", null)
	var sdm_len := sdm_raw.length() if sdm_raw is Vector3 else 0.0
	txt += _row("DJ avail",     _bool(has_dj))
	txt += _row("DJ used",      _bool(used_dj))
	txt += _row("Air dash OK",  _bool(has_ad))
	txt += _row("Air dash used",_bool(used_ad))
	txt += _row("Long jump",    _bool(can_lj) + C_DIM + " %.2fs" % lj_t + C_RESET)
	txt += _mini_bar_row("LJ window", lj_t / lj_w if lj_w > 0 else 0.0)
	if sdm_len > 0.01:
		txt += _row("Dash mom", C_WARN + "%.2f u/s stored" % sdm_len + C_RESET)
	else:
		txt += _row("Dash mom", C_DIM + "none" + C_RESET)
	txt += "\n"

	txt += _header("◆ WALL JUMP")
	var wj_cd := _get(player, "wall_jump_cooldown", 0.0)
	txt += _row("Cooldown", C_VAL + "%.3f s" % wj_cd + C_RESET)
	txt += _row("Ready",    _bool(wj_cd <= 0.0 and not player.is_on_floor()))
	txt += "\n"

	txt += _header("◆ UPGRADES (GameManager)")
	if game_manager:
		txt += _row("Double jump", _bool(game_manager.get("double_jump_purchased")))
		txt += _row("Wall jump",   _bool(game_manager.get("wall_jump_purchased")))
		txt += _row("Dash",        _bool(game_manager.get("dash_purchased")))
		txt += _row("Speed",       _bool(game_manager.get("speed_upgrade_purchased")))
		txt += _row("Health+",     _bool(game_manager.get("health_upgrade_purchased")))
		txt += _row("Damage+",     _bool(game_manager.get("damage_upgrade_purchased")))
	else:
		txt += C_DANGER + "  GameManager not found\n" + C_RESET
	txt += "\n"

	txt += _header("◆ DAMAGE STATE")
	var health  := game_manager.get_player_health() if game_manager else 0
	var max_hp  := game_manager.get_player_max_health() if game_manager else 3
	var is_inv  := _get(player, "is_invulnerable", false)
	var inv_t   := _get(player, "invulnerability_timer", 0.0)
	var inv_d   := _get(player, "invulnerability_duration", 1.5)
	var hp_col  := C_GOOD if health >= max_hp else (C_WARN if health > 1 else C_DANGER)
	txt += _row("Health",  hp_col + _heart_bar(health, max_hp) + " %d/%d" % [health, max_hp] + C_RESET)
	txt += _row("Dead",    _bool(_get(player, "is_dead", false), true))
	txt += _row("Invuln",  _bool(is_inv))
	if is_inv:
		txt += _row("Inv timer", C_WARN + "%.2f / %.2f s" % [inv_t, inv_d] + C_RESET)
		txt += _mini_bar_row("Inv bar", inv_t / inv_d if inv_d > 0 else 0.0)
	txt += _row("Flashing", _bool(_get(player, "should_flash", false)))
	txt += "\n"

	txt += _header("◆ ECONOMY")
	if game_manager:
		txt += _row("Gears", C_VAL + str(game_manager.get_gear_count()) + C_RESET)
		txt += _row("CRED",  C_VAL + str(game_manager.get_CRED_count()) + C_RESET)
	txt += "\n"

	txt += _header("◆ PAINT SYSTEM")
	if paint_manager:
		var pa   := _get(paint_manager, "current_paint_amount", 0)
		var pmax := _get(paint_manager, "max_paint_amount", 100)
		var pname := paint_manager.get_current_paint_name() if paint_manager.has_method("get_current_paint_name") else "?"
		var ppct := float(pa) / float(pmax) if pmax > 0 else 0.0
		var pc   := C_GOOD if ppct > 0.5 else (C_WARN if ppct > 0.2 else C_DANGER)
		txt += _row("Type",  C_VAL + pname + C_RESET)
		txt += _row("Meter", pc + "%d / %d" % [pa, pmax] + C_RESET)
		txt += _mini_bar_row("Bar", ppct)
	else:
		txt += C_DIM + "  PaintManager not found\n" + C_RESET
	txt += "\n"

	txt += _header("◆ CHECKPOINT")
	if checkpoint_manager:
		var has_cp := checkpoint_manager.has_active_checkpoint()
		txt += _row("Active", _bool(has_cp))
		if has_cp:
			var cp := checkpoint_manager.get_checkpoint_position()
			txt += _row("Pos", C_DIM + "(%.1f, %.1f, %.1f)" % [cp.x, cp.y, cp.z] + C_RESET)
	else:
		txt += C_DIM + "  CheckpointManager not found\n" + C_RESET

	label_right.text = txt

# ═════════════════════════════════════════════════════════════
#  FORMATTING HELPERS
# ═════════════════════════════════════════════════════════════
func _get(obj: Object, prop: String, fallback: Variant) -> Variant:
	if obj and obj.has_method("get"):
		var v = obj.get(prop)
		if v != null:
			return v
	return fallback

func _header(title: String) -> String:
	return C_HEADER + "[b]" + title + "[/b]" + C_RESET + "\n"

func _row(key: String, value: String) -> String:
	var pad  := max(0, 14 - key.length())
	var dots := C_DIM + ".".repeat(pad) + C_RESET
	return C_KEY + "  " + key + C_RESET + dots + " " + value + "\n"

func _bool(value: bool, invert: bool = false) -> String:
	var positive := value != invert
	return (C_GOOD + "✓ YES" if positive else C_DIM + "✗ NO") + C_RESET

func _vert_col(vy: float) -> String:
	if vy > 1.0:   return C_GOOD
	if vy < -10.0: return C_DANGER
	if vy < -3.0:  return C_WARN
	return C_VAL

func _heart_bar(hp: int, max_hp: int) -> String:
	var s := ""
	for i in max_hp:
		s += "♥" if i < hp else "♡"
	return s

func _mini_bar_row(label: String, pct: float) -> String:
	pct = clampf(pct, 0.0, 1.0)
	const W := 18
	var filled := int(pct * W)
	var col    := C_GOOD if pct > 0.5 else (C_WARN if pct > 0.2 else C_DANGER)
	var bar    := C_DIM + "[" + C_RESET + col + "█".repeat(filled) + C_RESET + C_DIM + "░".repeat(W - filled) + "]" + C_RESET
	return _row(label, bar)

func _speed_char(pct: float) -> String:
	if pct > 0.85: return C_DANGER + "█" + C_RESET
	if pct > 0.65: return C_WARN   + "▓" + C_RESET
	if pct > 0.40: return C_GOOD   + "▒" + C_RESET
	return C_DIM + "░" + C_RESET

func _ascii_graph(history: Array, max_val: float, height: int) -> String:
	var rows: Array[String] = []
	for _r in height:
		rows.append("")
	for i in history.size():
		var v      := clampf(history[i], 0.0, max_val)
		var filled := int((v / max_val) * height)
		for r in height:
			rows[r] += _speed_char(v / max_val) if (height - 1 - r) < filled else C_DIM + "·" + C_RESET
	var out := ""
	for r in rows:
		out += "  " + r + "\n"
	return out

func _ascii_graph_bipolar(history: Array, max_val: float, half_h: int) -> String:
	var total := half_h * 2
	var rows: Array[String] = []
	for _r in total:
		rows.append("")
	for i in history.size():
		var v    := clampf(history[i], -max_val, max_val)
		var norm := v / max_val
		for r in total:
			if norm >= 0:
				var bar_end := half_h - int(norm * half_h)
				if r >= bar_end and r < half_h:
					rows[r] += C_GOOD + "▐" + C_RESET
				elif r == half_h:
					rows[r] += C_DIM + "─" + C_RESET
				else:
					rows[r] += C_DIM + "·" + C_RESET
			else:
				var bar_end := half_h + int(-norm * half_h)
				if r > half_h and r <= bar_end:
					rows[r] += C_DANGER + "▐" + C_RESET
				elif r == half_h:
					rows[r] += C_DIM + "─" + C_RESET
				else:
					rows[r] += C_DIM + "·" + C_RESET
	var out := ""
	for r_idx in rows.size():
		var lbl := ""
		if r_idx == 0:             lbl = " " + C_GOOD   + "+%.0fu/s" % max_val + C_RESET
		elif r_idx == half_h:      lbl = " " + C_DIM    + "0" + C_RESET
		elif r_idx == total - 1:   lbl = " " + C_DANGER + "-%.0fu/s" % max_val + C_RESET
		out += "  " + rows[r_idx] + lbl + "\n"
	return out
