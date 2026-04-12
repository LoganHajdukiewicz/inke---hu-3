extends CanvasLayer
class_name DebugOverlay

# ──────────────────────────────────────────────────────────────
#  GREYBOX DEBUG OVERLAY  (v4 – air control · friction · jump distances)
#  Toggle with: ` (backtick — "display" action)
#  Scroll:      Mouse wheel  OR  D-pad Up/Down while overlay open
# ──────────────────────────────────────────────────────────────

var visible_overlay: bool = false

# ── References ────────────────────────────────────────────────
var player: CharacterBody3D = null
var hu3: CharacterBody3D    = null
var game_manager: Node       = null
var checkpoint_manager: Node = null
var paint_manager: Node      = null
var state_machine: Node      = null

# ── UI Layout constants ───────────────────────────────────────
const PANEL_W    : int = 1180
const PANEL_H    : int = 1060
const CONTENT_H  : int = 5200  # Expanded for new sections
const COL_W      : int = 370
const MARGIN_TOP : int = 28
const FONT_SIZE  : int = 12

# ── Scroll ────────────────────────────────────────────────────
var scroll_offset  : float = 0.0
var _scroll_target : float = 0.0
const SCROLL_STEP  : float = 28.0
const SCROLL_SMOOTH: float = 14.0

# ── UI Nodes ──────────────────────────────────────────────────
var bg_panel   : ColorRect
var scroll_cont: ScrollContainer
var col_parent : HBoxContainer
var label_left : RichTextLabel
var label_mid  : RichTextLabel
var label_right: RichTextLabel

# ── Jump tracking ─────────────────────────────────────────────
var launch_y: float = 0.0
var launch_pos: Vector3 = Vector3.ZERO
var peak_y: float = 0.0
var last_jump_height: float = 0.0
var last_jump_apex_speed: float = 0.0
var last_jump_horizontal_distance: float = 0.0
var last_jump_airtime: float = 0.0
var jump_airtime_counter: float = 0.0
var was_on_floor_jump: bool = true
var tracking_jump: bool = false

# ── NEW: Jump distance records ────────────────────────────────
var session_max_jump_height_off_ground: float = 0.0   # peak Y above spawn/ground, not above launch
var session_max_horizontal_jump_dist: float = 0.0
var session_max_airtime: float = 0.0
var last_landing_pos: Vector3 = Vector3.ZERO
var ground_y_at_launch: float = 0.0  # floor Y when jump started (for "height off ground")

# ── Speed history ─────────────────────────────────────────────
const GRAPH_SAMPLES: int = 80
var speed_history        : Array[float] = []
var vert_history         : Array[float] = []
var gravity_mult_history : Array[float] = []
var accel_history        : Array[float] = []

# ── NEW: Air control & friction history ───────────────────────
var air_control_history  : Array[float] = []  # effective horizontal air control factor
var friction_history     : Array[float] = []  # effective ground friction/decel per frame

# ── Previous frame velocity ───────────────────────────────────
var _prev_velocity: Vector3 = Vector3.ZERO
var _prev_h_speed: float = 0.0

# ── Session stats ─────────────────────────────────────────────
var session_peak_speed      : float = 0.0
var session_peak_fall_speed : float = 0.0
var session_peak_jump_height: float = 0.0
var session_jump_count      : int   = 0
var session_dash_count      : int   = 0
var session_wall_jump_count : int   = 0
var session_dbl_jump_count  : int   = 0
var session_grapple_count   : int   = 0
var session_damage_taken    : int   = 0
var session_heals           : int   = 0
var session_gears_collected : int   = 0
var _prev_gear_count        : int   = 0
var _prev_health            : int   = 3

# ── NEW: Game-feel session stats ──────────────────────────────
var session_peak_h_accel    : float = 0.0
var session_peak_h_decel    : float = 0.0
var session_spin_count      : int   = 0
var session_ledge_grab_count: int   = 0
var session_rail_count      : int   = 0
var session_coyote_jumps    : int   = 0
var session_long_jumps      : int   = 0
var session_dash_jumps      : int   = 0
var spin_was_active    : bool = false
var ledge_was_active   : bool = false
var rail_was_active    : bool = false

# ── State tracking ────────────────────────────────────────────
var last_state_name    : String = ""
var state_duration     : float  = 0.0
var previous_state_name: String = ""
var previous_state_dur : float  = 0.0
var state_enter_speed  : float  = 0.0
var state_peak_speed   : float  = 0.0
var state_history      : Array  = []

# ── Event flags ───────────────────────────────────────────────
var dash_was_active      : bool  = false
var wall_jump_was_active : bool  = false
var dbl_jump_was_active  : bool  = false
var grapple_was_active   : bool  = false
var last_dash_distance   : float = 0.0
var was_on_floor         : bool  = true

# ── NEW: Air control tracking ─────────────────────────────────
var air_time_total       : float = 0.0  # total seconds airborne this session
var ground_time_total    : float = 0.0  # total seconds on ground this session
var current_air_control  : float = 0.0  # computed each frame from state
var current_air_resist   : float = 0.0  # computed each frame from state

# ── NEW: Friction & decel tracking ───────────────────────────
var current_ground_friction   : float = 0.0  # effective decel or friction label
var current_friction_label    : String = "—"  # e.g. "Normal", "Ice", "Sliding"
var frames_in_air             : int   = 0
var frames_on_ground          : int   = 0

# ── HU-3 tracking ─────────────────────────────────────────────
var hu3_distance_history: Array[float] = []
const HU3_GRAPH_SAMPLES : int = 40

# ── Internal ──────────────────────────────────────────────────
var _tick: float = 0.0

# ── BBCode colours ────────────────────────────────────────────
const C_HEADER := "[color=#00ffcc]"
const C_KEY    := "[color=#aaffee]"
const C_VAL    := "[color=#ffffff]"
const C_WARN   := "[color=#ffdd00]"
const C_DANGER := "[color=#ff4444]"
const C_GOOD   := "[color=#44ff88]"
const C_DIM    := "[color=#557766]"
const C_ACCENT := "[color=#ff88ff]"
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
		gravity_mult_history.append(0.0)
		accel_history.append(0.0)
		air_control_history.append(0.0)
		friction_history.append(0.0)
	for i in HU3_GRAPH_SAMPLES:
		hu3_distance_history.append(0.0)

# ─── Build UI ─────────────────────────────────────────────────
func _build_ui() -> void:
	bg_panel = ColorRect.new()
	bg_panel.name = "DebugBG"
	bg_panel.color = Color(0.0, 0.04, 0.06, 0.92)
	bg_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg_panel.position = Vector2(0, 0)
	bg_panel.size = Vector2(PANEL_W, PANEL_H)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_panel)

	var accent := ColorRect.new()
	accent.color = Color(0.0, 1.0, 0.8, 1.0)
	accent.position = Vector2(0, 0)
	accent.size = Vector2(PANEL_W, 3)
	bg_panel.add_child(accent)

	var title := Label.new()
	title.text = "  ◈ INKE & HU-3 DEBUG  v4  [` toggle | wheel / D-pad ↑↓ scroll]"
	title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8))
	title.add_theme_font_size_override("font_size", 12)
	title.position = Vector2(4, 6)
	bg_panel.add_child(title)

	scroll_cont = ScrollContainer.new()
	scroll_cont.name = "DebugScroll"
	scroll_cont.position = Vector2(0, MARGIN_TOP)
	scroll_cont.size = Vector2(PANEL_W, PANEL_H - MARGIN_TOP)
	scroll_cont.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_cont.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_panel.add_child(scroll_cont)

	col_parent = HBoxContainer.new()
	col_parent.name = "ColumnParent"
	col_parent.size = Vector2(PANEL_W, CONTENT_H)
	col_parent.add_theme_constant_override("separation", 8)
	col_parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_cont.add_child(col_parent)

	label_left  = _make_label()
	label_mid   = _make_label()
	label_right = _make_label()
	col_parent.add_child(label_left)
	col_parent.add_child(_make_divider())
	col_parent.add_child(label_mid)
	col_parent.add_child(_make_divider())
	col_parent.add_child(label_right)

func _make_label() -> RichTextLabel:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.scroll_active = false
	lbl.fit_content = true
	lbl.custom_minimum_size = Vector2(COL_W, CONTENT_H)
	lbl.size = Vector2(COL_W, CONTENT_H)
	lbl.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	lbl.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _make_divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.0, 1.0, 0.8, 0.12)
	d.custom_minimum_size = Vector2(1, CONTENT_H)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

# ─── Find references ──────────────────────────────────────────
func _find_references() -> void:
	game_manager       = get_node_or_null("/root/GameManager")
	checkpoint_manager = get_node_or_null("/root/CheckpointManager")
	paint_manager      = get_node_or_null("/root/PaintManager")
	var players := get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0] as CharacterBody3D
		if player and player.has_node("StateMachine"):
			state_machine = player.get_node("StateMachine")
	if not hu3 and game_manager and game_manager.has_method("get_hu3_companion"):
		var h = game_manager.get_hu3_companion()
		if h and is_instance_valid(h): hu3 = h

# ═════════════════════════════════════════════════════════════
#  INPUT
# ═════════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("display"):
		_set_visible(not visible_overlay)
		get_viewport().set_input_as_handled()
		return
	if not visible_overlay: return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_target += SCROLL_STEP * 3
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_target -= SCROLL_STEP * 3
				get_viewport().set_input_as_handled()
	if Input.is_action_just_pressed("d_pad_down"): _scroll_target += SCROLL_STEP * 2
	if Input.is_action_just_pressed("d_pad_up"):   _scroll_target -= SCROLL_STEP * 2

func _set_visible(v: bool) -> void:
	visible_overlay = v
	bg_panel.visible = v

func _max_scroll() -> float:
	return maxf(0.0, float(CONTENT_H) - float(PANEL_H - MARGIN_TOP))

# ═════════════════════════════════════════════════════════════
#  MAIN PROCESS
# ═════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	_tick += delta
	if not player or not is_instance_valid(player):
		if visible_overlay: _find_references()
		return

	_track_jump(delta)
	_track_histories(delta)
	_track_state_duration(delta)
	_track_session_peaks()
	_track_events()
	_track_hu3()
	_track_economy()
	_track_air_ground_time(delta)       # NEW
	_track_air_control_and_friction()   # NEW

	if not visible_overlay:
		_prev_velocity = player.velocity
		_prev_h_speed = Vector2(player.velocity.x, player.velocity.z).length()
		return

	if Input.is_action_pressed("d_pad_down"): _scroll_target += SCROLL_STEP * delta * 55.0
	if Input.is_action_pressed("d_pad_up"):   _scroll_target -= SCROLL_STEP * delta * 55.0
	_scroll_target = clampf(_scroll_target, 0.0, _max_scroll())
	scroll_offset  = lerpf(scroll_offset, _scroll_target, SCROLL_SMOOTH * delta)
	scroll_cont.scroll_vertical = int(scroll_offset)

	_update_left(delta)
	_update_mid()
	_update_right()
	_prev_velocity = player.velocity
	_prev_h_speed = Vector2(player.velocity.x, player.velocity.z).length()

