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
var state_machine: Node = null

# ── UI Nodes ──────────────────────────────────────────────────
var bg_panel: ColorRect
var label_left: RichTextLabel
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
var was_on_floor: bool = true
var tracking_jump: bool = false

# ── Speed / velocity history for graphs ───────────────────────
const GRAPH_SAMPLES: int = 80
var speed_history: Array[float] = []
var vert_history: Array[float] = []
var gravity_mult_history: Array[float] = []

# ── Session peak stats ────────────────────────────────────────
var session_peak_speed: float = 0.0
var session_peak_fall_speed: float = 0.0
var session_peak_jump_height: float = 0.0
var session_jump_count: int = 0
var session_dash_count: int = 0
var session_wall_jump_count: int = 0
var session_double_jump_count: int = 0

# ── State change tracking ─────────────────────────────────────
var last_state_name: String = ""
var state_duration: float = 0.0
var previous_state_name: String = ""
var previous_state_duration: float = 0.0

# ── Dash tracking ─────────────────────────────────────────────
var last_dash_distance: float = 0.0
var dash_was_active: bool = false

# ── Wall jump / double jump event tracking ────────────────────
var wall_jump_was_active: bool = false
var double_jump_was_active: bool = false

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
		gravity_mult_history.append(0.0)

# ─── Build UI ─────────────────────────────────────────────────
func _build_ui() -> void:
	bg_panel = ColorRect.new()
	bg_panel.name = "DebugBG"
	bg_panel.color = Color(0.0, 0.04, 0.06, 0.88)
	bg_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg_panel.position = Vector2(0, 0)
	bg_panel.size = Vector2(780, 1020)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_panel)

	var accent := ColorRect.new()
	accent.color = Color(0.0, 1.0, 0.8, 1.0)
	accent.position = Vector2(0, 0)
	accent.size = Vector2(780, 3)
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
	label_left.size = Vector2(378, 990)
	label_left.add_theme_font_size_override("normal_font_size", 12)
	label_left.add_theme_font_size_override("bold_font_size", 12)
	label_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_panel.add_child(label_left)

	var div := ColorRect.new()
	div.color = Color(0.0, 1.0, 0.8, 0.15)
	div.position = Vector2(390, 26)
	div.size = Vector2(1, 990)
	bg_panel.add_child(div)

	label_right = RichTextLabel.new()
	label_right.bbcode_enabled = true
	label_right.scroll_active = false
	label_right.fit_content = true
	label_right.position = Vector2(394, 26)
	label_right.size = Vector2(378, 990)
	label_right.add_theme_font_size_override("normal_font_size", 12)
	label_right.add_theme_font_size_override("bold_font_size", 12)
	label_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_panel.add_child(label_right)

# ─── Find runtime references ──────────────────────────────────
func _find_references() -> void:
	game_manager       = get_node_or_null("/root/GameManager")
	checkpoint_manager = get_node_or_null("/root/CheckpointManager")
	var players := get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0] as CharacterBody3D
		if player and player.has_node("StateMachine"):
			state_machine = player.get_node("StateMachine")

# ═════════════════════════════════════════════════════════════
func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("display"):
		_set_visible(not visible_overlay)
		get_viewport().set_input_as_handled()

func _set_visible(v: bool) -> void:
	visible_overlay = v
	bg_panel.visible = v

# ═════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	_tick += delta
	if not player or not is_instance_valid(player):
		if visible_overlay:
			_find_references()
		return
	_track_jump(delta)
	_track_speed_history()
	_track_gravity_history()
	_track_state_duration(delta)
	_track_session_peaks()
	_track_dash_events()
	_track_wall_jump_events()
	_track_double_jump_events()
	if not visible_overlay:
		return
	_update_left_column(delta)
	_update_right_column()

