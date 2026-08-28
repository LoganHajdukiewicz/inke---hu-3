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
@export var launch_boost: float = 1.25          # Multiplier on tangential speed at release
@export var min_launch_speed: float = 9.0       # Floor so even lazy releases feel decent
@export var max_launch_speed: float = 24.0      # Cap on release speed
@export var regrab_lockout: float = 0.35        # Seconds before the same bar can catch you again

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
	
	# Swing plane forward = the horizontal direction the player was moving,
	# projected perpendicular to the bar. Falling straight down? Use facing.
	var h_vel = Vector3(player.velocity.x, 0, player.velocity.z)
	var seed_dir = h_vel if h_vel.length() > 1.0 else -player.global_transform.basis.z
	_swing_forward = (seed_dir - _swing_axis * seed_dir.dot(_swing_axis))
	if _swing_forward.length() < 0.1:
		_swing_forward = _swing_axis.cross(Vector3.UP)
	_swing_forward = _swing_forward.normalized()
	
	# Convert grab momentum into initial swing energy (tangential speed)
	var tangent = _tangent_dir()
	_angle = 0.0
	_angular_velocity = clampf(player.velocity.dot(tangent) / hang_radius, -4.0, 4.0)
	if absf(_angular_velocity) < 1.2:
		_angular_velocity = 1.2 * signf(_angular_velocity if _angular_velocity != 0.0 else 1.0)
	
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
	
	# Face along the swing direction
	var face = _swing_forward * signf(_angular_velocity if absf(_angular_velocity) > 0.1 else 1.0)
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-face.x, -face.z), 10.0 * delta)

func _tangent_dir() -> Vector3:
	"""Direction of travel along the arc for positive angular velocity."""
	return (Vector3.DOWN * -sin(_angle) + _swing_forward * cos(_angle)).normalized()

func _current_amplitude(g: float) -> float:
	"""Peak angle this swing's energy will reach (pendulum energy identity)."""
	var cos_peak = cos(_angle) - (_angular_velocity * _angular_velocity * hang_radius) / (2.0 * g)
	return acos(clampf(cos_peak, -1.0, 1.0))

func _launch():
	"""Release along the arc tangent - timing the jump IS the skill."""
	var v = _tangent_dir() * _angular_velocity * hang_radius * launch_boost
	
	var speed = v.length()
	if speed < min_launch_speed:
		v = (v.normalized() if speed > 0.1 else _swing_forward) * min_launch_speed
	elif speed > max_launch_speed:
		v = v.normalized() * max_launch_speed
	
	# Never launch downward off a swing bar - flatten and keep the speed
	if v.y < 0.0:
		var flat = Vector3(v.x, 0, v.z)
		v = (flat.normalized() if flat.length() > 0.1 else _swing_forward) * v.length() * 0.9
		v.y = 3.0
	
	player.velocity = v
	_detach()
	
	# Launch flourish
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.85, 1.2, 0.85), 0.08)
	tween.tween_property(player, "scale", Vector3.ONE, 0.15)
	
	change_to("FallingState")

func _drop_off():
	player.velocity = Vector3(0, -1.0, 0)
	_detach()
	change_to("FallingState")

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
	player.scale = Vector3.ONE