# ═════════════════════════════════════════════════════════════
#  TRACKING
# ═════════════════════════════════════════════════════════════
func _track_jump(delta: float) -> void:
	var on_floor := player.is_on_floor()
	if was_on_floor and not on_floor:
		launch_y = player.global_position.y
		launch_pos = player.global_position
		ground_y_at_launch = player.global_position.y
		peak_y = launch_y
		tracking_jump = true
		jump_airtime_counter = 0.0
		last_jump_apex_speed = 0.0
		session_jump_count += 1
	if tracking_jump and not on_floor:
		jump_airtime_counter += delta
		if player.global_position.y > peak_y:
			peak_y = player.global_position.y
			last_jump_apex_speed = Vector2(player.velocity.x, player.velocity.z).length()
	if not was_on_floor and on_floor and tracking_jump:
		last_jump_height = peak_y - launch_y
		last_jump_airtime = jump_airtime_counter
		var lp := player.global_position
		last_jump_horizontal_distance = Vector2(lp.x - launch_pos.x, lp.z - launch_pos.z).length()
		last_landing_pos = lp

		# "Height off ground" = peak Y above the ground level at launch
		var height_off_ground := peak_y - ground_y_at_launch
		if height_off_ground > session_max_jump_height_off_ground:
			session_max_jump_height_off_ground = height_off_ground

		if last_jump_horizontal_distance > session_max_horizontal_jump_dist:
			session_max_horizontal_jump_dist = last_jump_horizontal_distance

		if last_jump_airtime > session_max_airtime:
			session_max_airtime = last_jump_airtime

		if last_jump_height > session_peak_jump_height:
			session_peak_jump_height = last_jump_height
		tracking_jump = false
	was_on_floor = on_floor

func _track_histories(delta: float) -> void:
	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var prev_h  := Vector2(_prev_velocity.x, _prev_velocity.z).length()
	var accel   := (h_speed - prev_h) / maxf(delta, 0.0001)
	speed_history.append(h_speed)
	vert_history.append(player.velocity.y)
	accel_history.append(clampf(accel, -200.0, 200.0))
	var gm: float = 1.0
	if state_machine and state_machine.get("current_state") != null:
		var cs = state_machine.current_state
		if cs and cs.get("gravity_multiplier") != null:
			gm = cs.get("gravity_multiplier") as float
	gravity_mult_history.append(gm)

	# Air control & friction history
	air_control_history.append(current_air_control)
	friction_history.append(current_ground_friction)

	if speed_history.size()        > GRAPH_SAMPLES: speed_history.pop_front()
	if vert_history.size()         > GRAPH_SAMPLES: vert_history.pop_front()
	if accel_history.size()        > GRAPH_SAMPLES: accel_history.pop_front()
	if gravity_mult_history.size() > GRAPH_SAMPLES: gravity_mult_history.pop_front()
	if air_control_history.size()  > GRAPH_SAMPLES: air_control_history.pop_front()
	if friction_history.size()     > GRAPH_SAMPLES: friction_history.pop_front()

func _track_state_duration(delta: float) -> void:
	if not state_machine: return
	var cs = state_machine.get("current_state")
	if not cs or not cs.get_script(): return
	var nm: String = cs.get_script().get_global_name()
	if nm != last_state_name:
		if last_state_name != "":
			state_history.push_front({"name": last_state_name, "dur": state_duration})
			if state_history.size() > 6: state_history.pop_back()
		previous_state_name = last_state_name
		previous_state_dur  = state_duration
		last_state_name     = nm
		state_duration      = 0.0
		state_enter_speed   = Vector2(player.velocity.x, player.velocity.z).length()
		state_peak_speed    = state_enter_speed
	else:
		state_duration += delta
		var cur_h := Vector2(player.velocity.x, player.velocity.z).length()
		if cur_h > state_peak_speed: state_peak_speed = cur_h

func _track_session_peaks() -> void:
	var h := Vector2(player.velocity.x, player.velocity.z).length()
	if h > session_peak_speed: session_peak_speed = h
	if player.velocity.y < -session_peak_fall_speed: session_peak_fall_speed = -player.velocity.y

	# Acceleration peaks
	var dt_phys := 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	var cur_h := h
	var h_accel := (cur_h - _prev_h_speed) / dt_phys
	if h_accel > session_peak_h_accel: session_peak_h_accel = h_accel
	if -h_accel > session_peak_h_decel: session_peak_h_decel = -h_accel

func _track_events() -> void:
	var csn := _current_state_name()
	var is_dashing   := csn == "DodgeDashState"
	var is_wj        := csn == "WallJumpingState"
	var is_dj        := csn == "DoubleJumpState"
	var is_grapple   := csn == "GrappleHookState"
	var is_spin      := csn == "SpinAttackState"
	var is_ledge     := csn == "LedgeHangingState"
	var is_rail      := csn == "RailGrindingState"

	if is_dashing  and not dash_was_active:     session_dash_count += 1
	if is_wj       and not wall_jump_was_active: session_wall_jump_count += 1
	if is_dj       and not dbl_jump_was_active:  session_dbl_jump_count += 1
	if is_grapple  and not grapple_was_active:   session_grapple_count += 1
	if is_spin     and not spin_was_active:      session_spin_count += 1
	if is_ledge    and not ledge_was_active:     session_ledge_grab_count += 1
	if is_rail     and not rail_was_active:      session_rail_count += 1

	if not is_dashing and dash_was_active:
		if state_machine and state_machine.get("states") != null:
			var ds = state_machine.states.get("dodgedashstate")
			if ds:
				var sp: Variant = ds.get("dash_start_position")
				if sp is Vector3:
					last_dash_distance = player.global_position.distance_to(sp as Vector3)

	dash_was_active      = is_dashing
	wall_jump_was_active = is_wj
	dbl_jump_was_active  = is_dj
	grapple_was_active   = is_grapple
	spin_was_active      = is_spin
	ledge_was_active     = is_ledge
	rail_was_active      = is_rail

	if game_manager:
		var cur_hp : int = game_manager.get_player_health()
		if cur_hp < _prev_health: session_damage_taken += (_prev_health - cur_hp)
		if cur_hp > _prev_health: session_heals += (cur_hp - _prev_health)
		_prev_health = cur_hp

	# Track coyote jumps: jump was pressed while coyote timer > 0 and not on floor
	# Approximated: if we entered JumpingState from FallingState
	if is_dj and not dbl_jump_was_active:
		pass  # already tracked

func _track_hu3() -> void:
	if not hu3 or not is_instance_valid(hu3):
		hu3 = null
		if game_manager and game_manager.has_method("get_hu3_companion"):
			var h = game_manager.get_hu3_companion()
			if h and is_instance_valid(h): hu3 = h
	var dist := player.global_position.distance_to(hu3.global_position) if (hu3 and is_instance_valid(hu3)) else 0.0
	hu3_distance_history.append(dist)
	if hu3_distance_history.size() > HU3_GRAPH_SAMPLES: hu3_distance_history.pop_front()

func _track_economy() -> void:
	if not game_manager: return
	var	cur : int = game_manager.get_gear_count()
	if cur > _prev_gear_count: session_gears_collected += (cur - _prev_gear_count)
	_prev_gear_count = cur

func _track_air_ground_time(delta: float) -> void:
	if player.is_on_floor():
		ground_time_total += delta
		frames_on_ground += 1
		frames_in_air = 0
	else:
		air_time_total += delta
		frames_in_air += 1
		frames_on_ground = 0

func _track_air_control_and_friction() -> void:
	"""
	Read the effective air control factor and friction label from the current state.
	These values come from the actual constants in each state script.
	"""
	var csn := _current_state_name()
	current_air_control = 0.0
	current_air_resist  = 0.0
	current_ground_friction = 0.0
	current_friction_label  = "—"

	match csn:
		"JumpingState":
			var cs = state_machine.current_state if state_machine else null
			var dm: bool = _prop(cs, "used_dash_momentum", false) if cs else false
			current_air_control = 0.20 if dm else 0.50
			current_air_resist  = 0.003 if dm else 0.005
			current_friction_label = "Air"

		"FallingState":
			current_air_control = 0.25
			current_air_resist  = 0.010
			current_friction_label = "Air"

		"DoubleJumpState":
			current_air_control = 0.08
			current_air_resist  = 0.002
			current_friction_label = "Air (dbl)"

		"WallJumpingState":
			var cs = state_machine.current_state if state_machine else null
			var wt: float = _prop(cs, "wall_jump_timer", 0.0) if cs else 0.0
			var ml: float = _prop(cs, "momentum_lock_duration", 0.35) if cs else 0.35
			var tl: float = _prop(cs, "total_lock_time", 0.5) if cs else 0.5
			if wt < ml:
				current_air_control = 0.0
			elif wt < tl:
				var fade := (wt - ml) / maxf(tl - ml, 0.0001)
				current_air_control = 0.1 * fade
			else:
				current_air_control = 0.3
			current_air_resist = 0.0
			current_friction_label = "Air (wj)"

		"DodgeDashState":
			current_air_control = 0.0
			current_air_resist  = 0.0
			current_friction_label = "Dash"

		"GrappleHookState":
			current_air_control = 0.0
			current_air_resist  = 0.0
			current_friction_label = "Grapple"

		"IdleState":
			var is_ice: bool = _prop(player, "is_on_ice", false)
			current_ground_friction = 100.0 * (0.01 if is_ice else 1.0)
			current_friction_label  = "Ice (100×0.01)" if is_ice else "Normal (100/s)"

		"WalkingState", "RunningState":
			var is_ice: bool = _prop(player, "is_on_ice", false)
			# Ice uses lerp factor, normal is direct velocity set (effectively infinite accel)
			if is_ice:
				current_ground_friction = 0.5  # direction-similarity accel factor on ice
				current_friction_label  = "Ice (lerp 0.5)"
			else:
				current_ground_friction = 1.0  # direct set = no friction needed
				current_friction_label  = "Direct set"

		"SlidingState":
			current_ground_friction = 0.98  # per-frame multiplier
			current_friction_label  = "Slide (×0.98/f)"

		_:
			current_friction_label = "—"

func _current_state_name() -> String:
	if not state_machine: return ""
	var cs = state_machine.get("current_state")
	if cs and cs.get_script(): return cs.get_script().get_global_name()
	return ""