# ─── Jump tracking ────────────────────────────────────────────
func _track_jump(delta: float) -> void:
	var on_floor := player.is_on_floor()

	if was_on_floor and not on_floor:
		launch_y = player.global_position.y
		launch_pos = player.global_position
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
		var land_pos := player.global_position
		last_jump_horizontal_distance = Vector2(
			land_pos.x - launch_pos.x,
			land_pos.z - launch_pos.z
		).length()
		if last_jump_height > session_peak_jump_height:
			session_peak_jump_height = last_jump_height
		tracking_jump = false

	was_on_floor = on_floor

# ─── Speed / gravity history ──────────────────────────────────
func _track_speed_history() -> void:
	speed_history.append(Vector2(player.velocity.x, player.velocity.z).length())
	vert_history.append(player.velocity.y)
	if speed_history.size() > GRAPH_SAMPLES:
		speed_history.pop_front()
		vert_history.pop_front()

func _track_gravity_history() -> void:
	var gm: float = 1.0
	if state_machine and state_machine.get("current_state") != null:
		var cs = state_machine.current_state
		if cs and cs.get("gravity_multiplier") != null:
			gm = cs.get("gravity_multiplier") as float
	gravity_mult_history.append(gm)
	if gravity_mult_history.size() > GRAPH_SAMPLES:
		gravity_mult_history.pop_front()

# ─── State duration tracking ──────────────────────────────────
func _track_state_duration(delta: float) -> void:
	if not state_machine:
		return
	var cs = state_machine.get("current_state")
	if not cs or not cs.get_script():
		return
	var name: String = cs.get_script().get_global_name()
	if name != last_state_name:
		previous_state_name = last_state_name
		previous_state_duration = state_duration
		last_state_name = name
		state_duration = 0.0
	else:
		state_duration += delta

# ─── Session peak tracking ────────────────────────────────────
func _track_session_peaks() -> void:
	var h_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if h_speed > session_peak_speed:
		session_peak_speed = h_speed
	if player.velocity.y < -session_peak_fall_speed:
		session_peak_fall_speed = -player.velocity.y

# ─── Dash event tracking ──────────────────────────────────────
func _track_dash_events() -> void:
	var is_dashing := _current_state_name() == "DodgeDashState"
	if is_dashing and not dash_was_active:
		session_dash_count += 1
	if not is_dashing and dash_was_active:
		if state_machine and state_machine.get("states") != null:
			var ds = state_machine.states.get("dodgedashstate")
			if ds:
				var start_pos: Variant = ds.get("dash_start_position")
				if start_pos is Vector3:
					last_dash_distance = player.global_position.distance_to(start_pos as Vector3)
	dash_was_active = is_dashing

# ─── Wall jump / double jump event tracking ───────────────────
func _track_wall_jump_events() -> void:
	var is_wj := _current_state_name() == "WallJumpingState"
	if is_wj and not wall_jump_was_active:
		session_wall_jump_count += 1
	wall_jump_was_active = is_wj

func _track_double_jump_events() -> void:
	var is_dj := _current_state_name() == "DoubleJumpState"
	if is_dj and not double_jump_was_active:
		session_double_jump_count += 1
	double_jump_was_active = is_dj

# ─── Helper: current state name ───────────────────────────────
func _current_state_name() -> String:
	if not state_machine:
		return ""
	var cs = state_machine.get("current_state")
	if cs and cs.get_script():
		return cs.get_script().get_global_name()
	return ""

