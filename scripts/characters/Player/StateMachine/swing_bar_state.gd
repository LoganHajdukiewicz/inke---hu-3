extends State
class_name SwingBarState

## Hanging from a horizontal SwingBar, Jak & Daxter style:
##  - Grab it in the air and you START swinging automatically - the swing
##    pumps itself up to full amplitude over a couple of passes
##  - JUMP releases at the current point of the arc: time it as you swing
##    forward-and-up for a big launch, exactly like Jak's swing poles
##  - Hold forward/back to pump harder or brake, crouch to drop straight off
##
## Pure pendulum in the vertical plane perpendicular to the bar's axis.

@export var hang_radius: float = 1.6            # Player hangs this far below the bar
@export var auto_pump_torque: float = 2.6       # Self-pumping strength (the "auto swing")
@export var input_pump_torque: float = 2.2      # Extra pump from holding forward
@export var max_amplitude_degrees: float = 108.0  # Swing tops out just past horizontal
@export var regrab_lockout: float = 0.35        # Seconds before the same bar can catch you again

@export_category("Launch Juice")
## Multiplier on your tangential swing speed at the moment of release.
@export var launch_boost: float = 1.6
## Flat extra HEIGHT added to every jump-off. Crank for bigger air.
@export var launch_up_bonus: float = 7.0
## Flat extra OUTWARD push along the swing direction.
@export var launch_forward_bonus: float = 5.0
@export var min_launch_speed: float = 12.0      # Floor so even lazy releases feel decent
@export var max_launch_speed: float = 32.0      # Cap on release speed

var bar: Node3D = null            # The SwingBar we're on
var _swing_axis: Vector3          # Bar's long axis (we rotate around this)
var _swing_forward: Vector3       # Horizontal direction of the swing plane
var _angle: float = 0.0           # Radians from straight-down; + is toward _swing_forward
var _angular_velocity: float = 0.0

func setup(new_bar: Node3D):
	bar = new_bar

func enter():
	if not bar or not is_instance_valid(bar):
		change_to("FallingState")
		return
	
	_swing_axis = bar.get_bar_axis()
	
	# Swing plane forward = the direction you're FACING, projected
	# perpendicular to the bar. You always swing the way you came in -
	# never flipped backwards. (Velocity is the fallback if facing is
	# parallel to the bar.)
	var facing = -player.global_transform.basis.z
	var h_vel = Vector3(player.velocity.x, 0, player.velocity.z)
	_swing_forward = (facing - _swing_axis * facing.dot(_swing_axis))
	if _swing_forward.length() < 0.15 and h_vel.length() > 0.5:
		_swing_forward = (h_vel - _swing_axis * h_vel.dot(_swing_axis))
	if _swing_forward.length() < 0.1:
		_swing_forward = _swing_axis.cross(Vector3.UP)
	_swing_forward = _swing_forward.normalized()
	if _swing_forward.y != 0.0:
		_swing_forward.y = 0.0
		_swing_forward = _swing_forward.normalized()
	
	# Start at the angle you actually grabbed at (no snap-teleport to the
	# bottom of the arc, which is what caused the backwards flip)
	var anchor = bar.get_grab_point(player.global_position)
	var rel = player.global_position - anchor
	_angle = clampf(atan2(rel.dot(_swing_forward), maxf(-rel.y, 0.05)), -1.2, 1.2)
	
	# Momentum ALWAYS carries forward: swing speed comes from how fast you
	# were going, direction is always the way you're facing.
	var grab_speed = maxf(h_vel.length(), maxf(-player.velocity.y * 0.5, 0.0))
	_angular_velocity = clampf(grab_speed / hang_radius, 1.4, 5.5)
	
	player.velocity = Vector3.ZERO
	
	# Refresh air options - the bar resets your air state
	player.can_double_jump = true
	player.has_double_jumped = false
	player.can_air_dash = true
	player.has_air_dashed = false
	
	# Grab feedback
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.9, 1.15, 0.9), 0.08)
	tween.tween_property(player, "scale", Vector3.ONE, 0.1)