# ═════════════════════════════════════════════════════════════
#  LEFT COLUMN — Perf · Transform · Contact · Physics · Velocity · Air Control · Graphs
# ═════════════════════════════════════════════════════════════
func _update_left(delta: float) -> void:
	var txt := ""

	var fps := Engine.get_frames_per_second()
	var fps_col := C_GOOD if fps >= 55 else (C_WARN if fps >= 30 else C_DANGER)
	txt += _header("◆ PERFORMANCE")
	txt += _row("FPS",          fps_col + str(fps) + C_RESET)
	txt += _row("Physics Hz",   C_VAL + str(Engine.physics_ticks_per_second) + C_RESET)
	txt += _row("δ frame",      C_DIM + "%.4f s" % delta + C_RESET)
	txt += _row("Physics δ",    C_DIM + "%.4f s" % (1.0 / Engine.physics_ticks_per_second) + C_RESET)
	txt += _row("Uptime",       C_DIM + "%.1f s" % _tick + C_RESET)
	txt += "\n"

	if not player or not is_instance_valid(player):
		txt += C_DANGER + "  !! Player not found !!" + C_RESET + "\n"
		label_left.text = txt
		return

	var pos := player.global_position
	var rot := player.rotation
	txt += _header("◆ WORLD TRANSFORM")
	txt += _row("Pos X",        C_VAL + "%.4f" % pos.x + C_RESET)
	txt += _row("Pos Y",        C_VAL + "%.4f" % pos.y + C_RESET)
	txt += _row("Pos Z",        C_VAL + "%.4f" % pos.z + C_RESET)
	txt += _row("Rot Y (yaw)",  C_DIM + "%.2f°" % rad_to_deg(rot.y) + C_RESET)
	txt += _row("Facing",       C_DIM + _facing_cardinal(rot.y) + C_RESET)
	var cam_fwd := _get_camera_forward()
	if cam_fwd != Vector3.ZERO:
		txt += _row("Cam fwd",     C_DIM + "(%.2f,%.2f,%.2f)" % [cam_fwd.x, cam_fwd.y, cam_fwd.z] + C_RESET)
		var cam_yaw := rad_to_deg(atan2(-cam_fwd.x, -cam_fwd.z))
		txt += _row("Cam yaw",     C_DIM + "%.1f°" % cam_yaw + C_RESET)
		txt += _row("Cam offset",  C_DIM + "%.1f°" % _angle_between_yaws(rad_to_deg(rot.y), cam_yaw) + C_RESET)
	txt += "\n"

	txt += _header("◆ CONTACT STATE")
	txt += _row("On floor",     _bool(player.is_on_floor()))
	txt += _row("On wall",      _bool(player.is_on_wall()))
	txt += _row("On ceiling",   _bool(player.is_on_ceiling()))
	txt += _row("On ice",       _bool(_prop(player, "is_on_ice", false) as bool))
	txt += _row("Sprung",       _bool(_prop(player, "is_being_sprung", false) as bool))
	txt += _row("Ignore jump",  _bool(_prop(player, "ignore_next_jump", false) as bool))
	txt += _row("Controls off", _bool(_prop(player, "controls_disabled", false) as bool, true))
	var frames_air_col := C_GOOD if frames_in_air == 0 else (C_WARN if frames_in_air < 30 else C_ACCENT)
	txt += _row("Frames in air", frames_air_col + str(frames_in_air) + C_RESET)
	txt += _row("Frames on gnd", C_DIM + str(frames_on_ground) + C_RESET)
	if player.is_on_floor():
		for i in player.get_slide_collision_count():
			var col = player.get_slide_collision(i)
			var floor_normal := col.get_normal()
			var collider = col.get_collider()
			if collider:
				var ft = collider.get("floor_type")
				if ft != null:
					txt += _row("Floor type",  C_ACCENT + str(ft) + C_RESET)
				txt += _row("Floor node",  C_DIM + collider.name + C_RESET)
			if floor_normal != Vector3.ZERO:
				txt += _row("Floor normal", C_DIM + "(%.2f,%.2f,%.2f)" % [floor_normal.x, floor_normal.y, floor_normal.z] + C_RESET)
				txt += _row("Slope angle", C_DIM + "%.1f°" % rad_to_deg(acos(clampf(floor_normal.dot(Vector3.UP), -1.0, 1.0))) + C_RESET)
			break
	txt += "\n"

	txt += _header("◆ PHYSICS VARS")
	txt += _row("Gravity",      C_VAL + "%.4f" % (_prop(player, "gravity", 9.8) as float) + C_RESET)
	txt += _row("Grav default", C_DIM + "%.4f" % (_prop(player, "gravity_default", 9.8) as float) + C_RESET)
	txt += _row("Floor snap",   C_DIM + "%.3f" % player.floor_snap_length + C_RESET)
	txt += _row("Max slope°",   C_DIM + "%.1f°" % rad_to_deg(player.floor_max_angle) + C_RESET)
	txt += _row("Stop on slope",_bool(player.floor_stop_on_slope))
	txt += _row("Block on wall",_bool(player.floor_block_on_wall))
	txt += "\n"

	var vel   := player.velocity
	var h_spd := Vector2(vel.x, vel.z).length()
	var h_col := C_GOOD if h_spd < 20 else (C_WARN if h_spd < 50 else C_DANGER)
	txt += _header("◆ VELOCITY")
	txt += _row("vel.X",        C_VAL + "%.4f" % vel.x + C_RESET)
	txt += _row("vel.Y",        _vert_col(vel.y) + "%.4f" % vel.y + C_RESET)
	txt += _row("vel.Z",        C_VAL + "%.4f" % vel.z + C_RESET)
	txt += _row("H-speed",      h_col + "%.4f u/s" % h_spd + C_RESET)
	txt += _row("V-speed",      _vert_col(vel.y) + "%.4f u/s" % vel.y + C_RESET)
	txt += _row("3D magnitude", C_VAL + "%.4f u/s" % vel.length() + C_RESET)
	txt += _row("H angle",      C_DIM + "%.2f°" % rad_to_deg(atan2(vel.x, vel.z)) + C_RESET)
	txt += _row("Move dir",     C_DIM + _facing_cardinal(atan2(-vel.x, -vel.z)) + C_RESET)
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	txt += _row("Input len",    C_DIM + "%.3f" % input_dir.length() + C_RESET)
	if input_dir.length() > 0.05:
		txt += _row("Input X",     C_DIM + "%.3f" % input_dir.x + C_RESET)
		txt += _row("Input Y",     C_DIM + "%.3f" % input_dir.y + C_RESET)

	# Input vs velocity alignment
	if input_dir.length() > 0.05 and h_spd > 0.5:
		var cam_fwd2 := _get_camera_forward()
		if cam_fwd2 != Vector3.ZERO:
			var cam_basis_x = cam_fwd2.cross(Vector3.UP).normalized()
			var world_input = (cam_fwd2 * -input_dir.y + cam_basis_x * input_dir.x).normalized()
			var vel_dir = Vector3(vel.x, 0, vel.z).normalized()
			var alignment = clampf(world_input.dot(vel_dir), -1.0, 1.0)
			var align_deg = rad_to_deg(acos(alignment))
			var align_col = C_GOOD if align_deg < 20.0 else (C_WARN if align_deg < 60.0 else C_DANGER)
			txt += _row("Input→vel °",  align_col + "%.1f°" % align_deg + C_RESET)
	txt += "\n"

	var cur_h    := Vector2(vel.x, vel.z).length()
	var prev_h   := Vector2(_prev_velocity.x, _prev_velocity.z).length()
	var frame_dt := 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	var h_accel  := (cur_h - prev_h) / frame_dt
	var v_accel  := (vel.y - _prev_velocity.y) / frame_dt
	var accel_col := C_GOOD if abs(h_accel) < 50 else (C_WARN if abs(h_accel) < 150 else C_DANGER)
	txt += _header("◆ ACCELERATION")
	txt += _row("H-accel",      accel_col + "%.2f u/s²" % h_accel + C_RESET)
	txt += _row("V-accel",      _vert_col(v_accel / 10.0) + "%.2f u/s²" % v_accel + C_RESET)
	txt += _row("3D accel",     C_DIM + "%.2f u/s²" % ((vel - _prev_velocity).length() / frame_dt) + C_RESET)
	txt += _row("Peak H-accel", C_WARN + "%.2f u/s²" % session_peak_h_accel + C_RESET)
	txt += _row("Peak H-decel", C_WARN + "%.2f u/s²" % session_peak_h_decel + C_RESET)
	txt += "\n"

	# ── NEW: AIR CONTROL SECTION ──────────────────────────────
	txt += _header("◆ AIR CONTROL & FRICTION")
	var is_airborne := not player.is_on_floor()
	if is_airborne:
		var ac_col = C_DANGER if current_air_control < 0.05 else (C_WARN if current_air_control < 0.2 else C_GOOD)
		txt += _row("State",        C_ACCENT + current_friction_label + C_RESET)
		txt += _row("Air ctrl",     ac_col + "%.4f" % current_air_control + C_RESET)
		txt += _mini_bar_row("Ctrl %", current_air_control)
		txt += _row("Air resist",   C_DIM + "%.4f /frame" % current_air_resist + C_RESET)
		# Effective speed lost per second to air resistance
		var resist_loss_s := current_air_resist * float(Engine.physics_ticks_per_second) * cur_h
		txt += _row("Resist loss",  C_DIM + "%.4f u/s²" % resist_loss_s + C_RESET)
		# How much horizontal speed player can actually add with full input
		var max_air_spd := maxf(cur_h, 6.0)
		var potential_delta := (max_air_spd - cur_h) * current_air_control
		txt += _row("Max Δspd",     C_DIM + "%.4f u/s" % potential_delta + C_RESET)
		# Input effectiveness: how much of the max delta is being used
		if input_dir.length() > 0.05:
			txt += _row("Input eff.",   C_GOOD + "%.1f%%" % (input_dir.length() * 100.0) + C_RESET)
		else:
			txt += _row("Input eff.",   C_DIM + "0.0%" + C_RESET)
		txt += _row("Coyote left",  _coyote_display() + C_RESET)
	else:
		# Ground friction
		txt += _row("Surface",      C_ACCENT + current_friction_label + C_RESET)
		var fric_col = C_GOOD if current_ground_friction > 0.5 else (C_WARN if current_ground_friction > 0.1 else C_DANGER)
		if current_friction_label.begins_with("Ice"):
			txt += _row("Ice ctrl",     fric_col + "0.01 (lerp)" + C_RESET)
		elif current_friction_label == "Slide (×0.98/f)":
			txt += _row("Slide mult",   C_WARN + "0.98 / frame" + C_RESET)
			var spd_at_1s := cur_h * pow(0.98, 60.0)
			txt += _row("Spd @1s",      C_DIM + "%.3f u/s" % spd_at_1s + C_RESET)
		elif current_friction_label == "Normal (100/s)":
			txt += _row("Decel",        C_GOOD + "100.0 u/s²" + C_RESET)
			if cur_h > 0.0:
				var stop_time := cur_h / 100.0
				txt += _row("Stop in",    C_DIM + "%.4f s" % stop_time + C_RESET)
		else:
			txt += _row("Friction",     fric_col + "%.4f" % current_ground_friction + C_RESET)
		txt += _row("Coyote left",  _coyote_display() + C_RESET)
	txt += "\n"

	# ── Graphs ────────────────────────────────────────────────
	txt += _header("◆ H-SPEED  [0 ──► 60 u/s]")
	txt += _ascii_graph(speed_history, 60.0, 7)
	txt += "\n"
	txt += _header("◆ V-SPEED  [fall ◄─ 0 ─► rise]")
	txt += _ascii_graph_bipolar(vert_history, 30.0, 4)
	txt += "\n"
	txt += _header("◆ H-ACCEL  [decel ◄─ 0 ─► accel]")
	txt += _ascii_graph_bipolar(accel_history, 200.0, 4)
	txt += "\n"
	txt += _header("◆ GRAVITY MULT  [0 ──► 4x]")
	txt += _ascii_graph(gravity_mult_history, 4.0, 4)
	txt += "\n"
	txt += _header("◆ AIR CONTROL  [0 ──► 1.0]")
	txt += _ascii_graph(air_control_history, 1.0, 4)

	label_left.text = txt