# ═════════════════════════════════════════════════════════════
#  LEFT COLUMN — velocity, graphs, contact, physics
# ═════════════════════════════════════════════════════════════
func _update_left_column(delta: float) -> void:
	var txt := ""

	# ── Performance ───────────────────────────────────────────
	var fps := Engine.get_frames_per_second()
	var fps_col: String = C_GOOD if fps >= 55 else (C_WARN if fps >= 30 else C_DANGER)
	txt += _header("◆ PERFORMANCE")
	txt += _row("FPS",        fps_col + str(fps) + C_RESET)
	txt += _row("Physics Hz", C_VAL + str(Engine.physics_ticks_per_second) + C_RESET)
	txt += _row("δ frame",    C_DIM + "%.4f s" % delta + C_RESET)
	txt += "\n"

	if not player or not is_instance_valid(player):
		txt += C_DANGER + "  !! Player not found !!" + C_RESET + "\n"
		label_left.text = txt
		return

	# ── World position ────────────────────────────────────────
	var pos := player.global_position
	txt += _header("◆ WORLD POSITION")
	txt += _row("X", C_VAL + "%.3f" % pos.x + C_RESET)
	txt += _row("Y", C_VAL + "%.3f" % pos.y + C_RESET)
	txt += _row("Z", C_VAL + "%.3f" % pos.z + C_RESET)
	txt += "\n"

	# ── Velocity ──────────────────────────────────────────────
	var vel     := player.velocity
	var h_speed := Vector2(vel.x, vel.z).length()
	var h_col: String = C_GOOD if h_speed < 20 else (C_WARN if h_speed < 50 else C_DANGER)
	txt += _header("◆ VELOCITY")
	txt += _row("vel.X",    C_VAL + "%.3f" % vel.x + C_RESET)
	txt += _row("vel.Y",    _vert_col(vel.y) + "%.3f" % vel.y + C_RESET)
	txt += _row("vel.Z",    C_VAL + "%.3f" % vel.z + C_RESET)
	txt += _row("H-speed",  h_col + "%.2f u/s" % h_speed + C_RESET)
	txt += _row("V-speed",  _vert_col(vel.y) + "%.2f u/s" % vel.y + C_RESET)
	txt += _row("3D mag",   C_VAL + "%.2f u/s" % vel.length() + C_RESET)
	txt += _row("H angle",  C_DIM + "%.1f°" % rad_to_deg(atan2(vel.x, vel.z)) + C_RESET)
	txt += "\n"

	# ── H-speed graph ─────────────────────────────────────────
	txt += _header("◆ H-SPEED GRAPH  [0 ──► 60 u/s]")
	txt += _ascii_graph(speed_history, 60.0, 8)
	txt += "\n"

	# ── V-speed graph ─────────────────────────────────────────
	txt += _header("◆ V-SPEED GRAPH  [fall ◄─ 0 ─► rise]")
	txt += _ascii_graph_bipolar(vert_history, 30.0, 5)
	txt += "\n"

	# ── Gravity multiplier graph ───────────────────────────────
	txt += _header("◆ GRAVITY MULTIPLIER  [0 ──► 4x]")
	txt += _ascii_graph(gravity_mult_history, 4.0, 5)
	txt += "\n"

	# ── Contact state ─────────────────────────────────────────
	txt += _header("◆ CONTACT STATE")
	txt += _row("On floor",   _bool(player.is_on_floor()))
	txt += _row("On wall",    _bool(player.is_on_wall()))
	txt += _row("On ceiling", _bool(player.is_on_ceiling()))
	txt += _row("On ice",     _bool(_prop(player, "is_on_ice", false) as bool))
	txt += _row("Sprung",     _bool(_prop(player, "is_being_sprung", false) as bool))
	txt += "\n"

	# ── Physics vars ──────────────────────────────────────────
	txt += _header("◆ PHYSICS VARS")
	txt += _row("Gravity",      C_VAL + "%.4f" % (_prop(player, "gravity", 9.8) as float) + C_RESET)
	txt += _row("Grav default", C_DIM + "%.4f" % (_prop(player, "gravity_default", 9.8) as float) + C_RESET)
	txt += _row("Controls off", _bool(_prop(player, "controls_disabled", false) as bool))

	label_left.text = txt