func physics_update(delta: float):
	if not bar or not is_instance_valid(bar):
		change_to("FallingState")
		return
	
	# --- RELEASE: jump = tangential launch, crouch = drop off -------------
	if Input.is_action_just_pressed("jump"):
		_launch()
		return
	if Input.is_action_just_pressed("crouch"):
		_drop_off()
		return
	
	# --- PENDULUM ----------------------------------------------------------
	var g = absf(player.get_gravity().y)
	if g < 0.01:
		g = 9.8
	
	# Gravity torque
	var ang_accel = -(g / hang_radius) * sin(_angle)
	
	# AUTO-PUMP: push in the direction of travel until we hit max amplitude.
	# This is what makes the bar swing itself like Jak's poles.
	var max_amp = deg_to_rad(max_amplitude_degrees)
	var energy_amp = _current_amplitude(g)
	if energy_amp < max_amp and absf(_angular_velocity) > 0.05:
		ang_accel += auto_pump_torque * signf(_angular_velocity)
	
	# Player pump/brake with forward/back (relative to swing plane)
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if absf(input_dir.y) > 0.2:
		var camera_basis = player.get_node("CameraController").transform.basis
		var wish = (camera_basis * Vector3(input_dir.x, 0, input_dir.y))
		var along = wish.dot(_swing_forward)
		if energy_amp < max_amp or along * signf(_angular_velocity) < 0.0:
			ang_accel += input_pump_torque * along * signf(1.0)
	
	_angular_velocity += ang_accel * delta
	_angle += _angular_velocity * delta
	
	# Hard clamp at the amplitude limit - bleed energy instead of looping over
	if absf(_angle) > max_amp:
		_angle = max_amp * signf(_angle)
		_angular_velocity = -_angular_velocity * 0.35
	
	# Place the player on the arc (kinematic - the pendulum owns position)
	var anchor = bar.get_grab_point(player.global_position)
	var offset = (Vector3.DOWN * cos(_angle) + _swing_forward * sin(_angle)) * hang_radius
	player.global_position = anchor + offset
	player.velocity = _tangent_dir() * _angular_velocity * hang_radius
	
	# BODY TILT: stay aligned with the swing rod - head toward the bar,
	# like a human hanging on. Fully sideways = body horizontal, head in.
	var body_up = (anchor - player.global_position).normalized()
	var travel = signf(_angular_velocity) if absf(_angular_velocity) > 0.1 else 1.0
	var face = _swing_forward * travel
	var fwd = (face - body_up * face.dot(body_up)).normalized()
	var z_axis = -fwd
	var x_axis = body_up.cross(z_axis).normalized()
	var target_basis = Basis(x_axis, body_up, z_axis).orthonormalized()
	# Track hard - the swing moves fast and a lazy slerp visibly lags,
	# leaving Inke facing up when she should be sideways-head-in
	player.global_transform.basis = player.global_transform.basis.slerp(target_basis, minf(30.0 * delta, 1.0)).orthonormalized()

func _tangent_dir() -> Vector3:
	"""Direction of travel along the arc for positive angular velocity."""
	return (Vector3.DOWN * -sin(_angle) + _swing_forward * cos(_angle)).normalized()

func _current_amplitude(g: float) -> float:
	"""Peak angle this swing's energy will reach (pendulum energy identity)."""
	var cos_peak = cos(_angle) - (_angular_velocity * _angular_velocity * hang_radius) / (2.0 * g)
	return acos(clampf(cos_peak, -1.0, 1.0))

func _launch():
	"""Release along the arc tangent - timing the jump IS the skill.
	Then add the flat up/forward juice bonuses (Inspector-tunable)."""
	var travel = signf(_angular_velocity) if _angular_velocity != 0.0 else 1.0
	var v = _tangent_dir() * _angular_velocity * hang_radius * launch_boost
	
	var speed = v.length()
	if speed < min_launch_speed:
		v = (v.normalized() if speed > 0.1 else _swing_forward * travel) * min_launch_speed
	
	# Never launch downward off a swing bar - flatten and keep the speed
	if v.y < 0.0:
		var flat = Vector3(v.x, 0, v.z)
		v = (flat.normalized() if flat.length() > 0.1 else _swing_forward * travel) * v.length() * 0.9
		v.y = 0.0
	
	# THE JUICE: flat height + outward push on top of the earned speed
	v += _swing_forward * travel * launch_forward_bonus
	v.y += launch_up_bonus
	
	if v.length() > max_launch_speed:
		v = v.normalized() * max_launch_speed
	
	player.velocity = v
	_set_upright()
	_detach()
	
	# Launch flourish
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.85, 1.2, 0.85), 0.08)
	tween.tween_property(player, "scale", Vector3.ONE, 0.15)
	
	change_to("FallingState")

func _drop_off():
	player.velocity = Vector3(0, -1.0, 0)
	_set_upright()
	_detach()
	change_to("FallingState")

func _set_upright():
	"""Undo the swing tilt: back to feet-down, keeping the yaw we're facing."""
	var fwd = -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = _swing_forward
	fwd = fwd.normalized()
	player.rotation = Vector3(0, atan2(-fwd.x, -fwd.z), 0)

func _detach():
	if bar and is_instance_valid(bar):
		bar.notify_released(player, regrab_lockout)
	bar = null

func get_speed() -> float:
	return absf(_angular_velocity) * hang_radius if player else 0.0

func exit():
	if bar and is_instance_valid(bar):
		bar.notify_released(player, regrab_lockout)
	bar = null
	_set_upright()
	player.scale = Vector3.ONE