func _coyote_display() -> String:
	var ct: float = _prop(player, "coyote_time_counter", 0.0)
	var cd: float = _prop(player, "coyote_time_duration", 0.15)
	if ct <= 0.0:
		return C_DIM + "—"
	var pct := ct / maxf(cd, 0.0001)
	var c := C_GOOD if pct > 0.5 else (C_WARN if pct > 0.2 else C_DANGER)
	return c + "%.4f s (%.0f%%)" % [ct, pct * 100.0]

# ═════════════════════════════════════════════════════════════
#  MIDDLE COLUMN — State machine · Air Control · Internals · Abilities · Jump stats
# ═════════════════════════════════════════════════════════════
func _update_mid() -> void:
	var txt := ""
	if not player or not is_instance_valid(player):
		label_mid.text = ""
		return

	txt += _header("◆ STATE MACHINE")
	txt += _row("Current",      C_GOOD + "[b]" + last_state_name + "[/b]" + C_RESET)
	txt += _row("Time in state",C_VAL + "%.4f s" % state_duration + C_RESET)
	txt += _row("Enter H-spd",  C_DIM + "%.3f u/s" % state_enter_speed + C_RESET)
	txt += _row("Peak H-spd",   C_WARN + "%.3f u/s" % state_peak_speed + C_RESET)
	txt += _row("Previous",     C_DIM + previous_state_name + C_RESET)
	txt += _row("Prev dur",     C_DIM + "%.4f s" % previous_state_dur + C_RESET)
	if state_history.size() > 0:
		txt += C_DIM + "  History:\n" + C_RESET
		for i in min(state_history.size(), 5):
			var e = state_history[i]
			txt += C_DIM + "    [%d] %s  %.2fs\n" % [i + 1, e["name"], e["dur"]] + C_RESET
	txt += "\n"

	# ── NEW: AIR TIME & GROUND TIME RATIO ─────────────────────
	txt += _header("◆ AIR / GROUND TIME")
	var total_time := maxf(air_time_total + ground_time_total, 0.0001)
	var air_pct    := air_time_total / total_time
	var ground_pct := ground_time_total / total_time
	txt += _row("Air time",     C_ACCENT + "%.1f s" % air_time_total + C_RESET)
	txt += _row("Ground time",  C_DIM + "%.1f s" % ground_time_total + C_RESET)
	txt += _row("Air %",        C_ACCENT + "%.1f%%" % (air_pct * 100.0) + C_RESET)
	txt += _mini_bar_row("Air/Gnd", air_pct)
	txt += "\n"

	txt += _header("◆ ACTIVE STATE INTERNALS")
	if state_machine and state_machine.get("current_state") != null:
		var cs = state_machine.current_state
		match last_state_name:

			"IdleState":
				var h := Vector2(player.velocity.x, player.velocity.z).length()
				txt += _row("H-speed",      C_VAL + "%.4f u/s" % h + C_RESET)
				txt += _row("Deceleration", C_VAL + "100.0 u/s²" + C_RESET)
				if h > 0.01:
					txt += _row("Stop in",    C_DIM + "%.4f s" % (h / 100.0) + C_RESET)
				txt += _row("Ice mode",     _bool(_prop(player, "is_on_ice", false) as bool))
				if _prop(player, "is_on_ice", false):
					txt += _row("Ice decel",  C_WARN + "100 × 0.01 = 1.0 u/s²" + C_RESET)
					txt += _row("Stop in",    C_DIM + "%.4f s" % (h / 1.0) + C_RESET)
				txt += _row("Decelerating", _bool(h > 0.01))

			"WalkingState":
				var h := Vector2(player.velocity.x, player.velocity.z).length()
				txt += _row("Target speed", C_VAL + "10.0 u/s" + C_RESET)
				txt += _row("H-speed",      C_VAL + "%.4f u/s" % h + C_RESET)
				txt += _row("Delta to tgt", C_DIM + "%.4f" % (10.0 - h) + C_RESET)
				txt += _row("Ice mode",     _bool(_prop(player, "is_on_ice", false) as bool))
				if _prop(player, "is_on_ice", false):
					txt += _row("Ice lerp",   C_WARN + "accel×0.5–1.0" + C_RESET)
					txt += _row("Dir change", C_WARN + "×0.5 control" + C_RESET)
				txt += _row("Rot speed",    C_DIM + "10.0 rad/s" + C_RESET)
				# Time to reach target speed estimate
				var delta_spd := 10.0 - h
				if delta_spd > 0.01:
					txt += _row("~Time to tgt", C_DIM + "instant (direct)" + C_RESET)

			"RunningState":
				var h := Vector2(player.velocity.x, player.velocity.z).length()
				txt += _row("Target speed", C_VAL + "20.0 u/s" + C_RESET)
				txt += _row("H-speed",      C_VAL + "%.4f u/s" % h + C_RESET)
				txt += _row("Delta to tgt", C_DIM + "%.4f" % (20.0 - h) + C_RESET)
				txt += _row("Ice mode",     _bool(_prop(player, "is_on_ice", false) as bool))
				if _prop(player, "is_on_ice", false):
					txt += _row("Ice lerp",   C_WARN + "accel×0.5–1.0" + C_RESET)
				txt += _row("Rot speed",    C_DIM + "12.0 rad/s" + C_RESET)

			"JumpingState":
				var jt: float = _prop(cs, "jump_time", 0.0)
				var gm: float = _prop(cs, "gravity_multiplier", 1.0)
				var lj: bool  = _prop(cs, "is_long_jump", false)
				var dm: bool  = _prop(cs, "used_dash_momentum", false)
				var jv: float = _prop(cs, "jump_velocity", 15.0)
				var pt: float = _prop(cs, "peak_time", 0.0)
				var hd: float = _prop(cs, "horizontal_movement_decel", 0.8)
				var phase := "ASCENT"
				if player.velocity.y <= 0: phase = "→FALLING"
				elif jt >= pt and jt < pt + 0.05: phase = "PEAK"
				txt += _row("Jump time",    C_VAL + "%.4f s" % jt + C_RESET)
				txt += _row("Jump vel",     C_VAL + "%.4f u/s" % jv + C_RESET)
				txt += _row("vel.Y now",    _vert_col(player.velocity.y) + "%.4f" % player.velocity.y + C_RESET)
				txt += _row("Phase",        C_WARN + phase + C_RESET)
				txt += _row("Gravity x",    _grav_col(gm) + "%.4fx" % gm + C_RESET)
				txt += _row("Long jump",    _bool(lj))
				txt += _row("Dash jump",    _bool(dm))
				txt += _row("H decel",      C_DIM + "%.3f on entry" % hd + C_RESET)
				# Air control summary
				var ac := 0.20 if dm else 0.50
				var ar := 0.003 if dm else 0.005
				txt += _row("Air ctrl",     (C_WARN if dm else C_GOOD) + "%.2f" % ac + C_RESET)
				txt += _row("Air resist",   C_DIM + "%.3f/frame" % ar + C_RESET)
				var h_now := Vector2(player.velocity.x, player.velocity.z).length()
				var resist_loss := ar * float(Engine.physics_ticks_per_second) * h_now
				txt += _row("Resist loss",  C_DIM + "%.3f u/s²" % resist_loss + C_RESET)
				txt += _row("Max air spd",  C_DIM + "%.3f u/s" % maxf(h_now, 6.0) + C_RESET)
				txt += _mini_bar_row("Time", clampf(jt / 0.5, 0.0, 1.0))

			"FallingState":
				var ft: float = _prop(cs, "fall_time", 0.0)
				var iv: float = _prop(cs, "initial_fall_velocity", 0.0)
				var gm := 1.0
				if ft < 0.1:   gm = 1.0
				elif ft < 0.3: gm = lerp(1.0, 2.2, (ft - 0.1) / 0.2)
				else:          gm = 2.2
				txt += _row("Fall time",    C_VAL + "%.4f s" % ft + C_RESET)
				txt += _row("Init vel.Y",   C_DIM + "%.4f u/s" % iv + C_RESET)
				txt += _row("vel.Y now",    _vert_col(player.velocity.y) + "%.4f" % player.velocity.y + C_RESET)
				txt += _row("Gravity x",    _grav_col(gm) + "%.4fx" % gm + C_RESET)
				txt += _row("Terminal?",    _bool(player.velocity.y <= -30.0))
				txt += _row("Terminal vel", C_DIM + "-30.0 u/s" + C_RESET)
				txt += _row("Air ctrl",     C_VAL + "0.25" + C_RESET)
				txt += _row("Air resist",   C_DIM + "0.010/frame" + C_RESET)
				var h_now := Vector2(player.velocity.x, player.velocity.z).length()
				var resist_loss := 0.010 * float(Engine.physics_ticks_per_second) * h_now
				txt += _row("Resist loss",  C_DIM + "%.3f u/s²" % resist_loss + C_RESET)
				txt += _mini_bar_row("Grav", clampf(gm / 2.2, 0.0, 1.0))

			"DoubleJumpState":
				var jt: float = _prop(cs, "jump_elapsed_time", 0.0)
				var at: float = _prop(cs, "ascent_time", 0.15)
				var pt: float = _prop(cs, "peak_time", 0.05)
				var dm: float = _prop(cs, "descent_multiplier", 3.0)
				var jv: float = _prop(cs, "jump_velocity", 16.0)
				var phase := "ASCENT"
				if jt >= at and jt < at + pt: phase = "PEAK"
				elif jt >= at + pt:           phase = "DESCENT"
				txt += _row("Elapsed",      C_VAL + "%.4f s" % jt + C_RESET)
				txt += _row("Init vel",     C_VAL + "%.4f u/s" % jv + C_RESET)
				txt += _row("vel.Y now",    _vert_col(player.velocity.y) + "%.4f" % player.velocity.y + C_RESET)
				txt += _row("Phase",        C_WARN + phase + C_RESET)
				txt += _row("Ascent time",  C_DIM + "%.3f s" % at + C_RESET)
				txt += _row("Peak time",    C_DIM + "%.3f s" % pt + C_RESET)
				txt += _row("Descent mult", C_VAL + "%.3fx" % dm + C_RESET)
				txt += _row("Air ctrl",     C_DANGER + "0.08 (very low)" + C_RESET)
				txt += _row("Air resist",   C_DIM + "0.002/frame" + C_RESET)
				txt += _row("Max air spd",  C_DIM + "3.0 u/s (conservative)" + C_RESET)

			"DodgeDashState":
				var dt: float  = _prop(cs, "dash_timer", 0.0)
				var dd: float  = _prop(cs, "dash_duration", 0.3)
				var ds: float  = _prop(cs, "dash_speed", 100.0)
				var cd: float  = _prop(cs, "cooldown_timer", 0.0)
				var md: float  = _prop(cs, "max_dash_distance", 10.0)
				var air: bool  = _prop(cs, "is_air_dash", false)
				var sp: Variant = cs.get("dash_start_position")
				var traveled := 0.0
				if sp is Vector3:
					traveled = player.global_position.distance_to(sp as Vector3)
				var decel_f := 1.0 - clampf(dt / dd, 0.0, 1.0)
				var cur_ds  := ds * decel_f
				txt += _row("Timer",        C_VAL + "%.4f / %.3f s" % [dt, dd] + C_RESET)
				txt += _mini_bar_row("Progress", dt / dd if dd > 0 else 0.0)
				txt += _row("Base speed",   C_VAL + "%.2f u/s" % ds + C_RESET)
				txt += _row("Cur speed",    C_WARN + "%.3f u/s" % cur_ds + C_RESET)
				txt += _row("H-speed now",  C_VAL + "%.4f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)
				txt += _row("Dist",         C_DIM + "%.3f / %.1f u" % [traveled, md] + C_RESET)
				txt += _mini_bar_row("Distance", traveled / md if md > 0 else 0.0)
				txt += _row("Decel factor", C_DIM + "%.4f" % decel_f + C_RESET)
				txt += _row("Cooldown",     (C_WARN if cd > 0 else C_GOOD) + "%.4f s" % cd + C_RESET)
				txt += _row("Air dash",     _bool(air))
				txt += _row("Air ctrl",     C_DANGER + "0.0 (none)" + C_RESET)
				txt += _row("Exit momentum",C_DIM + "×0.6 on normal exit" + C_RESET)
				txt += _row("iFrame dur",   C_DIM + "0.4 s" + C_RESET)
				var ddir: Variant = cs.get("dash_direction")
				if ddir is Vector3:
					var dd3 := ddir as Vector3
					txt += _row("Dash dir",   C_DIM + "(%.2f,%.2f,%.2f)" % [dd3.x, dd3.y, dd3.z] + C_RESET)

			"WallJumpingState":
				var wt: float  = _prop(cs, "wall_jump_timer", 0.0)
				var ml: float  = _prop(cs, "momentum_lock_duration", 0.35)
				var fd: float  = _prop(cs, "momentum_fade_duration", 0.15)
				var tl: float  = _prop(cs, "total_lock_time", 0.5)
				var wjv: float = _prop(cs, "wall_jump_velocity", 5.0)
				var hf: float  = _prop(cs, "wall_jump_horizontal_force", 12.0)
				var ub: float  = _prop(cs, "wall_jump_upward_boost", 2.0)
				var wdir: Variant = cs.get("wall_direction")
				var phase := "LOCK"
				var ctrl  := 0.0
				if wt >= ml and wt < tl:
					phase = "FADE"
					ctrl  = (wt - ml) / fd
				elif wt >= tl:
					phase = "FREE"
					ctrl  = 1.0
				var ctrl_val := 0.0
				if phase == "LOCK":   ctrl_val = 0.0
				elif phase == "FADE": ctrl_val = 0.1 * ctrl
				else:                 ctrl_val = 0.3
				txt += _row("Timer",        C_VAL + "%.4f s" % wt + C_RESET)
				txt += _row("Phase",        C_WARN + "[b]" + phase + "[/b]" + C_RESET)
				txt += _mini_bar_row("Lock", clampf(wt / ml if ml > 0 else 0.0, 0.0, 1.0))
				txt += _row("Control",      C_DIM + "%.4f" % ctrl + C_RESET)
				txt += _row("Air ctrl",     (C_DANGER if ctrl_val < 0.05 else (C_WARN if ctrl_val < 0.2 else C_GOOD)) + "%.4f" % ctrl_val + C_RESET)
				txt += _mini_bar_row("Ctrl", ctrl_val)
				txt += _row("Jump vel",     C_VAL + "%.3f u/s" % wjv + C_RESET)
				txt += _row("Horiz force",  C_VAL + "%.3f u/s" % hf + C_RESET)
				txt += _row("Upward boost", C_DIM + "%.3f u/s" % ub + C_RESET)
				txt += _row("vel.Y now",    _vert_col(player.velocity.y) + "%.4f" % player.velocity.y + C_RESET)
				txt += _row("H-speed now",  C_VAL + "%.4f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)
				if wdir is Vector3:
					var wd := wdir as Vector3
					txt += _row("Wall normal", C_DIM + "(%.2f,%.2f,%.2f)" % [wd.x, wd.y, wd.z] + C_RESET)

			"WallSlidingState":
				var ss: float   = _prop(cs, "slide_speed", -2.0)
				var ms: float   = _prop(cs, "min_slide_speed", -5.0)
				var sf: float   = _prop(cs, "slide_friction", 0.95)
				var wn: Variant = cs.get("wall_normal")
				txt += _row("Slide speed",  C_VAL + "%.4f u/s" % ss + C_RESET)
				txt += _row("Min spd",      C_DIM + "%.4f u/s" % ms + C_RESET)
				txt += _row("Wall friction",C_DIM + "%.4f" % sf + C_RESET)
				txt += _row("vel.Y now",    _vert_col(player.velocity.y) + "%.4f" % player.velocity.y + C_RESET)
				txt += _row("H-speed",      C_VAL + "%.4f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)
				txt += _row("Air ctrl",     C_DIM + "perpendicular only" + C_RESET)
				txt += _row("Grav mult",    C_DIM + "0.30×" + C_RESET)
				if wn is Vector3:
					var wn3 := wn as Vector3
					txt += _row("Wall normal", C_DIM + "(%.2f,%.2f,%.2f)" % [wn3.x, wn3.y, wn3.z] + C_RESET)

			"RailGrindingState":
				var gs: float = _prop(cs, "grind_exit_speed", 15.0)
				var ls: float = _prop(cs, "lerp_speed", 50.0)
				var jv: float = _prop(cs, "jump_velocity", 10.0)
				txt += _row("Grind speed",  C_VAL + "%.3f u/s" % gs + C_RESET)
				txt += _row("Lerp speed",   C_DIM + "%.2f" % ls + C_RESET)
				txt += _row("Jump vel",     C_DIM + "%.3f u/s" % jv + C_RESET)
				txt += _row("H-speed now",  C_GOOD + "%.4f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)
				txt += _row("vel.Y now",    C_DIM + "%.4f" % player.velocity.y + C_RESET)
				txt += _row("Timer done",   _bool(_prop(cs, "grind_timer_complete", true) as bool))
				txt += _row("Gravity",      C_ACCENT + "0.0 (disabled)" + C_RESET)

			"GrappleHookState":
				var mode: Variant = cs.get("grapple_mode")
				var gp: Variant   = cs.get("grapple_point")
				var rl: float     = _prop(cs, "rope_length", 0.0)
				var gs: float     = _prop(cs, "grapple_speed", 30.0)
				var gpf: float    = _prop(cs, "grapple_pull_force", 25.0)
				var rb: float     = _prop(cs, "release_boost", 15.0)
				var scstr: float  = _prop(cs, "swing_control_strength", 8.0)
				var is_grp: bool  = _prop(cs, "is_grappling", false)
				txt += _row("Mode",         C_WARN + str(mode) + C_RESET)
				txt += _row("Is grappling", _bool(is_grp))
				txt += _row("Rope length",  C_VAL + "%.4f u" % rl + C_RESET)
				txt += _row("Speed",        C_DIM + "%.2f u/s" % gs + C_RESET)
				txt += _row("Pull force",   C_DIM + "%.2f" % gpf + C_RESET)
				txt += _row("Swing ctrl",   C_DIM + "%.2f" % scstr + C_RESET)
				txt += _row("Rel. boost",   C_DIM + "%.2f u/s" % rb + C_RESET)
				txt += _row("Grav mult",    C_DIM + "0.30× (pull) / full (swing)" + C_RESET)
				if gp is Vector3:
					var dist: float = player.global_position.distance_to(gp as Vector3)
					txt += _row("To target",  C_VAL + "%.4f u" % dist + C_RESET)
					txt += _mini_bar_row("Dist", clampf(1.0 - dist / 30.0, 0.0, 1.0))
				txt += _row("H-speed",      C_VAL + "%.4f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)
				txt += _row("vel.Y",        _vert_col(player.velocity.y) + "%.4f" % player.velocity.y + C_RESET)

			"SlidingState":
				var sv: Variant = cs.get("slide_velocity")
				var sd: Variant = cs.get("slide_direction")
				var cur_spd := (sv as Vector3).length() if sv is Vector3 else 0.0
				txt += _row("Slide speed",  C_VAL + "%.4f u/s" % cur_spd + C_RESET)
				txt += _row("H-speed",      C_VAL + "%.4f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)
				txt += _row("Friction",     C_DIM + "×0.98 / frame" + C_RESET)
				# Speed in 1s with 0.98/frame friction at 60fps
				var spd_at_1s := cur_spd * pow(0.98, 60.0)
				var spd_at_2s := cur_spd * pow(0.98, 120.0)
				txt += _row("Spd @1s",      C_DIM + "%.4f u/s" % spd_at_1s + C_RESET)
				txt += _row("Spd @2s",      C_DIM + "%.4f u/s" % spd_at_2s + C_RESET)
				txt += _row("Min spd",      C_DIM + "0.50 u/s (stop)" + C_RESET)
				if cur_spd > 0.5:
					# Approximate frames until stop (solve cur_spd * 0.98^n = 0.5)
					var frames_left := log(0.5 / maxf(cur_spd, 0.001)) / log(0.98)
					txt += _row("Stop in",    C_DIM + "%.0f frames" % frames_left + C_RESET)
				if sd is Vector3:
					var sd3 := sd as Vector3
					txt += _row("Slide dir",  C_DIM + "(%.2f,%.2f,%.2f)" % [sd3.x, sd3.y, sd3.z] + C_RESET)

			"SpinAttackState":
				var st: float = _prop(cs, "spin_timer", 0.0)
				var sd: float = _prop(cs, "spin_duration", 0.2)
				var hs: float = _prop(cs, "hover_strength", 25.0)
				var pr: float = _prop(cs, "pushback_radius", 3.0)
				var pf: float = _prop(cs, "pushback_force", 25.0)
				var dmg: int  = _prop(cs, "damage", 2)
				txt += _row("Timer",        C_VAL + "%.4f / %.3f s" % [st, sd] + C_RESET)
				txt += _mini_bar_row("Progress", st / sd if sd > 0 else 0.0)
				txt += _row("Hover str",    C_DIM + "%.2f" % hs + C_RESET)
				txt += _row("Radius",       C_DIM + "%.2f u" % pr + C_RESET)
				txt += _row("Push force",   C_DIM + "%.2f" % pf + C_RESET)
				txt += _row("Damage",       C_VAL + str(dmg) + C_RESET)
				txt += _row("Air ctrl",     C_ACCENT + "air: 25.0/s (high!)" + C_RESET)
				txt += _row("Grav mult",    C_DIM + "0.50× in air" + C_RESET)
				txt += _row("H-mom exit",   C_DIM + "×0.80" + C_RESET)
				txt += _row("On floor",     _bool(player.is_on_floor()))
				txt += _row("vel.Y now",    _vert_col(player.velocity.y) + "%.4f" % player.velocity.y + C_RESET)

			"LedgeHangingState":
				var climbing: bool = _prop(cs, "is_climbing", false)
				var lp: Variant    = cs.get("ledge_position")
				var ln: Variant    = cs.get("ledge_normal")
				var ss: float      = _prop(cs, "shimmy_speed", 3.0)
				var cu: float      = _prop(cs, "climb_up_duration", 0.5)
				txt += _row("Climbing",     _bool(climbing))
				txt += _row("Shimmy speed", C_DIM + "%.3f u/s" % ss + C_RESET)
				txt += _row("Climb dur",    C_DIM + "%.3f s" % cu + C_RESET)
				txt += _row("Gravity",      C_ACCENT + "0.0 (suspended)" + C_RESET)
				txt += _row("Velocity",     C_ACCENT + "ZERO (locked)" + C_RESET)
				if lp is Vector3:
					var lp3 := lp as Vector3
					txt += _row("Ledge pos",  C_DIM + "(%.2f,%.2f,%.2f)" % [lp3.x, lp3.y, lp3.z] + C_RESET)
					txt += _row("Dist",       C_VAL + "%.4f u" % player.global_position.distance_to(lp3) + C_RESET)
				if ln is Vector3:
					var ln3 := ln as Vector3
					txt += _row("Wall normal", C_DIM + "(%.2f,%.2f,%.2f)" % [ln3.x, ln3.y, ln3.z] + C_RESET)

			_:
				txt += C_DIM + "  (no detailed data for this state)\n" + C_RESET
	else:
		txt += C_DIM + "  StateMachine not ready\n" + C_RESET
	txt += "\n"

	txt += _header("◆ ABILITY READINESS")
	var has_dj : bool  = _prop(player, "can_double_jump",   false)
	var used_dj: bool  = _prop(player, "has_double_jumped", false)
	var has_ad : bool  = _prop(player, "can_air_dash",      false)
	var used_ad: bool  = _prop(player, "has_air_dashed",    false)
	var can_lj : bool  = _prop(player, "can_long_jump",     false)
	var lj_t   : float = _prop(player, "long_jump_timer",   0.0)
	var lj_w   : float = _prop(player, "long_jump_window",  0.3)
	var sdm_raw: Variant = _prop(player, "stored_dash_momentum", null)
	var sdm_len: float = (sdm_raw as Vector3).length() if sdm_raw is Vector3 else 0.0
	var wj_cd  : float = _prop(player, "wall_jump_cooldown", 0.0)
	var ct     : float = _prop(player, "coyote_time_counter", 0.0)
	var cd_dur : float = _prop(player, "coyote_time_duration", 0.15)
	var dash_cd   : float = 0.0
	var dash_ready: bool  = true
	if state_machine and state_machine.get("states") != null:
		var ds = state_machine.states.get("dodgedashstate")
		if ds:
			dash_cd    = _prop(ds, "cooldown_timer", 0.0) as float
			dash_ready = _prop(ds, "can_dash", true) as bool
	txt += _row("Double jump",  (C_GOOD + "READY" if has_dj and not used_dj else (C_DIM + "used" if used_dj else C_DANGER + "locked")) + C_RESET)
	txt += _row("Air dash",     (C_GOOD + "READY" if has_ad and not used_ad else (C_DIM + "used" if used_ad else C_DANGER + "locked")) + C_RESET)
	txt += _row("Wall jump",    (C_GOOD + "READY" if wj_cd <= 0.0 else C_WARN + "%.4f s" % wj_cd) + C_RESET)
	txt += _row("Dash",         (C_GOOD + "READY" if dash_ready else C_WARN + "%.4f s" % dash_cd) + C_RESET)
	if not dash_ready:
		txt += _mini_bar_row("Dash CD", 1.0 - clampf(dash_cd / 0.1, 0.0, 1.0))
	txt += _row("Coyote",       (C_GOOD + "%.4f s" % ct if ct > 0.0 else C_DIM + "—") + C_RESET)
	if ct > 0.0:
		txt += _mini_bar_row("Coyote", ct / cd_dur)
	txt += _row("Long jump",    (C_GOOD + "READY  %.3fs" % lj_t if can_lj else C_DIM + "—") + C_RESET)
	if can_lj:
		txt += _mini_bar_row("LJ window", lj_t / lj_w if lj_w > 0 else 0.0)
	txt += _row("Dash momentum",(C_WARN + "%.4f u/s" % sdm_len if sdm_len > 0.01 else C_DIM + "none") + C_RESET)
	if sdm_raw is Vector3:
		var sdm3 := sdm_raw as Vector3
		if sdm3.length() > 0.01:
			txt += _row("  direction", C_DIM + "(%.2f,%.2f,%.2f)" % [sdm3.x, sdm3.y, sdm3.z] + C_RESET)
	txt += "\n"

	txt += _header("◆ JUMP STATS")
	if tracking_jump:
		var cur_h    := maxf(0.0, player.global_position.y - launch_y)
		var cur_h_off := maxf(0.0, player.global_position.y - ground_y_at_launch)
		var cur_dist := Vector2(player.global_position.x - launch_pos.x, player.global_position.z - launch_pos.z).length()
		txt += _row("Height NOW",     C_WARN + "%.4f u" % cur_h + C_RESET)
		txt += _row("Off ground NOW", C_ACCENT + "%.4f u" % cur_h_off + C_RESET)
		txt += _row("Horiz dist",     C_WARN + "%.4f u" % cur_dist + C_RESET)
		txt += _row("Air time",       C_WARN + "%.4f s" % jump_airtime_counter + C_RESET)
		txt += _row("Apex H-spd",     C_VAL  + "%.4f u/s" % last_jump_apex_speed + C_RESET)
		txt += _row("Launch Y",       C_DIM  + "%.4f" % launch_y + C_RESET)
		txt += _row("Peak Y",         C_DIM  + "%.4f" % peak_y + C_RESET)
		txt += _row("Rise so far",    C_DIM  + "%.4f u" % (peak_y - launch_y) + C_RESET)
	else:
		txt += _row("Last height",    C_VAL + "%.4f u" % last_jump_height + C_RESET)
		txt += _row("Last off-gnd",   C_ACCENT + "%.4f u" % last_jump_height + C_RESET)  # same as height when started on ground
		txt += _row("Last h-dist",    C_VAL + "%.4f u" % last_jump_horizontal_distance + C_RESET)
		txt += _row("Last air t",     C_VAL + "%.4f s" % last_jump_airtime + C_RESET)
		txt += _row("Apex H-spd",     C_VAL + "%.4f u/s" % last_jump_apex_speed + C_RESET)
		txt += _row("Last dash dst",  C_DIM + "%.4f u" % last_dash_distance + C_RESET)
		if last_landing_pos != Vector3.ZERO:
			txt += _row("Land pos",   C_DIM + "(%.1f,%.1f,%.1f)" % [last_landing_pos.x, last_landing_pos.y, last_landing_pos.z] + C_RESET)

	label_mid.text = txt

# ═════════════════════════════════════════════════════════════
#  RIGHT COLUMN — Player state · Upgrades · HU-3 · Paint · Economy · Checkpoint · Session
# ═════════════════════════════════════════════════════════════
func _update_right() -> void:
	var txt := ""
	if not player or not is_instance_valid(player):
		label_right.text = ""
		return

	txt += _header("◆ PLAYER STATE")
	var health : int   = game_manager.get_player_health() if game_manager else 0
	var max_hp : int   = game_manager.get_player_max_health() if game_manager else 3
	var is_inv : bool  = _prop(player, "is_invulnerable", false)
	var inv_t  : float = _prop(player, "invulnerability_timer", 0.0)
	var inv_d  : float = _prop(player, "invulnerability_duration", 1.5)
	var is_dead: bool  = _prop(player, "is_dead", false)
	var flashing: bool = _prop(player, "should_flash", false)
	var hp_col := C_GOOD if health >= max_hp else (C_WARN if health > 1 else C_DANGER)
	txt += _row("Health",       hp_col + _heart_bar(health, max_hp) + "  %d/%d" % [health, max_hp] + C_RESET)
	txt += _row("Dead",         _bool(is_dead, true))
	txt += _row("Invulnerable", _bool(is_inv))
	if is_inv:
		txt += _row("Inv timer",  C_WARN + "%.4f / %.2f s" % [inv_t, inv_d] + C_RESET)
		txt += _mini_bar_row("Inv bar", inv_t / inv_d if inv_d > 0 else 0.0)
		txt += _row("Flashing",   _bool(flashing))
	var death_y: float = _prop(player, "death_y_threshold", -50.0)
	var margin_to_death := player.global_position.y - death_y
	var death_col := C_DANGER if margin_to_death < 10.0 else (C_WARN if margin_to_death < 20.0 else C_DIM)
	txt += _row("Death Y",      C_DIM + "%.1f" % death_y + C_RESET)
	txt += _row("Margin",       death_col + "%.2f u" % margin_to_death + C_RESET)
	txt += "\n"

	txt += _header("◆ PURCHASED UPGRADES")
	if game_manager:
		txt += _row("Double Jump",  _bool(game_manager.can_double_jump()))
		txt += _row("Wall Jump",    _bool(game_manager.can_wall_jump()))
		txt += _row("Dash",         _bool(game_manager.can_dash()))
		txt += _row("Speed",        _bool(game_manager.has_speed_upgrade()))
		txt += _row("Health +1",    _bool(game_manager.has_health_upgrade()))
		txt += _row("Damage +1",    _bool(game_manager.has_damage_upgrade()))
		txt += _row("Total",        C_VAL + "%d / 6" % game_manager.get_purchased_upgrades().size() + C_RESET)
	txt += "\n"

	txt += _header("◆ HU-3 COMPANION")
	if hu3 and is_instance_valid(hu3):
		var h3_pos  := hu3.global_position
		var h3_vel  := hu3.velocity
		var h3_spd  := h3_vel.length()
		var h3_dist := player.global_position.distance_to(h3_pos)
		var h3_spd_col := C_GOOD if h3_spd < 20 else (C_WARN if h3_spd < 40 else C_DANGER)
		# FIX: green when close, red when far (was inverted before)
		var dist_col   := C_GOOD if h3_dist < 4 else (C_WARN if h3_dist < 10 else C_DANGER)
		txt += _row("Found",        C_GOOD + "YES" + C_RESET)
		txt += _row("Distance",     dist_col + "%.4f u" % h3_dist + C_RESET)
		# FIX: distance bar fills green when close, transitions to red as HU-3 gets far
		txt += _hu3_dist_bar(h3_dist, 15.0)
		txt += _row("Pos X",        C_DIM + "%.4f" % h3_pos.x + C_RESET)
		txt += _row("Pos Y",        C_DIM + "%.4f" % h3_pos.y + C_RESET)
		txt += _row("Pos Z",        C_DIM + "%.4f" % h3_pos.z + C_RESET)
		txt += _row("Height diff",  _vert_col((h3_pos.y - player.global_position.y) / 5.0) + "%.4f u" % (h3_pos.y - player.global_position.y) + C_RESET)
		txt += _row("Speed",        h3_spd_col + "%.4f u/s" % h3_spd + C_RESET)
		txt += _row("vel.X",        C_DIM + "%.4f" % h3_vel.x + C_RESET)
		txt += _row("vel.Y",        C_DIM + "%.4f" % h3_vel.y + C_RESET)
		txt += _row("vel.Z",        C_DIM + "%.4f" % h3_vel.z + C_RESET)
		# Internal HU-3 state
		var collecting : bool  = _prop(hu3, "is_collecting_gear", false)
		var col_timer  : float = _prop(hu3, "collection_timer", 0.0)
		var col_timeout: float = _prop(hu3, "collection_timeout", 5.0)
		var hover_t    : float = _prop(hu3, "hover_time", 0.0)
		var hover_amp  : float = _prop(hu3, "hover_amplitude", 0.2)
		var hover_freq : float = _prop(hu3, "hover_frequency", 1.5)
		var follow_spd : float = _prop(hu3, "base_follow_speed", 20.0)
		var max_f_spd  : float = _prop(hu3, "follow_max_speed", 35.0)
		var catchup_th : float = _prop(hu3, "catchup_threshold", 5.0)
		var catchup_bst: float = _prop(hu3, "catchup_speed_boost", 5.0)
		var side_off   : float = _prop(hu3, "side_offset", 1.5)
		var fwd_off    : float = _prop(hu3, "forward_offset", 1.0)
		var hover_h    : float = _prop(hu3, "hover_height", 1.5)
		var gear_dst   : float = _prop(hu3, "gear_collection_distance", 8.0)
		var gear_spd   : float = _prop(hu3, "gear_collection_speed", 15.0)
		var sfv_raw    : Variant = _prop(hu3, "smooth_follow_velocity", null)
		var sfv_spd    := (sfv_raw as Vector3).length() if sfv_raw is Vector3 else 0.0
		var follow_accel: float = _prop(hu3, "follow_acceleration", 25.0)
		var follow_damp : float = _prop(hu3, "follow_damping", 0.92)
		txt += _row("Collecting",   _bool(collecting))
		if collecting:
			txt += _row("Col timer",  C_WARN + "%.3f / %.1fs" % [col_timer, col_timeout] + C_RESET)
			txt += _mini_bar_row("Col timeout", col_timer / col_timeout if col_timeout > 0 else 0.0)
		var hover_wave := sin(hover_t * hover_freq) * hover_amp
		txt += _row("Hover time",   C_DIM + "%.3f s" % hover_t + C_RESET)
		txt += _row("Hover offset", C_DIM + "%.4f u" % hover_wave + C_RESET)
		txt += _row("Hover amp",    C_DIM + "%.3f u" % hover_amp + C_RESET)
		txt += _row("Hover freq",   C_DIM + "%.2f Hz" % hover_freq + C_RESET)
		txt += _row("Hover height", C_DIM + "%.2f u" % hover_h + C_RESET)
		txt += _row("Side offset",  C_DIM + "%.2f u" % side_off + C_RESET)
		txt += _row("Fwd offset",   C_DIM + "%.2f u" % fwd_off + C_RESET)
		txt += _row("Follow spd",   C_DIM + "%.2f / %.2f" % [follow_spd, max_f_spd] + C_RESET)
		txt += _row("Follow accel", C_DIM + "%.2f" % follow_accel + C_RESET)
		txt += _row("Follow damp",  C_DIM + "%.3f" % follow_damp + C_RESET)
		txt += _row("Smooth vel",   C_DIM + "%.4f u/s" % sfv_spd + C_RESET)
		txt += _row("Catchup thr",  C_DIM + "%.2f u" % catchup_th + C_RESET)
		txt += _row("Catchup bst",  C_DIM + "%.2fx" % catchup_bst + C_RESET)
		txt += _row("Catchup mode", _bool(h3_dist > catchup_th))
		txt += _row("Gear sense",   C_DIM + "%.2f u" % gear_dst + C_RESET)
		txt += _row("Gear spd",     C_DIM + "%.2f u/s" % gear_spd + C_RESET)
		var is_grinding := last_state_name == "RailGrindingState"
		txt += _row("Speed mult",   (C_WARN + "2.0x  (grind!)" if is_grinding else C_DIM + "1.0x") + C_RESET)
	else:
		txt += C_DANGER + "  HU-3 not in scene\n" + C_RESET
	txt += "\n"

	txt += _header("◆ PAINT SYSTEM")
	if paint_manager and is_instance_valid(paint_manager):
		var paint_amt : int   = _prop(paint_manager, "current_paint_amount", 0)
		var paint_max : int   = _prop(paint_manager, "max_paint_amount", 100)
		var paint_pct : float = float(paint_amt) / maxf(float(paint_max), 1.0)
		var cur_paint : int   = _prop(paint_manager, "current_paint", 0)
		var paint_col := C_GOOD if paint_pct > 0.5 else (C_WARN if paint_pct > 0.2 else C_DANGER)
		var paint_names := {0: "SAVE", 1: "HEAL", 2: "FLY", 3: "COMBAT"}
		var costs       := {0: 20, 1: 20, 2: 20, 3: 10}
		txt += _row("Selected",     C_ACCENT + paint_names.get(cur_paint, "?") + C_RESET)
		txt += _row("Amount",       paint_col + "%d / %d" % [paint_amt, paint_max] + C_RESET)
		txt += _mini_bar_row("Paint", paint_pct)
		txt += _row("Ability cost", C_DIM + str(costs.get(cur_paint, "?")) + " paint" + C_RESET)
		txt += _row("Can use",      _bool(paint_amt >= costs.get(cur_paint, 999)))
		var sw_cd : float = _prop(paint_manager, "switch_cooldown", 0.0)
		txt += _row("Switch CD",    (C_DIM + "%.3f s" % sw_cd if sw_cd > 0 else C_GOOD + "ready") + C_RESET)
	else:
		txt += C_DIM + "  PaintManager not found\n" + C_RESET
	txt += "\n"

	txt += _header("◆ ECONOMY")
	if game_manager:
		txt += _row("Gears",        C_VAL + str(game_manager.get_gear_count()) + C_RESET)
		txt += _row("CRED",         C_VAL + str(game_manager.get_CRED_count()) + C_RESET)
	txt += "\n"

	txt += _header("◆ CHECKPOINT")
	if checkpoint_manager:
		var has_cp : bool = checkpoint_manager.has_active_checkpoint()
		txt += _row("Active",       _bool(has_cp))
		if has_cp:
			var cp     : Vector3 = checkpoint_manager.get_checkpoint_position()
			var cp_rot : Vector3 = checkpoint_manager.get_checkpoint_rotation()
			var dist_cp := player.global_position.distance_to(cp)
			txt += _row("Distance",   C_DIM + "%.3f u" % dist_cp + C_RESET)
			txt += _row("CP Pos",     C_DIM + "(%.1f,%.1f,%.1f)" % [cp.x, cp.y, cp.z] + C_RESET)
			txt += _row("CP Rot Y",   C_DIM + "%.1f°" % rad_to_deg(cp_rot.y) + C_RESET)
	else:
		txt += C_DIM + "  Not found\n" + C_RESET
	txt += "\n"

	# ── NEW: JUMP RECORDS ─────────────────────────────────────
	txt += _header("◆ JUMP RECORDS (Session)")
	txt += _row("Max height",   C_GOOD + "%.4f u" % session_peak_jump_height + C_RESET)
	txt += _row("Max off-gnd",  C_ACCENT + "%.4f u" % session_max_jump_height_off_ground + C_RESET)
	txt += _row("Max h-dist",   C_GOOD + "%.4f u" % session_max_horizontal_jump_dist + C_RESET)
	txt += _row("Max airtime",  C_GOOD + "%.4f s" % session_max_airtime + C_RESET)
	txt += _row("Peak H-speed", C_WARN + "%.4f u/s" % session_peak_speed + C_RESET)
	txt += _row("Peak fall",    C_WARN + "%.4f u/s" % session_peak_fall_speed + C_RESET)
	txt += _row("Peak H-accel", C_WARN + "%.2f u/s²" % session_peak_h_accel + C_RESET)
	txt += _row("Peak H-decel", C_WARN + "%.2f u/s²" % session_peak_h_decel + C_RESET)
	txt += "\n"

	# ── NEW: GAME FEEL / MOVEMENT FEEL BREAKDOWN ──────────────
	txt += _header("◆ GAME FEEL  (current state)")
	var csn := _current_state_name()
	# Responsiveness rating
	var resp_score := _responsiveness_score(csn)
	var resp_col   := C_GOOD if resp_score > 70.0 else (C_WARN if resp_score > 35.0 else C_DANGER)
	txt += _row("Responsivnss", resp_col + "%.0f / 100" % resp_score + C_RESET)
	txt += _mini_bar_row("Resp", resp_score / 100.0)
	# Speed feel
	var h_now := Vector2(player.velocity.x, player.velocity.z).length()
	var speed_feel_pct := clampf(h_now / 60.0, 0.0, 1.0)
	var sf_col := C_GOOD if speed_feel_pct > 0.5 else (C_DIM if speed_feel_pct < 0.1 else C_VAL)
	txt += _row("Speed feel",   sf_col + "%.0f%%" % (speed_feel_pct * 100.0) + C_RESET)
	txt += _mini_bar_row("Speed", speed_feel_pct)
	# Gravity feel (higher = heavier feel)
	var grav_feel := 0.0
	if state_machine and state_machine.get("current_state") != null:
		var csobj = state_machine.current_state
		if csobj and csobj.get("gravity_multiplier") != null:
			grav_feel = clampf((_prop(csobj, "gravity_multiplier", 1.0) as float) / 4.0, 0.0, 1.0)
	txt += _row("Gravity feel", C_DIM + "%.0f%% of max" % (grav_feel * 100.0) + C_RESET)
	txt += _mini_bar_row("Gravity", grav_feel)
	# Air tightness
	var tightness := current_air_control if not player.is_on_floor() else 1.0
	var tight_col  := C_GOOD if tightness > 0.3 else (C_WARN if tightness > 0.05 else C_DANGER)
	txt += _row("Air tightness",tight_col + "%.0f%%" % (tightness * 100.0) + C_RESET)
	txt += _mini_bar_row("Tight", tightness)
	# Momentum retention (how much speed survives a state transition)
	var cs_prev_speed_ratio := state_enter_speed / maxf(state_peak_speed, 0.0001)
	var momentum_pct := clampf(cs_prev_speed_ratio, 0.0, 1.0)
	txt += _row("Momentum ret.", C_DIM + "%.0f%% (entry/peak)" % (momentum_pct * 100.0) + C_RESET)
	txt += "\n"

	txt += _header("◆ SESSION STATS")
	txt += _row("Jumps",        C_VAL + str(session_jump_count) + C_RESET)
	txt += _row("Double jumps", C_VAL + str(session_dbl_jump_count) + C_RESET)
	txt += _row("Wall jumps",   C_VAL + str(session_wall_jump_count) + C_RESET)
	txt += _row("Dashes",       C_VAL + str(session_dash_count) + C_RESET)
	txt += _row("Grapples",     C_VAL + str(session_grapple_count) + C_RESET)
	txt += _row("Spin attacks", C_VAL + str(session_spin_count) + C_RESET)
	txt += _row("Ledge grabs",  C_VAL + str(session_ledge_grab_count) + C_RESET)
	txt += _row("Rail grinds",  C_VAL + str(session_rail_count) + C_RESET)
	txt += _row("Dmg taken",    (C_WARN if session_damage_taken > 0 else C_DIM) + str(session_damage_taken) + " HP" + C_RESET)
	txt += _row("Heals",        C_GOOD + str(session_heals) + " HP" + C_RESET)
	txt += _row("Gears found",  C_VAL + str(session_gears_collected) + C_RESET)
	txt += _row("Last dash dst",C_DIM + "%.4f u" % last_dash_distance + C_RESET)
	# Air/ground ratio
	var total_t := maxf(air_time_total + ground_time_total, 0.001)
	txt += _row("Air time tot", C_DIM + "%.1f s (%.0f%%)" % [air_time_total, (air_time_total / total_t) * 100.0] + C_RESET)

	label_right.text = txt

# ═════════════════════════════════════════════════════════════
#  HELPERS
# ═════════════════════════════════════════════════════════════
func _prop(obj: Object, prop: String, fallback: Variant) -> Variant:
	if obj and obj.has_method("get"):
		var v = obj.get(prop)
		if v != null: return v
	return fallback

func _get_camera_forward() -> Vector3:
	if not player: return Vector3.ZERO
	var cc = player.get_node_or_null("CameraController")
	if cc and cc.has_method("get_camera_forward"):
		return cc.get_camera_forward()
	return Vector3.ZERO

func _facing_cardinal(yaw_rad: float) -> String:
	var deg := fmod(rad_to_deg(yaw_rad) + 360.0, 360.0)
	if   deg < 22.5  or deg >= 337.5: return "S"
	elif deg < 67.5:  return "SW"
	elif deg < 112.5: return "W"
	elif deg < 157.5: return "NW"
	elif deg < 202.5: return "N"
	elif deg < 247.5: return "NE"
	elif deg < 292.5: return "E"
	else:             return "SE"

func _angle_between_yaws(a: float, b: float) -> float:
	return abs(fmod(a - b + 540.0, 360.0) - 180.0)

func _header(title: String) -> String:
	return C_HEADER + "[b]" + title + "[/b]" + C_RESET + "\n"

func _row(key: String, value: String) -> String:
	var pad  : int = max(0, 14 - key.length())
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

func _grav_col(gm: float) -> String:
	if gm <= 0.2:  return C_GOOD
	if gm >= 2.0:  return C_DANGER
	if gm >= 1.0:  return C_WARN
	return C_VAL

func _heart_bar(hp: int, max_hp: int) -> String:
	var s := ""
	for i in max_hp: s += "♥" if i < hp else "♡"
	return s

func _mini_bar_row(label: String, pct: float) -> String:
	pct = clampf(pct, 0.0, 1.0)
	const W := 18
	var filled := int(pct * W)
	var col := C_GOOD if pct > 0.5 else (C_WARN if pct > 0.2 else C_DANGER)
	var bar := C_DIM + "[" + C_RESET + col + "█".repeat(filled) + C_RESET + C_DIM + "░".repeat(W - filled) + "]" + C_RESET
	return _row(label, bar)

# ── NEW: HU-3 specific distance bar (green=close, red=far) ───
func _hu3_dist_bar(dist: float, max_dist: float) -> String:
	var pct := clampf(dist / max_dist, 0.0, 1.0)
	const W := 18
	var filled := int(pct * W)
	# Inverted: more filled = farther = more red
	var col := C_GOOD if pct < 0.3 else (C_WARN if pct < 0.65 else C_DANGER)
	var bar := C_DIM + "[" + C_RESET + col + "█".repeat(filled) + C_RESET + C_DIM + "░".repeat(W - filled) + "]" + C_RESET
	return _row("Dist bar", bar)

# ── NEW: Responsiveness score based on current state ─────────
func _responsiveness_score(csn: String) -> float:
	match csn:
		"IdleState":     return 95.0
		"WalkingState":  return 90.0
		"RunningState":  return 85.0
		"JumpingState":
			if state_machine and state_machine.get("current_state") != null:
				var dm: bool = _prop(state_machine.current_state, "used_dash_momentum", false)
				return 40.0 if dm else 55.0
			return 55.0
		"FallingState":  return 50.0
		"DoubleJumpState": return 20.0
		"DodgeDashState": return 5.0
		"WallJumpingState":
			var wt: float = 0.0
			var ml: float = 0.35
			var tl: float = 0.5
			if state_machine and state_machine.get("current_state") != null:
				wt = _prop(state_machine.current_state, "wall_jump_timer", 0.0)
				ml = _prop(state_machine.current_state, "momentum_lock_duration", 0.35)
				tl = _prop(state_machine.current_state, "total_lock_time", 0.5)
			if wt < ml:   return 0.0
			elif wt < tl: return 15.0
			else:         return 65.0
		"WallSlidingState": return 60.0
		"RailGrindingState": return 30.0
		"GrappleHookState":  return 25.0
		"SlidingState":      return 35.0
		"SpinAttackState":
			return 70.0 if player.is_on_floor() else 80.0
		"LedgeHangingState":
			if state_machine and state_machine.get("current_state") != null:
				var climbing: bool = _prop(state_machine.current_state, "is_climbing", false)
				return 5.0 if climbing else 55.0
			return 55.0
		_: return 50.0

func _speed_char(pct: float) -> String:
	if pct > 0.85: return C_DANGER + "█" + C_RESET
	if pct > 0.65: return C_WARN   + "▓" + C_RESET
	if pct > 0.40: return C_GOOD   + "▒" + C_RESET
	return C_DIM + "░" + C_RESET

func _ascii_graph(history: Array, max_val: float, height: int) -> String:
	var rows: Array[String] = []
	for _r in height: rows.append("")
	for i in history.size():
		var v      := clampf(history[i], 0.0, max_val)
		var filled := int((v / max_val) * height)
		for r in height:
			rows[r] += _speed_char(v / max_val) if (height - 1 - r) < filled else C_DIM + "·" + C_RESET
	var out := ""
	for r in rows: out += "  " + r + "\n"
	return out

func _ascii_graph_bipolar(history: Array, max_val: float, half_h: int) -> String:
	var total := half_h * 2
	var rows: Array[String] = []
	for _r in total: rows.append("")
	for i in history.size():
		var v    := clampf(history[i], -max_val, max_val)
		var norm := v / max_val
		for r in total:
			if norm >= 0:
				var bar_end := half_h - int(norm * half_h)
				if r >= bar_end and r < half_h:   rows[r] += C_GOOD + "▐" + C_RESET
				elif r == half_h:                  rows[r] += C_DIM + "─" + C_RESET
				else:                              rows[r] += C_DIM + "·" + C_RESET
			else:
				var bar_end := half_h + int(-norm * half_h)
				if r > half_h and r <= bar_end:   rows[r] += C_DANGER + "▐" + C_RESET
				elif r == half_h:                  rows[r] += C_DIM + "─" + C_RESET
				else:                              rows[r] += C_DIM + "·" + C_RESET
	var out := ""
	for r_idx in rows.size():
		var lbl := ""
		if r_idx == 0:           lbl = " " + C_GOOD   + "+%.0fu/s" % max_val + C_RESET
		elif r_idx == half_h:    lbl = " " + C_DIM    + "0" + C_RESET
		elif r_idx == total - 1: lbl = " " + C_DANGER + "-%.0fu/s" % max_val + C_RESET
		out += "  " + rows[r_idx] + lbl + "\n"
	return out

# ── NEW: HU-3 distance graph (green when low = close, red when high = far) ──
func _ascii_graph_hu3(history: Array, max_dist: float, height: int) -> String:
	var rows: Array[String] = []
	for _r in height: rows.append("")
	for i in history.size():
		var v      := clampf(history[i], 0.0, max_dist)
		var pct    := v / max_dist
		var filled := int(pct * height)
		# Color: green when close (low pct), yellow mid, red when far (high pct)
		var col := C_GOOD if pct < 0.3 else (C_WARN if pct < 0.65 else C_DANGER)
		for r in height:
			rows[r] += (col + "█" + C_RESET) if (height - 1 - r) < filled else C_DIM + "·" + C_RESET
	var out := ""
	for r in rows: out += "  " + r + "\n"
	return out