# ═════════════════════════════════════════════════════════════
#  RIGHT COLUMN — state, internals, jump stats, abilities, session
# ═════════════════════════════════════════════════════════════
func _update_right_column() -> void:
	var txt := ""

	if not player or not is_instance_valid(player):
		label_right.text = ""
		return

	# ── State machine ─────────────────────────────────────────
	txt += _header("◆ STATE MACHINE")
	txt += _row("Current",   C_GOOD + last_state_name + C_RESET)
	txt += _row("Time in",   C_VAL  + "%.3f s" % state_duration + C_RESET)
	txt += _row("Previous",  C_DIM  + previous_state_name + C_RESET)
	txt += _row("Prev time", C_DIM  + "%.3f s" % previous_state_duration + C_RESET)
	txt += "\n"

	# ── Active state internals ────────────────────────────────
	# Reads live data directly from the active state node so every
	# number reflects what the state machine is actually doing.
	txt += _header("◆ ACTIVE STATE INTERNALS")
	if state_machine and state_machine.get("current_state") != null:
		var cs = state_machine.current_state
		match last_state_name:

			"JumpingState":
				var jt: float  = _prop(cs, "jump_time", 0.0)
				var gm: float  = _prop(cs, "gravity_multiplier", 1.0)
				var lj: bool   = _prop(cs, "is_long_jump", false)
				var dm: bool   = _prop(cs, "used_dash_momentum", false)
				var jv: float  = _prop(cs, "jump_velocity", 15.0)
				txt += _row("Jump time",  C_VAL + "%.3f s" % jt + C_RESET)
				txt += _row("Jump vel",   C_VAL + "%.2f u/s" % jv + C_RESET)
				txt += _row("Gravity x",  _grav_col(gm) + "%.2fx" % gm + C_RESET)
				txt += _row("Long jump",  _bool(lj))
				txt += _row("Dash jump",  _bool(dm))

			"FallingState":
				var ft: float  = _prop(cs, "fall_time", 0.0)
				var iv: float  = _prop(cs, "initial_fall_velocity", 0.0)
				# Mirror the gravity curve from falling_state.gd
				var gm: float = 1.0
				if ft < 0.1:
					gm = 1.0
				elif ft < 0.3:
					gm = lerp(1.0, 2.2, (ft - 0.1) / 0.2)
				else:
					gm = 2.2
				txt += _row("Fall time",  C_VAL + "%.3f s" % ft + C_RESET)
				txt += _row("Init vel.Y", C_DIM + "%.2f u/s" % iv + C_RESET)
				txt += _row("Gravity x",  _grav_col(gm) + "%.2fx" % gm + C_RESET)
				txt += _row("Terminal?",  _bool(player.velocity.y <= -30.0))

			"DoubleJumpState":
				var jt: float  = _prop(cs, "jump_elapsed_time", 0.0)
				var at: float  = _prop(cs, "ascent_time", 0.15)
				var pt: float  = _prop(cs, "peak_time", 0.05)
				var dm: float  = _prop(cs, "descent_multiplier", 3.0)
				var jv: float  = _prop(cs, "jump_velocity", 16.0)
				var phase := "ASCENT"
				if jt >= at and jt < at + pt:
					phase = "PEAK"
				elif jt >= at + pt:
					phase = "DESCENT"
				txt += _row("Elapsed",    C_VAL + "%.3f s" % jt + C_RESET)
				txt += _row("Init vel",   C_VAL + "%.2f u/s" % jv + C_RESET)
				txt += _row("Phase",      C_WARN + phase + C_RESET)
				txt += _row("Descend x",  C_VAL + "%.1fx" % dm + C_RESET)

			"DodgeDashState":
				var dt: float  = _prop(cs, "dash_timer", 0.0)
				var dd: float  = _prop(cs, "dash_duration", 0.3)
				var ds: float  = _prop(cs, "dash_speed", 100.0)
				var cd: float  = _prop(cs, "cooldown_timer", 0.0)
				var air: bool  = _prop(cs, "is_air_dash", false)
				var pct: float = dt / dd if dd > 0.0 else 0.0
				txt += _row("Timer",     C_VAL + "%.3f / %.3f s" % [dt, dd] + C_RESET)
				txt += _mini_bar_row("Progress", pct)
				txt += _row("Speed",     C_VAL + "%.1f u/s" % ds + C_RESET)
				txt += _row("Cooldown",  (C_WARN if cd > 0 else C_GOOD) + "%.3f s" % cd + C_RESET)
				txt += _row("Air dash",  _bool(air))

			"WallJumpingState":
				var wt: float  = _prop(cs, "wall_jump_timer", 0.0)
				var ml: float  = _prop(cs, "momentum_lock_duration", 0.35)
				var tl: float  = _prop(cs, "total_lock_time", 0.5)
				var wdir: Variant = cs.get("wall_direction")
				var phase2 := "LOCK"
				if wt >= ml and wt < tl:
					phase2 = "FADE"
				elif wt >= tl:
					phase2 = "FREE"
				txt += _row("Timer",     C_VAL + "%.3f s" % wt + C_RESET)
				txt += _row("Phase",     C_WARN + phase2 + C_RESET)
				txt += _mini_bar_row("Lock", clampf(wt / ml if ml > 0 else 0.0, 0.0, 1.0))
				if wdir is Vector3:
					var wd := wdir as Vector3
					txt += _row("Wall dir", C_DIM + "(%.2f, %.2f, %.2f)" % [wd.x, wd.y, wd.z] + C_RESET)
				txt += _row("Jmp vel",   C_VAL + "%.2f u/s" % (_prop(cs, "wall_jump_velocity", 5.0) as float) + C_RESET)

			"WallSlidingState":
				var ss: float  = _prop(cs, "slide_speed", -2.0)
				var ms: float  = _prop(cs, "min_slide_speed", -5.0)
				txt += _row("Slide spd", C_VAL + "%.2f u/s" % ss + C_RESET)
				txt += _row("Min spd",   C_DIM + "%.2f u/s" % ms + C_RESET)
				txt += _row("Vel.Y now", _vert_col(player.velocity.y) + "%.2f u/s" % player.velocity.y + C_RESET)

			"RailGrindingState":
				var gs: float  = _prop(cs, "grind_exit_speed", 15.0)
				var ls: float  = _prop(cs, "lerp_speed", 50.0)
				txt += _row("Grind spd", C_VAL + "%.1f u/s" % gs + C_RESET)
				txt += _row("Lerp spd",  C_DIM + "%.1f" % ls + C_RESET)
				txt += _row("H-speed",   C_GOOD + "%.2f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)

			"GrappleHookState":
				var mode: Variant = cs.get("grapple_mode")
				var gp: Variant   = cs.get("grapple_point")
				var rl: float     = _prop(cs, "rope_length", 0.0)
				txt += _row("Mode",      C_WARN + str(mode) + C_RESET)
				txt += _row("Rope len",  C_VAL + "%.2f u" % rl + C_RESET)
				if gp is Vector3:
					var dist: float = player.global_position.distance_to(gp as Vector3)
					txt += _row("To target", C_VAL + "%.2f u" % dist + C_RESET)

			"SlidingState":
				var sv: Variant = cs.get("slide_velocity")
				if sv is Vector3:
					txt += _row("Slide spd", C_VAL + "%.2f u/s" % (sv as Vector3).length() + C_RESET)
				txt += _row("H-speed",   C_VAL + "%.2f u/s" % Vector2(player.velocity.x, player.velocity.z).length() + C_RESET)

			_:
				txt += C_DIM + "  (no extra data for this state)\n" + C_RESET
	else:
		txt += C_DIM + "  StateMachine not ready\n" + C_RESET
	txt += "\n"

	# ── Jump stats ────────────────────────────────────────────
	txt += _header("◆ JUMP STATS")
	if tracking_jump:
		var cur_h    := maxf(0.0, player.global_position.y - launch_y)
		var cur_dist := Vector2(
			player.global_position.x - launch_pos.x,
			player.global_position.z - launch_pos.z
		).length()
		txt += _row("Height NOW",  C_WARN + "%.3f u" % cur_h + C_RESET)
		txt += _row("Horiz dist",  C_WARN + "%.2f u" % cur_dist + C_RESET)
		txt += _row("Air time",    C_WARN + "%.3f s" % jump_airtime_counter + C_RESET)
		txt += _row("Peak H-spd",  C_VAL  + "%.2f u/s" % last_jump_apex_speed + C_RESET)
		txt += _row("Launch Y",    C_DIM  + "%.3f" % launch_y + C_RESET)
	else:
		txt += _row("Last height", C_VAL + "%.3f u" % last_jump_height + C_RESET)
		txt += _row("Last dist",   C_VAL + "%.2f u" % last_jump_horizontal_distance + C_RESET)
		txt += _row("Last air t",  C_VAL + "%.3f s" % last_jump_airtime + C_RESET)
		txt += _row("Apex H-spd",  C_VAL + "%.2f u/s" % last_jump_apex_speed + C_RESET)
	txt += "\n"

	# ── Ability readiness ─────────────────────────────────────
	txt += _header("◆ ABILITY READINESS")
	var has_dj: bool   = _prop(player, "can_double_jump",  false)
	var used_dj: bool  = _prop(player, "has_double_jumped", false)
	var has_ad: bool   = _prop(player, "can_air_dash",     false)
	var used_ad: bool  = _prop(player, "has_air_dashed",   false)
	var can_lj: bool   = _prop(player, "can_long_jump",    false)
	var lj_t: float    = _prop(player, "long_jump_timer",  0.0)
	var lj_w: float    = _prop(player, "long_jump_window", 0.3)
	var sdm_raw: Variant = _prop(player, "stored_dash_momentum", null)
	var sdm_len: float = (sdm_raw as Vector3).length() if sdm_raw is Vector3 else 0.0
	var wj_cd: float   = _prop(player, "wall_jump_cooldown", 0.0)

	txt += _row("Double jump", (C_GOOD + "READY" if has_dj and not used_dj else (C_DIM + "used" if used_dj else C_DANGER + "locked")) + C_RESET)
	txt += _row("Air dash",    (C_GOOD + "READY" if has_ad and not used_ad else (C_DIM + "used" if used_ad else C_DANGER + "locked")) + C_RESET)
	txt += _row("Wall jump",   (C_GOOD + "READY" if wj_cd <= 0.0 else C_WARN + "%.3f s" % wj_cd) + C_RESET)

	var dash_cd: float   = 0.0
	var dash_ready: bool = true
	if state_machine and state_machine.get("states") != null:
		var ds = state_machine.states.get("dodgedashstate")
		if ds:
			dash_cd    = _prop(ds, "cooldown_timer", 0.0) as float
			dash_ready = _prop(ds, "can_dash", true) as bool
	txt += _row("Dash",        (C_GOOD + "READY" if dash_ready else C_WARN + "%.3f s" % dash_cd) + C_RESET)
	txt += _row("Long jump",   (C_GOOD + "READY  %.2fs" % lj_t if can_lj else C_DIM + "—") + C_RESET)
	txt += _mini_bar_row("LJ window", lj_t / lj_w if lj_w > 0 else 0.0)
	txt += _row("Dash mom",    (C_WARN + "%.2f u/s" % sdm_len if sdm_len > 0.01 else C_DIM + "none") + C_RESET)
	txt += "\n"

	# ── Damage state ──────────────────────────────────────────
	txt += _header("◆ DAMAGE STATE")
	var health: int  = game_manager.get_player_health() if game_manager else 0
	var max_hp: int  = game_manager.get_player_max_health() if game_manager else 3
	var is_inv: bool = _prop(player, "is_invulnerable", false)
	var inv_t: float = _prop(player, "invulnerability_timer", 0.0)
	var inv_d: float = _prop(player, "invulnerability_duration", 1.5)
	var hp_col: String = C_GOOD if health >= max_hp else (C_WARN if health > 1 else C_DANGER)
	txt += _row("Health",   hp_col + _heart_bar(health, max_hp) + " %d/%d" % [health, max_hp] + C_RESET)
	txt += _row("Dead",     _bool(_prop(player, "is_dead", false) as bool, true))
	txt += _row("Invuln",   _bool(is_inv))
	if is_inv:
		txt += _row("Inv timer", C_WARN + "%.2f / %.2f s" % [inv_t, inv_d] + C_RESET)
		txt += _mini_bar_row("Inv bar", inv_t / inv_d if inv_d > 0 else 0.0)
	txt += "\n"

	# ── Session stats ─────────────────────────────────────────
	txt += _header("◆ SESSION STATS")
	txt += _row("Jumps",        C_VAL + str(session_jump_count) + C_RESET)
	txt += _row("Double jumps", C_VAL + str(session_double_jump_count) + C_RESET)
	txt += _row("Wall jumps",   C_VAL + str(session_wall_jump_count) + C_RESET)
	txt += _row("Dashes",       C_VAL + str(session_dash_count) + C_RESET)
	txt += _row("Peak H-spd",   C_WARN + "%.2f u/s" % session_peak_speed + C_RESET)
	txt += _row("Peak fall",    C_WARN + "%.2f u/s" % session_peak_fall_speed + C_RESET)
	txt += _row("Peak height",  C_WARN + "%.3f u" % session_peak_jump_height + C_RESET)
	if last_dash_distance > 0.0:
		txt += _row("Last dash d",  C_DIM + "%.2f u" % last_dash_distance + C_RESET)
	txt += "\n"

	# ── Economy / checkpoint ──────────────────────────────────
	txt += _header("◆ ECONOMY")
	if game_manager:
		txt += _row("Gears", C_VAL + str(game_manager.get_gear_count()) + C_RESET)
		txt += _row("CRED",  C_VAL + str(game_manager.get_CRED_count()) + C_RESET)
	txt += "\n"

	txt += _header("◆ CHECKPOINT")
	if checkpoint_manager:
		var has_cp: bool = checkpoint_manager.has_active_checkpoint()
		txt += _row("Active", _bool(has_cp))
		if has_cp:
			var cp: Vector3 = checkpoint_manager.get_checkpoint_position()
			var dist_to_cp: float = player.global_position.distance_to(cp)
			txt += _row("Dist",  C_DIM + "%.1f u" % dist_to_cp + C_RESET)
			txt += _row("Pos",   C_DIM + "(%.1f, %.1f, %.1f)" % [cp.x, cp.y, cp.z] + C_RESET)
	else:
		txt += C_DIM + "  CheckpointManager not found\n" + C_RESET

	label_right.text = txt

# ═════════════════════════════════════════════════════════════
#  FORMATTING HELPERS
# ═════════════════════════════════════════════════════════════

# NOTE: Named _prop (not _get) to avoid conflicting with the
# built-in Object._get(StringName) -> Variant signature.
func _prop(obj: Object, prop: String, fallback: Variant) -> Variant:
	if obj and obj.has_method("get"):
		var v = obj.get(prop)
		if v != null:
			return v
	return fallback

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
	for i in max_hp:
		s += "♥" if i < hp else "♡"
	return s

func _mini_bar_row(label: String, pct: float) -> String:
	pct = clampf(pct, 0.0, 1.0)
	const W := 18
	var filled := int(pct * W)
	var col: String = C_GOOD if pct > 0.5 else (C_WARN if pct > 0.2 else C_DANGER)
	var bar := C_DIM + "[" + C_RESET + col + "█".repeat(filled) + C_RESET + C_DIM + "░".repeat(W - filled) + "]" + C_RESET
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
		if r_idx == 0:           lbl = " " + C_GOOD   + "+%.0fu/s" % max_val + C_RESET
		elif r_idx == half_h:    lbl = " " + C_DIM    + "0" + C_RESET
		elif r_idx == total - 1: lbl = " " + C_DANGER + "-%.0fu/s" % max_val + C_RESET
		out += "  " + rows[r_idx] + lbl + "\n"
	return out
